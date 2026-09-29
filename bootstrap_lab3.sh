#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Laboratorio 3 - DevOps ESEN
# Bootstrap de Google Cloud para Incident API
#
# Preparación del entorno:
# - Artifact Registry y cleanup policy
# - Firestore (default)
# - identidades separadas para publicación, despliegue y runtime
# - Workload Identity Federation para GitHub Actions
# - revisión baseline de Cloud Run
# - validación de /health y /incidents
#
# Debe ejecutarse desde la raíz del repositorio utilizado en el Laboratorio 2.
# ============================================================================

: "${PROJECT_ID:?lab03-devops}"
: "${GITHUB_OWNER:?astrid-esen}"
: "${GITHUB_REPOSITORY:?lab02-devops}"

REGION="${REGION:-us-central1}"

AR_REPOSITORY="devops-images"
IMAGE_NAME="incident-api"
RUN_SERVICE="incident-api"

POOL_ID="github-lab3"
PROVIDER_ID="github"

PUBLISHER_SA_NAME="gha-publisher"
DEPLOYER_SA_NAME="gha-deployer"
RUNTIME_SA_NAME="incident-api-runtime"

PUBLISHER_SA="${PUBLISHER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
DEPLOYER_SA="${DEPLOYER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA="${RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

GITHUB_REPO="${GITHUB_OWNER}/${GITHUB_REPOSITORY}"
BASELINE_REVISION="${RUN_SERVICE}-baseline"
BASELINE_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}/${IMAGE_NAME}:baseline"

section() {
  printf '\n============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

fail() {
  printf '\nERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "No se encontró el comando requerido: $1"
}

# Ejecuta nuevamente un comando que puede fallar temporalmente por propagación
# eventual de IAM. Se utiliza únicamente en operaciones IAM concretas.
retry_iam() {
  local description="$1"
  shift

  local max_attempts=18
  local delay_seconds=10
  local attempt

  for attempt in $(seq 1 "$max_attempts"); do
    if "$@"; then
      return 0
    fi

    if [[ "$attempt" -lt "$max_attempts" ]]; then
      printf 'IAM todavía no completó "%s" (intento %s/%s). Reintentando en %s s...\n' \
        "$description" "$attempt" "$max_attempts" "$delay_seconds" >&2
      sleep "$delay_seconds"
    fi
  done

  fail "No fue posible completar la operación IAM: ${description}"
}

section "1. Validaciones locales"

for cmd in gcloud docker curl git; do
  require_command "$cmd"
done

[[ -f "Dockerfile" ]] || fail "Debe ejecutar el script desde la raíz del repositorio: no se encontró Dockerfile."
[[ -d "app" ]] || fail "Debe ejecutar el script desde la raíz del repositorio: no se encontró app/."

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "El directorio actual no pertenece a un repositorio Git."

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1 || true)"
[[ -n "$ACTIVE_ACCOUNT" ]] || fail "No existe una cuenta activa en gcloud. Ejecute: gcloud auth login"

docker info >/dev/null 2>&1 \
  || fail "Docker no está disponible. Verifique que el daemon esté en ejecución."

printf 'Cuenta activa de gcloud: %s\n' "$ACTIVE_ACCOUNT"
printf 'Proyecto solicitado:       %s\n' "$PROJECT_ID"
printf 'Región:                    %s\n' "$REGION"
printf 'Repositorio GitHub:        %s\n' "$GITHUB_REPO"

section "2. Proyecto y facturación"

gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1 \
  || fail "El proyecto ${PROJECT_ID} no existe o la cuenta activa no puede acceder a él."

gcloud config set project "$PROJECT_ID" >/dev/null

PROJECT_NUMBER="$(
  gcloud projects describe "$PROJECT_ID" \
    --format='value(projectNumber)'
)"

[[ -n "$PROJECT_NUMBER" ]] || fail "No fue posible obtener el número del proyecto."

BILLING_ENABLED="$(
  gcloud billing projects describe "$PROJECT_ID" \
    --format='value(billingEnabled)' 2>/dev/null || true
)"

if [[ "$BILLING_ENABLED" != "True" && "$BILLING_ENABLED" != "true" ]]; then
  fail "El proyecto no tiene una cuenta de facturación activa."
fi

printf 'Número del proyecto: %s\n' "$PROJECT_NUMBER"
printf 'Facturación:         habilitada\n'

section "3. Habilitación de APIs"

printf 'Habilitando APIs requeridas. Esta operación puede tardar varios minutos...\n'

gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  firestore.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  --project="$PROJECT_ID"

section "4. Artifact Registry"

if gcloud artifacts repositories describe "$AR_REPOSITORY" \
    --location="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf 'El repositorio %s ya existe. Se reutilizará.\n' "$AR_REPOSITORY"
else
  gcloud artifacts repositories create "$AR_REPOSITORY" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Imágenes del Laboratorio 3 de DevOps" \
    --disable-vulnerability-scanning \
    --project="$PROJECT_ID"
fi

CLEANUP_FILE="$(mktemp)"
trap 'rm -f "$CLEANUP_FILE"' EXIT

cat > "$CLEANUP_FILE" <<'JSON'
[
  {
    "name": "delete-old-versions",
    "action": {"type": "Delete"},
    "condition": {
      "tagState": "any",
      "olderThan": "3d"
    }
  },
  {
    "name": "keep-baseline",
    "action": {"type": "Keep"},
    "condition": {
      "tagState": "tagged",
      "tagPrefixes": ["baseline"]
    }
  },
  {
    "name": "keep-recent",
    "action": {"type": "Keep"},
    "mostRecentVersions": {
      "keepCount": 3
    }
  }
]
JSON

gcloud artifacts repositories set-cleanup-policies "$AR_REPOSITORY" \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --policy="$CLEANUP_FILE" \
  --no-dry-run \
  --quiet

printf 'Cleanup policy configurada sobre %s.\n' "$AR_REPOSITORY"

section "5. Firestore"

if gcloud firestore databases describe \
    --database="(default)" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  FIRESTORE_LOCATION="$(
    gcloud firestore databases describe \
      --database="(default)" \
      --project="$PROJECT_ID" \
      --format='value(locationId)'
  )"

  printf 'La base (default) ya existe en %s.\n' "$FIRESTORE_LOCATION"

  if [[ -n "$FIRESTORE_LOCATION" && "$FIRESTORE_LOCATION" != "$REGION" ]]; then
    fail "La base Firestore (default) ya existe en ${FIRESTORE_LOCATION}, pero el laboratorio utiliza ${REGION}. Utilice un proyecto limpio."
  fi
else
  gcloud firestore databases create \
    --database="(default)" \
    --location="$REGION" \
    --edition=standard \
    --type=firestore-native \
    --project="$PROJECT_ID"
fi

section "6. Service accounts e IAM"

ensure_service_account() {
  local name="$1"
  local email="$2"
  local display_name="$3"

  if gcloud iam service-accounts describe "$email" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    printf 'Service account existente: %s\n' "$email"
  else
    gcloud iam service-accounts create "$name" \
      --display-name="$display_name" \
      --project="$PROJECT_ID"
  fi
}

ensure_service_account "$PUBLISHER_SA_NAME" "$PUBLISHER_SA" "GitHub Actions - publicación de imágenes"
ensure_service_account "$DEPLOYER_SA_NAME" "$DEPLOYER_SA" "GitHub Actions - despliegue en Cloud Run"
ensure_service_account "$RUNTIME_SA_NAME" "$RUNTIME_SA" "Incident API - identidad de ejecución"

printf 'Configurando permisos. Las identidades recién creadas pueden requerir tiempo de propagación...\n'

retry_iam "runtime -> Datastore User" \
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${RUNTIME_SA}" \
    --role="roles/datastore.user" \
    --condition=None \
    --quiet

retry_iam "publisher -> Artifact Registry Writer" \
  gcloud artifacts repositories add-iam-policy-binding "$AR_REPOSITORY" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${PUBLISHER_SA}" \
    --role="roles/artifactregistry.writer" \
    --condition=None \
    --quiet

retry_iam "deployer -> Artifact Registry Reader" \
  gcloud artifacts repositories add-iam-policy-binding "$AR_REPOSITORY" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${DEPLOYER_SA}" \
    --role="roles/artifactregistry.reader" \
    --condition=None \
    --quiet

retry_iam "deployer -> Service Account User sobre runtime" \
  gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${DEPLOYER_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None \
    --quiet

section "7. Workload Identity Federation"

printf 'Configurando la federación de identidad para GitHub Actions...\n'

if gcloud iam workload-identity-pools describe "$POOL_ID" \
    --location="global" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf 'Workload Identity Pool existente: %s\n' "$POOL_ID"
else
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --location="global" \
    --display-name="GitHub Actions - Laboratorio 3" \
    --description="Federación OIDC para el repositorio ${GITHUB_REPO}" \
    --project="$PROJECT_ID"
fi

EXPECTED_CONDITION="assertion.repository=='${GITHUB_REPO}' && assertion.ref=='refs/heads/main'"

if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location="global" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  CURRENT_CONDITION="$(
    gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
      --workload-identity-pool="$POOL_ID" \
      --location="global" \
      --project="$PROJECT_ID" \
      --format='value(attributeCondition)'
  )"

  [[ "$CURRENT_CONDITION" == "$EXPECTED_CONDITION" ]] \
    || fail "El provider ${PROVIDER_ID} ya existe con una condición distinta: ${CURRENT_CONDITION}"

  printf 'Workload Identity Provider existente y compatible: %s\n' "$PROVIDER_ID"
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location="global" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="$EXPECTED_CONDITION" \
    --project="$PROJECT_ID"
fi

WIF_PRINCIPAL_SET="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

retry_iam "GitHub -> impersonación de publisher" \
  gcloud iam service-accounts add-iam-policy-binding "$PUBLISHER_SA" \
    --project="$PROJECT_ID" \
    --member="$WIF_PRINCIPAL_SET" \
    --role="roles/iam.workloadIdentityUser" \
    --condition=None \
    --quiet

retry_iam "GitHub -> impersonación de deployer" \
  gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA" \
    --project="$PROJECT_ID" \
    --member="$WIF_PRINCIPAL_SET" \
    --role="roles/iam.workloadIdentityUser" \
    --condition=None \
    --quiet

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

section "8. Revisión baseline de Cloud Run"

printf 'Preparando la revisión baseline. La construcción y el despliegue pueden tardar varios minutos...\n'

SERVICE_EXISTS="false"
if gcloud run services describe "$RUN_SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  SERVICE_EXISTS="true"
fi

if [[ "$SERVICE_EXISTS" == "true" ]]; then
  if gcloud run revisions describe "$BASELINE_REVISION" \
      --region="$REGION" \
      --project="$PROJECT_ID" >/dev/null 2>&1; then
    printf 'El servicio %s y la revisión %s ya existen. No se reconstruirá la baseline.\n' \
      "$RUN_SERVICE" "$BASELINE_REVISION"
  else
    fail "Ya existe un servicio Cloud Run llamado ${RUN_SERVICE}, pero no contiene la revisión ${BASELINE_REVISION}. Utilice un proyecto limpio."
  fi
else
  section "8.1 Construcción y publicación de baseline"

  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

  docker build \
    --label "edu.esen.devops.release=baseline" \
    --tag "$BASELINE_IMAGE" \
    .

  docker push "$BASELINE_IMAGE"

  section "8.2 Despliegue de baseline"

  gcloud run deploy "$RUN_SERVICE" \
    --image="$BASELINE_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --revision-suffix="baseline" \
    --service-account="$RUNTIME_SA" \
    --set-env-vars="STORAGE_BACKEND=firestore,GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
    --min=0 \
    --max=2 \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet
fi

retry_iam "deployer -> Cloud Run Developer sobre incident-api" \
  gcloud run services add-iam-policy-binding "$RUN_SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${DEPLOYER_SA}" \
    --role="roles/run.developer" \
    --condition=None \
    --quiet

section "9. Validación funcional"

SERVICE_URL="$(
  gcloud run services describe "$RUN_SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status.url)'
)"

LATEST_READY_REVISION="$(
  gcloud run services describe "$RUN_SERVICE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status.latestReadyRevisionName)'
)"

[[ -n "$SERVICE_URL" ]] || fail "No fue posible obtener la URL del servicio Cloud Run."

printf 'URL del servicio:          %s\n' "$SERVICE_URL"
printf 'Última revisión preparada: %s\n' "$LATEST_READY_REVISION"

HEALTH_OK="false"
for attempt in $(seq 1 10); do
  if curl --fail --silent --show-error "${SERVICE_URL}/health" >/dev/null 2>&1; then
    HEALTH_OK="true"
    break
  fi
  printf 'Intento %s/10 para /health. Reintentando en 10 s...\n' "$attempt"
  sleep 10
done

[[ "$HEALTH_OK" == "true" ]] || fail "El endpoint /health no respondió satisfactoriamente."
printf 'GET /health: OK\n'

INCIDENTS_OK="false"
INCIDENTS_BODY=""

for attempt in $(seq 1 24); do
  RESPONSE_FILE="$(mktemp)"

  if curl --fail --silent --show-error \
      "${SERVICE_URL}/incidents" \
      --output "$RESPONSE_FILE" 2>/dev/null; then
    INCIDENTS_BODY="$(cat "$RESPONSE_FILE")"
    rm -f "$RESPONSE_FILE"
    INCIDENTS_OK="true"
    break
  fi

  rm -f "$RESPONSE_FILE"
  printf 'Intento %s/24 para /incidents. Reintentando en 15 s...\n' "$attempt"
  sleep 15
done

[[ "$INCIDENTS_OK" == "true" ]] \
  || fail "El endpoint /incidents no pudo acceder correctamente a Firestore."

printf 'GET /incidents: OK\n'
printf 'Respuesta: %s\n' "$INCIDENTS_BODY"

section "ENTORNO DEL LABORATORIO 3 PREPARADO"

cat <<EOF
Proyecto:
  ${PROJECT_ID}

Número del proyecto:
  ${PROJECT_NUMBER}

Región:
  ${REGION}

Artifact Registry:
  ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}

Imagen baseline:
  ${BASELINE_IMAGE}

Firestore:
  (default)

Cloud Run:
  Servicio: ${RUN_SERVICE}
  URL: ${SERVICE_URL}
  Revisión baseline: ${BASELINE_REVISION}
  Última revisión lista: ${LATEST_READY_REVISION}

Service accounts:
  Publisher: ${PUBLISHER_SA}
  Deployer:  ${DEPLOYER_SA}
  Runtime:   ${RUNTIME_SA}

Workload Identity Provider:
  ${WIF_PROVIDER}

Repositorio autorizado:
  ${GITHUB_REPO}

Referencia autorizada:
  refs/heads/main

------------------------------------------------------------
Variables de repositorio para GitHub Actions
------------------------------------------------------------

GCP_PROJECT_ID=${PROJECT_ID}
GCP_REGION=${REGION}
ARTIFACT_REPOSITORY=${AR_REPOSITORY}
IMAGE_NAME=${IMAGE_NAME}
CLOUD_RUN_SERVICE=${RUN_SERVICE}
WIF_PROVIDER=${WIF_PROVIDER}
PUBLISHER_SERVICE_ACCOUNT=${PUBLISHER_SA}
DEPLOYER_SERVICE_ACCOUNT=${DEPLOYER_SA}
RUNTIME_SERVICE_ACCOUNT=${RUNTIME_SA}

Estas variables NO son llaves privadas y no deben reemplazarse por una
service account key JSON.

Preparación finalizada correctamente.
EOF