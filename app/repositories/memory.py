from datetime import UTC, datetime

from app.models.incident import Incident, IncidentStatus
from app.repositories.base import IncidentRepository


class InMemoryIncidentRepository(IncidentRepository):
    """Repositorio de ejemplo para entender la capa de persistencia.

    En una aplicación real, esto podría ser Firestore o una base de datos SQL.
    Aquí se usa un diccionario en memoria para que los estudiantes puedan
    comprender la lógica de negocio sin necesidad de configurar un servicio
    externo durante el primer contacto con FastAPI.
    """

    def __init__(self) -> None:
        # Simula una base de datos simple: clave = id del incidente,
        # valor = instancia del modelo Incident.
        # Esto permite guardar, consultar y actualizar registros en memoria
        # durante la ejecución de la aplicación.
        self._incidents: dict[str, Incident] = {}

    def list(self) -> list[Incident]:
        # Devuelve todos los incidentes ordenados por fecha de creación.
        # El orden estable ayuda a que la API responda de forma consistente
        # y facilita pruebas y demostraciones.
        return sorted(
            self._incidents.values(),
            key=lambda incident: incident.created_at,
        )

    def get(self, incident_id: str) -> Incident | None:
        # Busca un incidente por su identificador.
        # En FastAPI, este tipo de acceso suele usarse desde rutas como
        # GET /incidents/{incident_id}.
        return self._incidents.get(incident_id)

    def create(self, incident: Incident) -> Incident:
        # Guarda un nuevo incidente en memoria.
        # En una API REST, esta operación normalmente corresponde a un POST
        # donde se recibe un payload y se convierte en un objeto de dominio.
        self._incidents[incident.id] = incident
        return incident

    def update_status(
        self,
        incident_id: str,
        status: IncidentStatus,
    ) -> Incident | None:
        # Esta operación representa un caso típico de actualización de estado.
        # En FastAPI, suele ser utilizada por endpoints que cambian el estado
        # de un recurso, por ejemplo PUT/PATCH.
        incident = self.get(incident_id)
        if incident is None:
            return None

        # Mantenemos el campo resolved_at en sincronía con el estado.
        # Si el incidente pasa a RESOLVED, se registra el momento exacto de
        # resolución; si sale de RESOLVED, se limpia la fecha para evitar
        # inconsistencias.
        resolved_at = incident.resolved_at
        if status == IncidentStatus.RESOLVED:
            resolved_at = datetime.now(UTC)
        elif incident.status == IncidentStatus.RESOLVED:
            resolved_at = None

        updated = incident.model_copy(
            update={"status": status, "resolved_at": resolved_at}
        )
        self._incidents[incident_id] = updated
        return updated
