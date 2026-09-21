def sample_payload() -> dict[str, str]:
    # Payload de ejemplo para pruebas de integración.
    # Se usa un caso realista para validar el flujo completo HTTP.
    return {
        "title": "Database latency",
        "description": "Queries exceed the expected response time",
        "priority": "critical",
    }


def test_health_endpoint(client):
    # Verifica que la aplicación esté viva y responda en el endpoint base.
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_and_get_incident(client):
    # Prueba el flujo principal: crear un incidente y luego consultarlo.
    created = client.post("/incidents", json=sample_payload())
    assert created.status_code == 201

    incident_id = created.json()["id"]
    fetched = client.get(f"/incidents/{incident_id}")

    assert fetched.status_code == 200
    assert fetched.json()["title"] == "Database latency"
    assert fetched.json()["status"] == "open"


def test_unknown_incident_returns_404(client):
    # Verifica que la API responde correctamente cuando un recurso no existe.
    response = client.get("/incidents/INC-UNKNOWN")
    assert response.status_code == 404


def test_invalid_status_transition_returns_409(client):
    # Comprueba que la API expone un conflicto de negocio cuando una transición
    # no está permitida, por ejemplo OPEN -> RESOLVED.
    created = client.post("/incidents", json=sample_payload())
    incident_id = created.json()["id"]

    response = client.patch(
        f"/incidents/{incident_id}/status",
        json={"status": "resolved"},
    )

    assert response.status_code == 409


def test_valid_status_transition(client):
    # Verifica el caso exitoso de un cambio de estado válido.
    created = client.post("/incidents", json=sample_payload())
    incident_id = created.json()["id"]

    response = client.patch(
        f"/incidents/{incident_id}/status",
        json={"status": "in_progress"},
    )

    assert response.status_code == 200
    assert response.json()["status"] == "in_progress"
