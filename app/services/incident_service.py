from datetime import UTC, datetime
from uuid import uuid4

from app.models.incident import (
    Incident,
    IncidentCreate,
    IncidentStatus,
)
from app.repositories.base import IncidentRepository


class IncidentNotFoundError(Exception):
    """Se lanza cuando un incidente no existe en la capa de persistencia."""


class InvalidStatusTransitionError(Exception):
    """Se lanza cuando se intenta cambiar un estado no permitido.

    Por ejemplo: un incidente en OPEN no puede pasar directamente a RESOLVED.
    Este tipo de validación suele estar en la capa de servicio porque expresa
    la regla de negocio, no solo la estructura de datos.
    """


# Regla de negocio: define qué transiciones son válidas para cada estado.
# Esto permite centralizar la lógica del flujo del incidente y evitar estados
# inconsistentes o inválidos.
_ALLOWED_TRANSITIONS: dict[IncidentStatus, set[IncidentStatus]] = {
    IncidentStatus.OPEN: {IncidentStatus.IN_PROGRESS},
    IncidentStatus.IN_PROGRESS: {IncidentStatus.RESOLVED},
    IncidentStatus.RESOLVED: set(),
}


class IncidentService:
    """Capa de servicio o lógica de negocio.

    En una aplicación FastAPI, esta clase suele encapsular las reglas del
    dominio y orquestar la comunicación con el repositorio. La API no debe
    saber cómo se persisten los datos ni cómo se validan las transiciones;
    solo delega la operación a este servicio.
    """

    def __init__(self, repository: IncidentRepository) -> None:
        # El servicio depende de una interfaz de repositorio, no de una
        # implementación concreta. Esto facilita reemplazar la persistencia sin
        # cambiar la lógica de negocio.
        self._repository = repository

    def list_incidents(self) -> list[Incident]:
        # Consulta todos los incidentes.
        # En FastAPI, esta operación normalmente corresponde a GET /incidents.
        return self._repository.list()

    def get_incident(self, incident_id: str) -> Incident:
        # Busca un incidente por id y levanta error si no existe.
        incident = self._repository.get(incident_id)
        if incident is None:
            raise IncidentNotFoundError(incident_id)
        return incident

    def create_incident(self, data: IncidentCreate) -> Incident:
        # Crea un objeto de dominio a partir de los datos recibidos por la API.
        # El cliente no manda id ni created_at; la aplicación los genera.
        incident = Incident(
            id=f"INC-{uuid4().hex[:8].upper()}",
            title=data.title,
            description=data.description,
            priority=data.priority,
            status=IncidentStatus.OPEN,
            created_at=datetime.now(UTC),
        )
        return self._repository.create(incident)

    def update_status(
        self,
        incident_id: str,
        new_status: IncidentStatus,
    ) -> Incident:
        # Primero valida que el incidente exista.
        incident = self.get_incident(incident_id)

        # Luego aplica la regla de negocio para evitar transiciones inválidas.
        # Por ejemplo: OPEN -> RESOLVED no está permitido porque debe pasar por
        # IN_PROGRESS primero.
        if new_status not in _ALLOWED_TRANSITIONS[incident.status]:
            transition = f"{incident.status.value} -> {new_status.value}"
            raise InvalidStatusTransitionError(
                f"Transition {transition} is not allowed"
            )

        # Si todo es válido, delega la actualización al repositorio.
        updated = self._repository.update_status(incident_id, new_status)
        if updated is None:
            raise IncidentNotFoundError(incident_id)
        return updated
