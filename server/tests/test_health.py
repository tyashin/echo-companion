"""Tests for the health endpoint (minimal app, DB check mocked)."""

from unittest.mock import AsyncMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.routes import health


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    app = FastAPI()
    app.include_router(health.router)
    mock_check = AsyncMock()
    monkeypatch.setattr(health, "check_db_connection", mock_check)
    return TestClient(app)


def test_health_healthy(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_health_unhealthy(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        health, "check_db_connection", AsyncMock(side_effect=ConnectionError("db down"))
    )
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "unhealthy"}
