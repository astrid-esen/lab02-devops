# Evidencias

## Laboratorio 2. Integración continua

### 19.1 Pipeline final

El workflow `.github/workflows/ci.yml` corre en cada `push` a `main` y en cada
`pull_request` cuyo destino es `main`. Tres jobs:

- **Lint**: instala `requirements-dev.txt` y ejecuta `python -m ruff check .`.
  Responsable de análisis estático de estilo/errores.
- **Test**: instala `requirements-dev.txt`, ejecuta `pytest` con cobertura sobre
  el paquete `app` (`--cov=app --cov-report=xml`) y publica `coverage.xml` como
  artifact. Responsable de las pruebas automatizadas y su cobertura.
- **Container**: construye la imagen Docker y la etiqueta con el SHA del commit
  (`incident-api:${{ github.sha }}`). Responsable de verificar que el proyecto
  es empaquetable.

`Lint` y `Test` no dependen entre sí y se ejecutan en paralelo. `Container`
depende de ambos (`needs: [Lint, Test]`) y solo corre si los dos terminan con éxito.

### 19.2 Fallo de lint

- Enlace a la ejecución: <link https://github.com/astrid-esen/lab02-devops/pull/3>
- Cambio que provocó el fallo: el cambio que provoco el fallo fue agregar una variable que no se ocupaba en el archivo de main.py.
  <link https://github.com/astrid-esen/lab02-devops/actions/runs/36290134183/job/108538505736?pr=3>
- Evidencia de que `Container` no se ejecutó: <link https://github.com/astrid-esen/lab02-devops/actions/runs/36290134183/job/108538568047?pr=3>
- Evidencia de que el merge quedó bloqueado: <link https://github.com/astrid-esen/lab02-devops/pull/3>

### 19.3 Fallo de pruebas

- Enlace a la ejecución: <link https://github.com/astrid-esen/lab02-devops/pull/3>
- Cambio que provocó el fallo: se agregó temporalmente assert 1 == 2 dentro del archivo test/test_temporal.py
- Evidencia de que `Container` no se ejecutó: <link https://github.com/astrid-esen/lab02-devops/actions/runs/36291366211/job/108541964579?pr=3>
- Evidencia de que el merge quedó bloqueado: <link https://github.com/astrid-esen/lab02-devops/actions/runs/36291366211/job/108541964579?pr=3>

### 19.4 Ejecución satisfactoria

- Enlace a la ejecución con los tres jobs satisfactorios: <link https://github.com/astrid-esen/lab02-devops/pull/3/checks>
- Enlace al pull request utilizado para integrar el laboratorio: <link https://github.com/astrid-esen/lab02-devops/pull/3>
- SHA del commit final evaluado: 5fcce06333ba8d653089f3393d7d4a7942ee0275

### 19.5 Artifact
- **Identificación:** El reporte de cobertura en formato XML fue configurado para conservarse como un workflow artifact. 
- **Evidencia:** Se generó el artefacto con el nombre `coverage-report` (que contiene el archivo `coverage.xml`). Este se puede visualizar y descargar desde la sección "Artifacts" en el resumen de cualquier ejecución exitosa del pipeline en GitHub Actions. <link https://github.com/astrid-esen/lab02-devops/actions/runs/36289348274>

### 19.6 Caché

- Enlace a una ejecución donde se observa reutilización de caché: <link https://github.com/astrid-esen/lab02-devops/actions/caches>
- Qué cambio invalida la caché: la clave de caché está atada al hash de
  `requirements.txt` y `requirements-dev.txt` (`cache-dependency-path`). Modificar
  cualquiera de esos dos archivos (agregar, quitar o cambiar de versión una
  dependencia) genera una nueva clave y fuerza a reconstruir la caché.
