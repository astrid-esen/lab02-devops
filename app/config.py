import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    storage_backend: str
    google_cloud_project: str | None


def get_settings() -> Settings:
    return Settings(
        storage_backend=os.getenv("STORAGE_BACKEND", "memory").lower(),
        google_cloud_project=os.getenv("GOOGLE_CLOUD_PROJECT"),
    )
