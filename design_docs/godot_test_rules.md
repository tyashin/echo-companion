# Godot Test Rules

Rules for client tests under `client/tests/`, covering unit tests (pure GDScript logic) and
scene/integration tests (real scenes driven through the scene runner). Test framework:
**GdUnit4 6.2.x**, compatible with Godot 4.7.1. The exact GdUnit4 version is pinned in the
project and updated deliberately — never float on a version range. Suites execute headless via
`godot --headless`.

## Layout & naming

- Tests live in three directories:
  - `tests/unit/` — pure GDScript logic, no scene tree;
  - `tests/integration/` — scene tests and persistence tests;
  - `tests/fixtures/` — shared helpers, fakes, and test data.
- **Mirror the source folder structure** inside `tests/unit/` and `tests/integration/`:
  `scripts/player/movement.gd` → `tests/unit/player/movement_test.gd`.
- One test suite per source class is the default, not a hard rule — split or combine when that
  materially improves readability and discoverability.
- Test suites extend `GdUnitTestSuite`, files named `*_test.gd`; test functions
  `test_<unit>_<scenario>_<expected_result>` — the name alone should say what broke.
- Directory separation is the selection mechanism: fast PR checks run `tests/unit/`, full CI
  runs `tests/unit/` + `tests/integration/`. This separation also keeps "unit test" from
  drifting toward tests that instantiate half the scene tree.

## Design for testability

- **Separate engine-independent logic from engine-dependent behaviour.** Domain rules,
  calculations, decision logic, and state transformations go into independently testable
  classes where practical. Node scripts may legitimately contain behaviour that depends on the
  scene tree, lifecycle, input, physics, rendering, or other Godot APIs — keep orchestration
  nodes thin where doing so improves testability and maintainability. The goal is separation
  of concerns, not eliminating logic from Nodes.
- Default homes, as guidance rather than law: `RefCounted` for ordinary domain/service/helper
  objects, `Resource` for configuration and serializable data objects, `Node` for
  scene-tree- and engine-dependent behaviour.
- Domain and reusable logic receives dependencies explicitly. Scene/composition nodes may
  resolve child nodes (`$HealthBar`) and application-level autoloads as part of wiring. What
  to avoid is hidden global dependencies inside logic that should be reusable and testable.
- **Wrap boundaries that are difficult, nondeterministic, or hardware-dependent** — camera
  capture, microphone input, networking, persistent storage, OS APIs — in thin adapter
  classes, and fake the adapter in tests.

## Unit tests

- No scene tree, rendering, or platform boundaries: a unit test instantiates the class under
  test directly and fakes its collaborators — GdUnit4 `mock()`/`spy()` for GDScript classes,
  hand-rolled fakes where a mock can't express the behavior.
- Unit tests do not depend on mutable application-global state (autoloads, singletons).
- **Setup scopes follow fixture discipline.** `before()`/`after()` run once per suite — only
  for expensive, immutable work (e.g. preloading a resource); `before_test()`/`after_test()`
  handle anything mutable. Never carry mutable state between tests through suite-level setup.
- Deterministic: fixed RNG seeds; no wall-clock waits (`OS.delay_msec`); float/vector
  assertions are approximate (`is_equal_approx()` matchers); no dependence on a window or
  display server.
- Independent and order-proof: any order, any subset. Tests leave no orphan Nodes or other
  manually managed objects behind; `RefCounted`/`Resource` objects follow normal
  reference-counted lifetime and need no manual freeing. GdUnit4 orphan-node detection stays
  enabled, and a leak fails the test.
- The unit suite runs headless with **no hardware and no server**: no camera, no microphone,
  no network.

## Scene tests (integration)

- **Real scenes, fake world.** Instantiate actual scenes via `scene_runner()` — the scene
  under test is never replaced by a fake. Fakes live at external boundaries: remote server,
  camera, microphone, OS services.
- **Persistence is the exception**: save/load integration tests use real `FileAccess` /
  `ResourceSaver` round-trips against isolated temporary paths. When a boundary is owned by
  the application and is itself under test, use the real implementation — otherwise every
  test can pass while persistence is actually broken.
- **Drive by frames and signals, not time**: `simulate_frames()`, awaiting `process_frame` /
  `physics_frame`, `simulate_input()` / `simulate_key_press()` for input. No real sleeps
  anywhere.
- Assert invariants, not exact physics: ranges, approximations, and state transitions (e.g.
  "reached the floor", "velocity ≈ 0", "state is GROUNDED") — not precise float positions,
  unless an exact value is genuinely part of the contract.
- **Signal contracts are tested**: assert emissions and payloads (`assert_signal()` /
  `await_signal_on()`); every signal wait has a timeout so a missing signal fails fast instead
  of hanging the suite.
- Teardown is explicit: fresh scene instance per test, zero orphan nodes afterwards. A shared
  scene across tests only if stateless — and then its state is reset in `before_test()`. Any
  global/autoload state mutated by an integration test is restored in `after_test()`.
- Coverage split: domain-logic branches and boundary values belong primarily in unit tests;
  scene tests cover wiring, lifecycle, engine interaction, state transitions, and
  integration-specific edge cases (node removed during a signal callback, pause, tree
  exit/enter, focus routing, scene reload).
- Prefer unit tests when behaviour can be tested meaningfully without the engine; keep scene
  tests focused and avoid duplicating pure-logic cases. The unit/scene ratio is guidance, not
  a quota.

## Hardware, E2E & manual layers

- The full testing model is layered: unit → scene integration → **hardware/system tests** →
  client↔server E2E → manual acceptance. The layers above integration are planned
  deliberately, not lumped together as "profiling".
- Hardware/system tests exercise real devices — e.g. the tablet camera actually opens and
  delivers frames, real microphone capture, real networking. They run on demand, before
  releases, or on target-device runners — not on every commit.
- Client↔server E2E tests run the real client against the real server, on demand. Ordinary
  unit and scene tests never touch a live server: the networking adapter is faked.
- Manual acceptance/gameplay validation on the target device closes the loop; it is a
  separate activity from automated hardware tests.

## Running & hygiene

- The whole automated suite (unit + integration) runs via the GdUnit4 command-line runner
  under `godot --headless`, with a non-zero exit code on failure, locally and in CI. Tests
  needing a real GPU, window, camera, or microphone belong to the hardware/system layer, not
  this suite.
- Test code is real code: statically typed GDScript, `gdlint`/`gdformat` clean, same review
  bar as `scripts/`.
