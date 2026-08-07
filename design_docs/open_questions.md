# Echo Companion: Open Questions

These questions arise from review of `architecture.md`. The file now also tracks resolution status, updated 2026-08-07 after the design-review discussion; statuses reference the updated `architecture.md` and `implementation_plan.md`.

Legend: **SETTLED** — decided and written into the docs; **PARTIAL** — direction decided, details open; **OPEN** — still needs an answer.

---

## Turn management and interaction

1. **How does Echo know speech is directed at it?** — **PARTIAL.** Elevated to a load-bearing requirement (§15.4): the gate is a high-recall named-address detector plus push-to-talk fallback, not a hard wake word, and proactive speech additionally requires a "may Echo speak now" context policy. The concrete detection approach and its harness evaluation remain open (§21.13).

2. **Is a wake word the right gate for this user?** — **SETTLED.** No hard wake word: the target user may not reliably produce one under stress or sundowning. Named-address detection with recall favored over precision, push-to-talk as explicit fallback; validated with the real patient in the Phase 0 probe.

3. **How is patient affective state handled?** — **PARTIAL.** Accepted as a product requirement: calming register (§15.1), proactive-speech gating by affect and time of day (§15.4), valence approach/avoid flags on topics and stories (§8.5). A reliable affect-detection strategy is still open (§21.16).

## Architecture and components

4. **Is Neo4j justified at single-patient scale?** — **SETTLED.** Neo4j stays. The safety invariants are now explicit (§8.4, §8.6): rebuildable from Postgres at all times, uniqueness constraints on every stable ID, supernode-aware query discipline, capped traversal depths, scheduled dumps under Community Edition, vector search kept in pgvector.

5. **Is Godot Android camera support mature enough to commit to?** — **SETTLED** (as risk handling). The camera spike moved to Phase 0 (implementation plan 0.2) with measured go/no-go criteria. Client development happens on the Linux dev PC; camera access sits behind a backend interface with a file/replay desktop backend (§5.1).

6. **Is the half-duplex Echo-speech exclusion fully specified for failure paths?** — **PARTIAL.** Requirements are now specified (§9.6): server-authoritative suppression window bounded by known playback duration, ingestion resumes at window expiry on lost `playback_ended` or client crash, idempotent re-sync on reconnect. Concrete timeout values are set during Phase 1b soak testing.

## Model behavior

7. **How are confidence values from different providers made comparable during fusion?** — **OPEN** (§21.14). Default until answered: fuse ordinal/rank evidence rather than raw cross-provider scores.

8. **What reranks the evidence bundle (§14)?** — **OPEN** (§21.15). Heuristics first; the mechanism must be decided before Phase 1a retrieval ships.

## Scope and phasing

9. **Should Phase 1 be split into an offline-first validation before live streaming?** — **SETTLED.** The Phase 1a (offline pipeline) / Phase 1b (live client) split is in §20 and the implementation plan.

10. **What evidence threshold promotes a candidate event between statuses?** — **PARTIAL.** The first concrete rule is adopted (§6.6): confirmation by a trusted principal promotes status. The full threshold design — which signals, what weights, automatic vs. manual — remains open.

## Deployment

11. **Is the cost framing labeled as prototype-stage?** — **SETTLED.** §18 now states the stance is prototype-scoped; sound-gated ASR (§9.2) removes the largest cost driver (billing for silence); later phases revisit the budget with real measurements.

## Minor

12. **Retention cross-dependency (§7):** is the dependency graph from raw observation to derived event to Neo4j projection traced and enforceable? — **OPEN.** Must become enforceable (foreign keys, deletion jobs, projection invalidation), not asserted. Scheduled for the Phase 1a schema work.

13. **Speaker-identification abstention policy** — **OPEN.** `UNCERTAIN` is a first-class label; retrieval and answer generation must surface abstention naturally ("не уверена, кто это был") rather than silently picking a candidate. To be designed with the Phase 1a diarization work.

---

## Questions added since the original review

14. Which named-address detection approach achieves high recall on this patient's speech without constant false triggers? (§21.13)
15. How should valence (approach/avoid) signals be validated, and when must family marks override inference? (§8.5, §15.5, §21.19)
16. What authority should in-person voice actions from trusted-circle members carry, given probabilistic speaker identification? (§17.2, §21.18)
17. How accurate is retelling-merge in practice, and what is the cost of wrongly merging two distinct stories vs. failing to merge one? (§8.5)
18. What per-stage latency do the chosen ASR/LLM/TTS providers achieve on the patient's Russian, and does the pipelined interactive loop meet the §15.6 budget (first audio < 2 s p50, < 4 s p95)? (§15.6, §21.20)
