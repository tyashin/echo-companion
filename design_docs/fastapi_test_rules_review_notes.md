# FastAPI Unit and Integration Test Rules — Review Notes

## Overall assessment

The rules are strong overall: **approximately 8/10**.

They are substantially better than generic “write tests with pytest” guidance. In particular, they define a clear boundary between unit and integration tests, enforce isolation, encourage sensible fixture scoping, and focus tests on externally observable behaviour instead of implementation details.

The main issue is that several rules are written too absolutely. Most of the recommended changes below are not architectural changes; they are refinements that preserve the intent while avoiding unnecessary restrictions.

---

## What is particularly good

### Unit-test boundary

The unit-test rules correctly define unit tests as isolated tests with no dependency on real databases, networks, clocks, environment state, or external services.

The following principles are particularly strong:

- unit tests should be fast;
- tests should exercise public behaviour and contracts;
- a behaviour-preserving refactor should not break a correct unit test;
- edge cases, error paths, and boundary values matter more than chasing coverage percentages.

That is a good foundation for a maintainable unit-test suite.

### Test structure

The rules around:

- Arrange–Act–Assert;
- one behaviour per test;
- `pytest.raises`;
- parametrization;
- deterministic execution;

are all sound.

The rule that mock interactions should only be asserted when the interaction itself is part of the contract is especially good. It avoids over-specifying implementation details.

### Integration-test scope

The integration-test document correctly focuses integration tests on **seams** between components:

- route ↔ service ↔ database;
- transactions;
- migrations;
- serialization;
- configuration wiring.

This is a better use of integration tests than duplicating unit-test branch coverage.

### Real infrastructure

Using actual Postgres/pgvector and later Neo4j for infrastructure owned by the application is the correct general strategy.

The rules also correctly require:

- a dedicated test environment;
- migrations to build the schema;
- no use of `Base.metadata.create_all()` as a substitute for migrations;
- clean state for every test;
- no reliance on rows left behind by previous tests;
- generated seed data rather than large shared SQL/CSV snapshots.

### API-level assertions

The rule to assert both:

1. the HTTP/API contract; and
2. the resulting persisted database state

is particularly valuable.

A test that only receives `200 OK` is often insufficient. Verifying persisted state ensures that the route, service, repository, transaction handling, serialization, and database write actually worked together.

---

# Recommended changes

## 1. Clarify the filesystem rule

Current unit-test rule:

> No real DB, network, filesystem, clock, or environment.

Later, the rules recommend `tmp_path`.

These two statements conflict because `tmp_path` uses the real temporary filesystem.

### Recommended wording

> Unit tests must not depend on external or persistent filesystem state. If filesystem behaviour is part of the unit's contract, use `tmp_path`; otherwise replace the filesystem boundary with a mock or fake.

This preserves isolation without incorrectly classifying every use of a temporary file as an integration test.

---

## 2. Relax “fixtures for all setup/teardown”

Current rule:

> Use fixtures for all setup/teardown.

This is too broad.

Simple test-specific setup is often clearer inline:

```python
user = User(name="Alice", age=42)
```

Hiding trivial construction behind fixtures can make tests harder to read because setup becomes distributed through `conftest.py` files.

### Recommended wording

> Use fixtures for reusable setup, dependency injection, and resource lifecycle management. Keep trivial test-specific setup directly in the test. Prefer `yield` fixtures when cleanup is required.

---

## 3. Relax the “no control flow” rule

Current rule:

> No control flow (loops, conditionals) inside tests.

The intent is good: loops should not be used to hide multiple test cases.

However, small loops can be completely reasonable when asserting an invariant over one returned structure.

Example:

```python
result = service.get_users()

for user in result:
    assert user.email
```

This is one behaviour being checked over one result.

### Recommended wording

> Do not use control flow to encode multiple independent test cases. Prefer `@pytest.mark.parametrize` for input matrices. Small loops used to assert an invariant over a single returned structure are acceptable.

---

## 4. Clarify transaction rollback and FastAPI dependency overrides

The integration rules allow:

> per-test transaction rollback or truncate fixture

but also say:

> Use `dependency_overrides` only for out-of-process services.

Taken literally, these rules can conflict.

If FastAPI creates its own SQLAlchemy session and connection during the request, a transaction opened by the test cannot automatically roll back changes made through a different connection.

A common solution is to provide the application with a SQLAlchemy session bound to the transaction controlled by the test.

That is technically a dependency override, but it does **not** bypass the database layer. The test still exercises:

```text
route
  ↓
service
  ↓
repository
  ↓
SQLAlchemy
  ↓
real PostgreSQL
```

The override only redirects the DB dependency to the test-controlled connection/session.

### Recommended wording

> `dependency_overrides` may redirect an infrastructure dependency to an equivalent test instance of the same infrastructure, such as a SQLAlchemy session bound to the test transaction. Do not override dependencies in a way that bypasses a layer being tested.

### Good

```text
route → service → repository → real PostgreSQL test transaction
```

### Bad for a route/service/DB integration test

```text
route → mocked service
```

This is one of the most important changes to make.

---

## 5. Add an explicit FastAPI lifespan rule

The integration document recommends:

- `TestClient`; or
- HTTPX `ASGITransport`.

These do not automatically behave identically with respect to FastAPI startup/shutdown lifespan handling.

If application initialization occurs in FastAPI lifespan logic, a test can accidentally exercise an incompletely initialized application unless lifespan is explicitly run.

### Recommended rule

> Tests that depend on application lifespan must explicitly execute startup and shutdown. Use `with TestClient(app)` for synchronous tests, or an appropriate lifespan manager when using `AsyncClient` with `ASGITransport`.

This should be part of the FastAPI-specific integration-test rules.

---

## 6. Make async loop scope explicit

Current rule:

> With pytest-asyncio, the event-loop scope must cover the fixture scope — a session-scoped async fixture requires a session-scoped event loop.

The principle is good.

However, the project should explicitly configure the relevant pytest-asyncio loop behaviour instead of relying on defaults that may change between pytest-asyncio versions.

### Recommended policy

- configure normal async-test behaviour in `pyproject.toml`;
- require unusual module/session-scoped async fixtures to declare compatible loop scope explicitly;
- avoid relying on pytest-asyncio defaults when fixture lifetime matters.

This reduces version-dependent behaviour.

---

## 7. Reconsider globally unique test-file basenames

Current unit-test rules say:

- no `__init__.py` in test directories;
- every test-file basename must be globally unique.

This is technically defensible under pytest's traditional import behaviour, but it becomes awkward in a mirrored source tree.

Real applications commonly contain:

```text
users/service.py
orders/service.py
billing/service.py
```

A mirrored layout naturally produces:

```text
tests/unit/users/test_service.py
tests/unit/orders/test_service.py
tests/unit/billing/test_service.py
```

Requiring globally unique basenames fights the source-tree mirroring rule.

### Recommended approach

Configure pytest import mode deliberately, for example:

```toml
[tool.pytest.ini_options]
addopts = "--import-mode=importlib"
```

Then duplicate test basenames in different directories are normally much less problematic.

The exact pytest configuration should be tested against the project's package layout before adopting it.

---

## 8. Relax “one test file per source module”

Current rule:

> One test file per source module.

This is a useful default but should not be mandatory.

A sufficiently large module may be clearer as:

```text
test_service_creation.py
test_service_permissions.py
test_service_search.py
```

Likewise, very small closely related modules may sometimes be clearer when tested together.

### Recommended wording

> Normally mirror one source module with one test module. Split or combine test files when doing so materially improves readability and discoverability.

---

# Recommended testing-layer model

It would be useful to state explicitly what normally belongs at each test level.

## Unit tests

Typical unit-test targets:

- domain logic;
- service logic in isolation;
- validators;
- transformations;
- parsing;
- calculation logic;
- error branches;
- edge cases;
- boundary values;
- authorization decision logic where dependencies can be isolated.

Typical properties:

```text
no Postgres
no Neo4j
no external network
no application server
no shared external state
```

---

## Integration tests

Typical integration-test targets:

- HTTP route → dependency injection → service → repository → PostgreSQL;
- SQLAlchemy mappings;
- real SQL queries;
- transaction behaviour;
- migration correctness;
- Pydantic ↔ database serialization;
- authentication integration;
- configuration wiring;
- Postgres/pgvector behaviour;
- Neo4j integration when introduced.

Typical shape:

```text
FastAPI ASGI app
       ↓
     route
       ↓
    service
       ↓
 repository
       ↓
 SQLAlchemy
       ↓
real test PostgreSQL
```

Mocks should generally appear only at boundaries outside the application's control.

---

## End-to-end tests

If the project later introduces E2E tests, distinguish them from current ASGI integration tests.

Possible E2E scope:

- real application server process;
- actual TCP socket;
- deployed/runtime configuration;
- infrastructure started as it is in production;
- optionally external services or controlled equivalents.

An HTTPX `ASGITransport` test is still an **in-process application integration test**, not a complete deployed-system E2E test.

---

# Suggested priorities

## High priority

### 1. Fix DB transaction isolation vs `dependency_overrides`

The rules should explicitly permit injecting a test-controlled real SQLAlchemy session when required for transaction rollback isolation.

### 2. Add FastAPI lifespan handling

Tests using `ASGITransport` or `TestClient` should have an explicit policy for application startup/shutdown behaviour.

These two points can affect the correctness of the tests, not merely their style.

---

## Medium priority

- clarify temporary filesystem usage;
- weaken “fixtures for all setup”;
- weaken the absolute control-flow prohibition;
- make pytest-asyncio loop configuration explicit.

---

## Lower priority / organizational

- globally unique test filenames;
- strict one-source-module ↔ one-test-module mapping.

These mostly affect maintainability rather than correctness.

---

# Final assessment

Approximate scores:

| Area | Score |
|---|---:|
| Unit/integration separation | 9/10 |
| Test isolation | 9/10 |
| Mocking philosophy | 9/10 |
| Fixture discipline | 8/10 |
| FastAPI-specific rules | 7/10 |
| Async testing | 8/10 |
| Database integration | 8/10 |
| Maintainability | 8/10 |
| Avoidance of overly rigid rules | 6/10 |

## Conclusion

The test architecture is good and does not need redesigning.

The strongest parts are:

- clear unit/integration separation;
- good isolation discipline;
- sensible mocking philosophy;
- real database integration;
- migration testing;
- assertions against both API contracts and persisted state.

The main improvement is to replace several absolute rules with statements of the actual invariant the project wants to preserve.

The two technically important changes are:

1. explicitly allowing a test-controlled real DB session through FastAPI dependency injection when needed for rollback isolation;
2. explicitly handling FastAPI lifespan when testing through `TestClient` or HTTPX `ASGITransport`.

Everything else is primarily refinement for readability, maintainability, and future-proofing.
