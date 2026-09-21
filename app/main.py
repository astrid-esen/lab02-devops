from fastapi import FastAPI

from app.api.incidents import router as incidents_router

app = FastAPI(
    title="Incident API",
    version="1.0.0",
    description="API base para los laboratorios de CI/CD del curso DevOps.",
)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(incidents_router)
