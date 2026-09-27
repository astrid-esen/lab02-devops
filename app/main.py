from fastapi import FastAPI

from app.api.incidents import router as incidents_router

app = FastAPI(
    title="Incident API",
    version="1.0.0",
    description="API base para los laboratorios de CI/CD del curso DevOps.",
)

variable_sin_usar = "Esta variable no se usa en el código, pero sirve para probar GitHub Actions."

@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(incidents_router)
