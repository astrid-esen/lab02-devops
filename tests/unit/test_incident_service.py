import pytest

from app.models.incident import (
    IncidentCreate,
    IncidentPriority,
    IncidentStatus,
)
from app.services.incident_service import (
    IncidentNotFoundError,
    IncidentService,
    InvalidStatusTransitionError,
)


def create_sample(service: IncidentService):
    # Helper para crear un incidente con datos mínimos y reproducibles.
    # Esto mantiene los tests más legibles y evita repetir el mismo payload.
    return service.create_incident(
        IncidentCreate(
            title="API unavailable",
            description="Public API returns HTTP 503",
            priority=IncidentPriority.HIGH,
        )
    )


def test_new_incident_starts_open(service: IncidentService):
    # Verifica el estado inicial del dominio: todo incidente nuevo debe abrirse.
    incident = create_sample(service)
    assert incident.status == IncidentStatus.OPEN
    assert incident.id.startswith("INC-")


def test_valid_status_sequence(service: IncidentService):
    # Prueba el flujo correcto del ciclo de vida del incidente.
    # OPEN -> IN_PROGRESS -> RESOLVED es la secuencia permitida por la regla.
    incident = create_sample(service)

    in_progress = service.update_status(
        incident.id,
        IncidentStatus.IN_PROGRESS,
    )
    resolved = service.update_status(
        incident.id,
        IncidentStatus.RESOLVED,
    )

    assert in_progress.status == IncidentStatus.IN_PROGRESS
    assert resolved.status == IncidentStatus.RESOLVED
    assert resolved.resolved_at is not None


def test_cannot_resolve_open_incident_directly(service: IncidentService):
    # Asegura que la lógica de negocio invalida una transición imposible.
    # Esto es clave para proteger la integridad del flujo y enseñar buenas
    # prácticas de validación en la capa de servicio.
    incident = create_sample(service)

    with pytest.raises(InvalidStatusTransitionError):
        service.update_status(incident.id, IncidentStatus.RESOLVED)


def test_unknown_incident_raises_error(service: IncidentService):
    # Prueba el caso de error cuando se consulta un id inexistente.
    with pytest.raises(IncidentNotFoundError):
        service.get_incident("INC-UNKNOWN")
