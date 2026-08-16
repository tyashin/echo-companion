# Python Unit Test Rules

Rules for unit tests in `server/tests/unit/`. For tests against real infrastructure see
`integration_test_rules.md`. Test runner: **pytest** (`uv run pytest`).

## Layout & naming

- **Mirror the source folder structure.** `tests/unit/` replicates the directory tree of the
  source root: `<source-root>/foo/bar.py` → `tests/unit/foo/test_bar.py`. With a `src/` layout
  the source root is `src/`, so `src/foo/bar.py` → `tests/unit/foo/test_bar.py`.
- One test file per source module is the default, not a hard rule — split a large module's
  tests by concern (`test_service_creation.py`, `test_service_permissions.py`) or combine tiny
  related modules when that materially improves readability and discoverability.
- Test files are named `test_<module>.py`; test functions
  `test_<unit>_<scenario>_<expected_result>` — the name alone should say what broke.
- No `__init__.py` in test directories. Pytest runs with `--import-mode=importlib` (see
  `pyproject.toml`), so duplicate basenames in different directories are fine; without that
  setting every test file basename must be unique.

## What counts as a unit test

- Tests one unit (function/class/module) in isolation. **No real DB, network, clock,
  environment, or external/persistent filesystem state** — replace those boundaries with
  mocks/fakes. If filesystem behavior is part of the unit's contract, use `tmp_path`: an
  isolated temp directory is not an external dependency.
- Fast: a single test runs in well under 100 ms; the whole unit suite in seconds. If a test
  needs a running service, it is an integration test — move it.
- Test public behavior and contracts, not implementation details. If a behavior-preserving
  refactor breaks the test, the test is wrong.
- Typical targets: domain logic, service logic in isolation, validators, transformations and
  parsing, calculations, error branches, edge cases, boundary values, authorization decisions
  whose dependencies can be isolated.

## Test structure

- Arrange–Act–Assert: setup, one action, assertions. One behavior per test; several asserts
  are fine when they describe the same behavior.
- Do not use control flow to encode multiple independent test cases — use
  `@pytest.mark.parametrize` for input matrices instead. A small loop asserting an invariant
  over one returned structure is fine.
- Expect exceptions with `pytest.raises(..., match=...)`, never with try/except in the test.

## Fixtures

- Use fixtures for reusable setup, dependency injection, and resource lifecycle management —
  not for trivial test-specific construction (`user = User(name="Alice")` stays inline).
  Prefer `yield` fixtures whenever cleanup is required, so it runs even when the test fails.
- Shared fixtures live in the nearest `conftest.py` to the tests that use them. Never import
  from a `conftest.py`.
- **Scope = when the fixture is created.** Default `function` scope (fresh before every single
  test). Widen to `module`/`session` (created once before the suite) only for objects that are
  expensive to build **and** immutable. Never let a wide-scoped fixture carry mutable state
  between tests.
- Use factory-as-fixture (a fixture returning a builder function) for domain objects that
  tests need with different overrides.
- Prefer built-in fixtures over hand-rolled helpers: `tmp_path` for files, `monkeypatch` for
  attributes/env vars, `capsys`/`caplog` for output.

## Mocks

- Mock at the boundaries you own: DB session, external clients, clock, randomness, env. Never
  mock the unit under test itself.
- Patch where the name is **looked up**, not where it is defined: if `package/module.py` does
  `from lib import helper`, patch `package.module.helper`, not `lib.helper`.
- Use `monkeypatch` for attributes and environment, `unittest.mock.Mock`/`MagicMock` for
  collaborators, and `AsyncMock` for async dependencies (pytest-asyncio runs in
  `asyncio_mode = "auto"`). Prefer `autospec=True` so mocks catch signature drift.
- Assert on mock interactions only when the call itself is the contract (e.g. "publishes one
  event"). Otherwise assert on results, not on how they were produced.
- Mocks follow the same scoping rules as fixtures: built per test by default; a shared mock
  across tests is a bug waiting to happen.

## Determinism & independence

- Tests are independent and order-proof: each builds its own state, none relies on another
  test's side effects. `pytest tests/unit` must pass with any subset, in any order.
- No `sleep`, no real clock dependence — freeze or inject time. Seed all randomness.
- No dependence on env vars, locale, timezone, or the current working directory; set what you
  need via `monkeypatch.setenv` / `monkeypatch.chdir`.
- `uv run pytest tests/unit` must pass with **no services running** (no Postgres, no Neo4j).

## Hygiene

- Test code is real code: same ruff rules, type annotations, and readability standards as the
  source.
- Don't chase coverage numbers; do chase edge cases, error paths, and boundary values.
- Directory separation is the selection mechanism (`tests/unit` vs `tests/integration`); add
  `pytest.mark` labels only when a rule above isn't enough.
