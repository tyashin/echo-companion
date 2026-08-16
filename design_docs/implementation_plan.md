# Echo Companion: Implementation Plan, Phases 0–2

## Status and intent

This plan covers the first three phases of the roadmap in `architecture.md` §20 — Phase 0 (probe, spikes, evaluation harness), Phase 1 (evidence-preserving audio memory), and Phase 2 (interactive companion). Phases 3–5 are deliberately not planned here; they will be planned when earlier results constrain the choices.

This is not a waterfall plan. The direction is fixed; the scope inside each increment is adjustable. Every increment ends in something demonstrable and, where marked, a go/no-go decision. Update this file as increments complete and decisions settle — it is a working document, not a contract.

## Risk order

What can kill the project, in the order it should be retired:

1. **Patient engagement** — does the patient talk to it, does it help or confuse? (Phase 0 probe)
2. **Audio pipeline quality on real household audio** — ASR, diarization, media gate, overlap. (Phase 0 harness)
3. **Godot camera path on the target tablet** — the riskiest client dependency. (Phase 0 spike)
4. Everything else is engineering.

## Working agreements

- Evidence-first: no derived record without provenance to source observations (`architecture.md` §3.1).
- Postgres is the source of truth; Neo4j must be rebuildable from it at all times (§8.4, §8.6).
- Prompt, persona, and extractor versions are recorded on every derived record; changes are replayed through the evaluation harness before they ship.
- The Godot client is developed primarily on the Linux dev PC; the tablet is used for camera-backend validation and profiling (§5.1 development workflow).
- The cost stance is prototype-scoped: measure, don't minimize (§18).

---

## Phase 0: Probe, spikes, and evaluation harness

**Purpose:** retire the three existential risks before building the memory pipeline.

### 0.1 Project skeleton and dev environment

**Status: DONE (2026-08-13).** Server skeleton in `server/` (flat app layout, uv, Python 3.13, FastAPI, SQLAlchemy 2.0 async + Alembic, `/health` with Postgres check, pytest + ruff); `docker-compose.yml` at repo root runs Postgres 17 + pgvector (port 5432) and Neo4j 5 CE (host ports 17474/17687 — a non-Docker Neo4j occupies the defaults on the dev PC); Godot 4.7.1 client skeleton in `client/` runs headless; Godot MCP bridge ([tugcantopaloglu/godot-mcp](https://github.com/tugcantopaloglu/godot-mcp), 157 tools, 4.7-tested) installed at `~/godot/godot-mcp` with the `McpInteractionServer` autoload in the client and project-level `.kimi-code/mcp.json`; GitHub Actions CI (`.github/workflows/ci.yml`): ruff, pytest, `alembic upgrade head`, `alembic check`. Python dev happens locally under uv; only Postgres/Neo4j are containerized in dev.

- Server repo: current-stable Python, FastAPI, Pydantic, SQLAlchemy/SQLModel with Alembic migrations; Postgres + pgvector; Neo4j Community Edition; docker-compose for local development.
- Godot project skeleton (4.7.1+) that runs on the Linux dev PC, with a Godot MCP server (editor bridge) installed so the agent can inspect the scene tree, run the project, and read errors/screenshots from the live editor. Selection criteria: Godot 4.7.1+ support; GDScript-based game code per §5.1 (a C#-based plugin requires the .NET editor build but does not change the game-language decision).
- CI: lint, unit tests, migration check.

*Done when:* `docker compose up` brings up Postgres and Neo4j; the server serves a health endpoint; the Godot project runs on desktop.

### 0.2 Godot camera spike (tablet)

**Status: IN PROGRESS (2026-08-16).** Spike project written in `spikes/camera_spike/`: `CameraFeed` → `get_image()` readback → JPEG encode harness logging per-second metrics (feed fps, extracted fps, stage timings, CPU, thermal) to CSV + JSON summary, with an adb-side thermal/CPU collector in `tools/` and a headless `--self-test` validated on desktop. Android export preset prepared; SDK reinstall on the dev PC is pending (user-owned). Remaining: deploy to the tablet, 30-minute run, record numbers and the decision below.

- Minimal Godot project on the target tablet: acquire frames via `CameraServer`/`CameraFeed`, `get_image()` readback, encode; measure sustained achievable frame rate, latency, CPU and thermal behavior over a 30-minute run.

*Done when:* measured numbers are written down and a decision is recorded: GDScript path sufficient / C++ GDExtension required / camera plan revised. This is the commit-or-abandon test for the whole vision path.

### 0.3 Godot audio streaming spike (Linux desktop)

- `AudioStreamMicrophone` + `AudioEffectCapture` → client-side VAD with pre-roll buffer → framed binary WebSocket stream (epochs, sequence numbers, acknowledgements) → Python server records to disk.

*Done when:* a one-hour desktop session streams with no lost or duplicated frames, and VAD gating keeps speech onsets intact.

### 0.4 Patient interaction probe

- Minimal interactive prototype (desktop or tablet): placeholder avatar, named-address or push-to-talk trigger, ASR → LLM → TTS loop over a hand-curated memory file (a few family-provided facts and recent events).
- Test 2–3 persona candidates per §15.1 (devoted secretary; peer/old friend; plain warm companion) in short sessions over one to two weeks.
- Measure: does the patient address it spontaneously; conversation length; engagement vs. confusion or distress; which persona register works; per-stage ASR/LLM/TTS latency feeding the §15.6 budget.

*Done when:* a persona is chosen and frozen as configuration v1, and engagement evidence says proceed — or stop, which is a legitimate and cheap outcome. **Go/no-go gate.**

### 0.5 Household audio corpus

- Collect and annotate consented household audio: patient speech, family speech, TV/radio playing, overlapping speech, Russian/English code-switching, silence. Target tens of hours with rough ground truth (who spoke, when, whether media was playing).

*Done when:* the corpus is versioned with an annotation guide.

### 0.6 ASR and diarization benchmark harness

- Replayable runners over the corpus: 2–3 ASR providers and a diarization pipeline. Metrics per §19: WER (Russian, English, code-switched), DER, patient-vs-other classification, media false-positive and false-negative rates, timestamp continuity across session rotation.

*Done when:* provider choices are recorded with measured numbers, and known failure modes are documented. **Go/no-go gate** on audio-pipeline adequacy for our data, not benchmark marketing.

### 0.7 Media gate experiment

- Media/household separation (TV/radio vs. people in the room), evaluated on the corpus including overlap cases (TV on while people talk).

*Done when:* precision and recall are measured and the integration point (pre-ASR) is validated on real data.

### 0.8 Event ontology and schema v1

- Initial event ontology (calls, visits, meals, medication, conversations, media-request, ...); Postgres schema v1 (§7 tables plus `principals` and `trust_actions`, the `origin` marker on derived records); Neo4j uniqueness constraints on stable IDs.

*Done when:* migrations apply cleanly and sample records round-trip through the outbox into Neo4j.

### Phase 0 gate

Proceed to Phase 1 only if: the probe shows engagement; measured ASR/diarization/media-gate quality on **our** corpus is adequate (thresholds fixed once baselines are known); the camera spike is resolved one way or another.

---

## Phase 1: Evidence-preserving audio memory

Split so the memory loop is validated offline before live transport exists.

### Phase 1a: offline memory pipeline

1. File-based ingestion: corpus audio → normalization → evidence-ledger rows (devices, sessions, segments).
2. ASR and diarization adapters behind narrow interfaces; media gate applied pre-ASR; speaker segments and clusters; conservative identification with `UNCERTAIN` as a first-class outcome.
3. Utterance and assertion extraction preserving polarity, tense, and modality (§6.5); prompt/extractor versions recorded on every record.
4. Candidate events with `event_evidence` links and the status ladder; manual trusted-principal verification entry (form/CLI) with `FAMILY_PROVIDED` origin and the §6.6 promotion rule.
5. Entity resolution: mentions → candidate links, no destructive merges (§8.3).
6. Biographical layer (§8.5): fuzzy/relative time extraction, era anchors, family-seeded skeleton biography, retelling consolidation into canonical story nodes, valence flags.
7. Outbox projector → Neo4j: idempotent `MERGE`, checkpoints, and a tested rebuild-from-Postgres path.
8. Hybrid retrieval (Postgres filters + pgvector + capped graph traversal) → evidence bundle → CLI Q&A over recordings with source citations.
9. Evaluation: replay harness wired to the §19 metrics; fixed evaluation set v1.

*Done when:* retrospective questions over the corpus are answered with traceable evidence bundles; Neo4j rebuild is demonstrated; the metrics baseline is recorded.

### Phase 1b: live audio client

1. Godot client (desktop first, then tablet): VAD-gated streaming, durable local spool, reconnect with bounded backoff, resumable epochs, idempotent retransmission.
2. Server transport: epochs/sequence/acks, heartbeat, backpressure; provider session rotation hidden from the client.
3. Half-duplex echo-speech exclusion with failure handling per §9.6: server-authoritative suppression window bounded by playback duration, timeouts, idempotent re-sync on reconnect.
4. Minimal family-facing status screen on the device.
5. Soak test: tablet runs unattended for 24 hours; monitor ASR gaps, dropped frames, duplicate streams, projection lag, storage growth.

*Done when:* the 24-hour unattended run completes with no lost or duplicated audio, and live questions can be asked against same-day memory.

---

## Phase 2: Interactive companion

1. **Persona configuration v1** (frozen from the probe): secretary persona, registers (briefing / conversation / calming / quiet), behavioral invariants (§15.2), family-owned honesty policy.
2. **Intent of address** (§15.4): high-recall named-address detector plus push-to-talk fallback; "may Echo speak now" policy v1 (activity, time of day, who else is present, recent engagement, affect).
3. **Grounded response generation** from evidence bundles, with confidence-to-phrasing rules (§15.2 rule 4).
4. **Interactive-loop latency** (§15.6): pipelined turn path — streaming ASR partials, speculative retrieval, sentence-streamed LLM→TTS, answer cache for repeated questions, pre-rendered acknowledgment clips; per-stage timings recorded per turn and checked against the budget.
5. **TTS + viseme timing; 2D Godot avatar** — simple, warm, stylized, not resembling a relative. A photorealistic 3D avatar is a later-phase goal (§15.3).
6. **Proactive socialization loop** (§15.5): "what to talk about" retrieval from the graph, valence approach/avoid constraints, strict rate limiting, reminiscence invitations.
7. **Trusted circle v1** (§17): text-chat channel (Telegram bot or similar) as the primary family interface — seeding (biography, interests, medication schedules), verification queue (confirm/dispute candidate events), corrections; Admin/Contributor roles; scoped query access with conservative defaults; every trust action recorded as evidence.
8. **Echo's own turns** stored as generated utterances for reference resolution across conversations.
9. **Evaluation additions** per §19: engagement metrics, persona consistency, repetition warmth, confabulation-agreement rate, intent-of-address quality — automated in the harness where possible, family-judged otherwise.

*Done when:* a multi-week pilot with the patient completes; the family reviews engagement and safety metrics weekly; go/no-go is recorded for Phase 3 (vision).

---

## Explicitly out of scope for Phases 0–2

- Vision pipeline beyond the Phase 0 camera spike (Phase 3).
- Pan-tilt hardware (Phase 4 — deferred by decision; nothing earlier depends on it).
- Multi-device, multi-household, administration polish, the "what Echo learned" timeline (Phase 5).
- Photorealistic avatar work (later-phase goal, §15.3).
- C++ GDExtension work, unless the camera spike proves it necessary.
