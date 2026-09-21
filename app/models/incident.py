from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class IncidentPriority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class IncidentStatus(StrEnum):
    OPEN = "open"
    IN_PROGRESS = "in_progress"
    RESOLVED = "resolved"


class IncidentCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    description: str = Field(min_length=5, max_length=1000)
    priority: IncidentPriority = IncidentPriority.MEDIUM


class Incident(BaseModel):
    id: str
    title: str
    description: str
    priority: IncidentPriority
    status: IncidentStatus
    created_at: datetime
    resolved_at: datetime | None = None


class IncidentStatusUpdate(BaseModel):
    status: IncidentStatus
