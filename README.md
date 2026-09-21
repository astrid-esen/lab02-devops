# Incident API

Aplicación base para los laboratorios de integración y entrega continua del curso DevOps.

## Stack

- Python 3.13
- FastAPI
- Firestore, disponible como backend persistente
- almacenamiento en memoria por defecto
- pytest
- Ruff
- Docker

## Ejecución local

Crear un entorno virtual e instalar las dependencias de desarrollo:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements-dev.txt
```

Ejecutar la API:

```bash
python -m app.server
```

La API queda disponible en `http://localhost:8080` y la documentación interactiva en `http://localhost:8080/docs`.

## Validaciones locales

```bash
python -m ruff check .
python -m pytest
```

## Docker

```bash
docker build -t incident-api:local .
docker run --rm -p 8080:8080 incident-api:local
```

## Almacenamiento

Por defecto se utiliza un repositorio en memoria:

```text
STORAGE_BACKEND=memory
```

La implementación de Firestore se encuentra incluida para etapas posteriores del proyecto. No se requiere Google Cloud para ejecutar las pruebas ni para trabajar con la configuración predeterminada.
