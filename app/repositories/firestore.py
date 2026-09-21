from datetime import UTC, datetime
from typing import Any

from google.cloud import firestore

from app.models.incident import Incident, IncidentStatus
from app.repositories.base import IncidentRepository


class FirestoreIncidentRepository(IncidentRepository):
    COLLECTION = "incidents"

    def __init__(self, project: str | None = None) -> None:
        self._client = firestore.Client(project=project)
        self._collection = self._client.collection(self.COLLECTION)

    @staticmethod
    def _to_incident(data: dict[str, Any]) -> Incident:
        return Incident.model_validate(data)

    def list(self) -> list[Incident]:
        documents = self._collection.order_by("created_at").stream()
        return [self._to_incident(document.to_dict()) for document in documents]

    def get(self, incident_id: str) -> Incident | None:
        snapshot = self._collection.document(incident_id).get()
        if not snapshot.exists:
            return None
        return self._to_incident(snapshot.to_dict())

    def create(self, incident: Incident) -> Incident:
        self._collection.document(incident.id).set(
            incident.model_dump(mode="python")
        )
        return incident

    def update_status(
        self,
        incident_id: str,
        status: IncidentStatus,
    ) -> Incident | None:
        incident = self.get(incident_id)
        if incident is None:
            return None

        resolved_at = incident.resolved_at
        if status == IncidentStatus.RESOLVED:
            resolved_at = datetime.now(UTC)
        elif incident.status == IncidentStatus.RESOLVED:
            resolved_at = None

        self._collection.document(incident_id).update(
            {
                "status": status.value,
                "resolved_at": resolved_at,
            }
        )
        return self.get(incident_id)
