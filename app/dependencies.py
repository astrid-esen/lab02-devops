from functools import lru_cache

from app.config import get_settings
from app.repositories.base import IncidentRepository
from app.repositories.memory import InMemoryIncidentRepository
from app.services.incident_service import IncidentService


@lru_cache
def get_repository() -> IncidentRepository:
    settings = get_settings()

    if settings.storage_backend == "memory":
        return InMemoryIncidentRepository()

    if settings.storage_backend == "firestore":
        from app.repositories.firestore import FirestoreIncidentRepository

        return FirestoreIncidentRepository(project=settings.google_cloud_project)

    raise RuntimeError(
        f"Unsupported STORAGE_BACKEND: {settings.storage_backend}"
    )


def get_incident_service() -> IncidentService:
    return IncidentService(get_repository())
