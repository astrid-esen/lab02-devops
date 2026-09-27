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
- Cambio que provocó el fallo: <el cambio qu >
- Evidencia de que `Container` no se ejecutó: <link al run mostrando el job en "skipped">
- Evidencia de que el merge quedó bloqueado: <link al PR mostrando el check requerido en rojo / merge deshabilitado>

### 19.3 Fallo de pruebas

- Enlace a la ejecución: <link al run de Actions>
- Cambio que provocó el fallo: <describir, ej. test temporal con assert False>
- Evidencia de que `Container` no se ejecutó: <link al run mostrando el job en "skipped">
- Evidencia de que el merge quedó bloqueado: <link al PR mostrando el check requerido en rojo / merge deshabilitado>

### 19.4 Ejecución satisfactoria

- Enlace a la ejecución con los tres jobs satisfactorios: <link>
- Enlace al pull request utilizado para integrar el laboratorio: <link>
- SHA del commit final evaluado: <sha>

### 19.5 Artifact

- Artifact generado por el job `Test`: `coverage-report` (contiene `coverage.xml`)
- Enlace al run donde se puede descargar: <link>

### 19.6 Caché

- Enlace a una ejecución donde se observa reutilización de caché: <link a run/step>
- Qué cambio invalida la caché: la clave de caché está atada al hash de
  `requirements.txt` y `requirements-dev.txt` (`cache-dependency-path`). Modificar
  cualquiera de esos dos archivos (agregar, quitar o cambiar de versión una
  dependencia) genera una nueva clave y fuerza a reconstruir la caché.
