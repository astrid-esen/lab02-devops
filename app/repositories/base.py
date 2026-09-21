from abc import ABC, abstractmethod

from app.models.incident import Incident, IncidentStatus


class IncidentRepository(ABC):
    @abstractmethod
    def list(self) -> list[Incident]:
        raise NotImplementedError

    @abstractmethod
    def get(self, incident_id: str) -> Incident | None:
        raise NotImplementedError

    @abstractmethod
    def create(self, incident: Incident) -> Incident:
        raise NotImplementedError

    @abstractmethod
    def update_status(
        self,
        incident_id: str,
        status: IncidentStatus,
    ) -> Incident | None:
        raise NotImplementedError
