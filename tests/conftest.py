import pytest
from fastapi.testclient import TestClient

from app.dependencies import get_incident_service
from app.main import app
from app.repositories.memory import InMemoryIncidentRepository
from app.services.incident_service import IncidentService


@pytest.fixture
def service() -> IncidentService:
    # Fixture de servicio para pruebas unitarias.
    # Se usa una implementación en memoria para garantizar aislamiento entre
    # pruebas y evitar depender de una base de datos real.
    return IncidentService(InMemoryIncidentRepository())


@pytest.fixture
def client(service: IncidentService):
    # Fixture para pruebas de integración de la API.
    # Sobrescribe la dependencia normal de la app para que el cliente use el
    # mismo servicio en memoria compartido por estas pruebas.
    app.dependency_overrides[get_incident_service] = lambda: service
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
