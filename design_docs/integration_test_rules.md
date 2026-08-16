# Python Integration Test Rules

Rules for integration tests in `server/tests/integration/` — tests that exercise several units
together against real infrastructure (Postgres, Neo4j, the ASGI app). For isolated tests see
`unit_test_rules.md`. Test runner: **pytest** (`uv run pytest tests/integration`).

## What belongs here

Typical targets: HTTP route → dependency injection → service → repository → PostgreSQL;
SQLAlchemy mappings; real SQL queries; transaction behavior; migration correctness;
pydantic ↔ database serialization; authentication integration; configuration wiring; pgvector
queries; Neo4j integration when introduced. Mocks appear only at boundaries outside the
application's control.

The canonical shape:

```text
FastAPI ASGI app → route → service → repository → SQLAlchemy → real test PostgreSQL
```

An httpx `ASGITransport` test is an **in-process** integration test. Future end-to-end tests
(real server process, real TCP socket, production-like configuration) are a separate layer and
do not belong in this directory.

## Layout & selection

- **Mirror the source folder structure**, same as unit tests: `tests/integration/` replicates
  the directory tree of the source root, files named `test_<module>.py`.
- Directory separation is the selection mechanism: `tests/unit` runs fast and often,
  `tests/integration` runs in CI and on demand. No `__init__.py` in test directories.
- Follow the test pyramid: few integration tests, many unit tests. Integration tests cover the
  **seams** — route ↔ service ↔ DB, transactions, migrations, serialization, config wiring.
  Edge cases and branch coverage belong in unit tests; don't duplicate them here.

## Infrastructure & state

- Use **real services for our own infrastructure** (Postgres/pgvector via docker-compose,
  later Neo4j). Mock only third-party systems outside our control.
- Dedicated test environment: separate database name and ports, own settings — never run
  against dev or production data.
- Schema is built by migrations (`alembic upgrade head`), created once per run in a
  session-scoped fixture. Never create tables via `Base.metadata.create_all` in integration
  tests — the migrations themselves are under test.
- Every test starts from a known, clean state: per-test transaction rollback or truncate
  fixture. Never rely on rows left behind by another test.
- Seed data through factory/helper fixtures, not raw SQL dumps or shared CSV snapshots.

## Fixtures & scopes

- **Scope = when the fixture is created.**
  - `session`/`module` scope (once before the suite): expensive, immutable infrastructure —
    DB engine, migrated schema, app instance, container handles.
  - `function` scope (before every single test): anything mutable — DB rows, queues, caches,
    monkeypatched settings.
- Teardown must be failure-proof: `yield` fixtures with cleanup after the yield (or
  try/finally) so connections, transactions, and containers are released even when a test
  fails.
- pytest-asyncio loop behavior is configured explicitly in `pyproject.toml`
  (`asyncio_default_fixture_loop_scope`); do not rely on plugin defaults, which change between
  versions. A fixture wider than the default loop scope (e.g. a session-scoped async fixture)
  must declare a compatible loop scope explicitly.
- Mock sparingly, at the outer boundary only, and with the same scoping discipline: a mock
  installed for one test must not leak into the next.

## API-level tests

- Exercise the app through its real interface: the FastAPI app via `TestClient` /
  httpx `ASGITransport`. `dependency_overrides` may redirect an infrastructure dependency to
  an equivalent test instance of the same infrastructure — e.g. a SQLAlchemy session bound to
  the test-controlled transaction, so per-test rollback isolation also covers requests handled
  on connections the test did not open. Never override in a way that bypasses a layer under
  test (`route → service → repository → real test transaction` is good;
  `route → mocked service` is not).
- Tests that depend on application startup must run the FastAPI lifespan explicitly:
  `with TestClient(app)`, or a lifespan manager around `ASGITransport` for async clients — a
  bare `ASGITransport` does not execute startup/shutdown.
- Assert on contracts: status codes, response bodies validated against the pydantic schemas,
  **and** the persisted state in the database — never on internals.

## Robustness

- Every network/DB call has a timeout. A hung service must fail the test, never block the
  suite.
- Deterministic: fixed seeds; frozen or injected time wherever logic depends on it.
- Failures must be debuggable: use `caplog`, unique test data IDs, and include the response
  body in assertion messages.
- Never silently skip when infrastructure is missing — in CI, a missing service is a failed
  run, not a green one.
