# Echo Companion — Agent Notes

## Project status (as of 2026-08-07)

Design phase; no implementation code exists yet. The design docs were reworked in a design-review discussion and reflect all decisions to date:

- `design_docs/architecture.md` — system design, the source of truth for decisions
- `design_docs/implementation_plan.md` — Phases 0–2, iterative, with done-when criteria and go/no-go gates
- `design_docs/open_questions.md` — review questions with SETTLED / PARTIAL / OPEN statuses
- `README.md` — public summary, kept consistent with `design_docs/`

## Next step

Phase 0.1 from the implementation plan: project skeleton — Python server (FastAPI, Pydantic, SQLAlchemy/SQLModel + Alembic, Postgres + pgvector, Neo4j CE via docker-compose) and a Godot 4.7.1+ project running on the Linux dev PC.

## Working agreements

- Update the design docs as decisions settle; keep `README.md` consistent with `design_docs/`.
- Iterative, risk-first development — the user prefers starting over waterfall planning.
- Risk order: patient engagement > household audio quality (ASR/diarization/media gate) > Godot camera path > everything else.
- Client development happens on the Linux PC; the tablet is only for camera-backend validation and profiling.
- Git commits are made by the user, not the agent.

## Context

- The patient is male; the household speaks Russian and English. The project owner is a family member (son) who will act as a trusted-circle admin (e.g., provides prescription facts) — see §17 of the architecture doc.
- Settled decisions — do not relitigate without new evidence: Neo4j stays (with the §8.4/§8.6 invariants); no hard wake word (high-recall named-address + push-to-talk); sound-gated ASR; media exclusion by default; single stable persona (devoted secretary, to be validated against alternatives in the Phase 0 probe); pan-tilt hardware deferred to Phase 4; text chat (not voice) is the primary trusted-circle channel.
