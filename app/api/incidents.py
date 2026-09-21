from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.dependencies import get_incident_service
from app.models.incident import (
    Incident,
    IncidentCreate,
    IncidentStatusUpdate,
)
from app.services.incident_service import (
    IncidentNotFoundError,
    IncidentService,
    InvalidStatusTransitionError,
)

# Router de FastAPI: agrupa todas las rutas relacionadas a incidentes.
# El prefijo /incidents y el tag sirven para organizar la documentación
# automática de Swagger/OpenAPI.
router = APIRouter(prefix="/incidents", tags=["incidents"])

# Tipo auxiliar para inyectar la dependencia del servicio en cada endpoint.
# Esto permite que FastAPI cree una instancia del servicio a partir de
# get_incident_service y la pase automáticamente a la ruta.
IncidentServiceDependency = Annotated[
    IncidentService,
    Depends(get_incident_service),
]


@router.get("", response_model=list[Incident])
def list_incidents(service: IncidentServiceDependency) -> list[Incident]:
    # GET /incidents
    # La ruta delega la consulta al servicio y devuelve la lista serializada
    # como respuesta JSON, gracias a response_model.
    return service.list_incidents()


@router.get("/{incident_id}", response_model=Incident)
def get_incident(
    incident_id: str,
    service: IncidentServiceDependency,
) -> Incident:
    # GET /incidents/{incident_id}
    try:
        return service.get_incident(incident_id)
    except IncidentNotFoundError as exc:
        # Si no existe, FastAPI responde con 404 y un mensaje claro.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Incident not found",
        ) from exc


@router.post("", response_model=Incident, status_code=status.HTTP_201_CREATED)
def create_incident(
    data: IncidentCreate,
    service: IncidentServiceDependency,
) -> Incident:
    # POST /incidents
    # FastAPI valida automáticamente que el body cumpla con IncidentCreate.
    # Luego se delega al servicio para crear el incidente y guardarlo.
    return service.create_incident(data)


@router.patch("/{incident_id}/status", response_model=Incident)
def update_incident_status(
    incident_id: str,
    data: IncidentStatusUpdate,
    service: IncidentServiceDependency,
) -> Incident:
    # PATCH /incidents/{incident_id}/status
    try:
        return service.update_status(incident_id, data.status)
    except IncidentNotFoundError as exc:
        # Cuando el id no existe, responde 404.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Incident not found",
        ) from exc
    except InvalidStatusTransitionError as exc:
        # Si la transición de estado no está permitida, responde 409 Conflict.
        # Este código es útil para indicar un conflicto de negocio.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
