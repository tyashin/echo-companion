# Echo Companion: Open Questions

These questions arise from review of `architecture.md`. They are not objections to the design; they identify decisions that are either unresolved, under-justified, or worth validating before significant code is written. Grouped roughly by area, ranked within each group by how much they would worry me.

---

## Turn management and interaction

1. **How does Echo know speech is directed at it?** The doc covers an always-on companion and the `MEDIA` speaker category, but never addresses intent-of-address: speech directed at a visitor, to the television, or to the patient themselves versus speech meant for Echo. For an always-on device this is the gating UX problem, larger than wake-word mechanics. It is currently absent from both §9/§15 and the §21 open-questions list. What is the detection strategy, and is it evaluated in the harness?

2. **Is a wake word the right gate for this user (Phase 2)?** A person with advancing dementia may not reliably produce a fixed wake word, especially under stress or sundowning. Relying on one risks under-serving the exact population the system is built for. Have you considered push-to-talk, proximity/gaze triggers, or a high-recall named-address detector ("Эхо, ...") rather than a hard gate? At minimum this should be flagged as a risk, not treated as a settled choice.

3. **How is patient affective state handled?** §15.2 is about answering questions. Dementia care also includes agitation, distress, and sundowning. Should an always-on companion detect and adapt to affect? This seems like a larger product gap than several technical sections that receive detailed treatment.

---

## Architecture and components

4. **Is Neo4j justified at single-patient scale?** The Postgres schema already models entities, mentions, candidate_events, event_evidence, and the doc itself cites PostgreSQL recursive CTEs as a reference. For one patient's graph, Postgres + pgvector + recursive traversal likely covers §14 retrieval without a second database to operate, back up, and keep consistent. The justification ("the graph is a primary memory representation, not merely query optimization") is asserted but not substantiated: everything in §8 is expressible relationally given the schema. Should Neo4j be deferred until a concrete query demonstrates recursive CTEs are inadequate, and treated as optional in Phase 1 rather than load-bearing? What does the outbox/projector machinery cost in operational complexity?

5. **Is Godot Android camera support mature enough to commit to (§5.1, §10.2)?** `CameraServer`/`CameraFeed` on Android has historically been limited and finicky: frame access, lifecycle, and permissions have rough edges. The audio path (microphone + `AudioEffectCapture` + `WebSocketPeer`) is solid; the camera path is the riskiest dependency in the doc. Has the assumed maturity of "Godot 4.7.1+" been verified against a real device? Should a camera spike move earlier than Phase 3 to de-risk the whole vision path before downstream work commits to it?

6. **Is the half-duplex Echo-speech exclusion fully specified for failure paths (§9.5)?** The doc describes the happy path. What happens when the client crashes mid-playback, when `playback_ended` is lost over a flaky link, or when the server restarts while suppression is active? Does ingestion stay suppressed indefinitely, or resume early and ingest Echo's own voice? The state machine needs defined timeouts, a server-authoritative suppression window bounded by a known playback duration, and idempotent re-sync on reconnect. What are these values?

---

## Model behavior

7. **How are confidence values from different providers made comparable during fusion (§12)?** A 0.64 from one VLM is not equal to 0.64 from another, yet fusion treats them as commensurate. Should fusion calibrate per-provider, or operate on ordinal/rank evidence instead of raw scores? This is a known hard problem worth naming explicitly rather than leaving implicit.

8. **What reranks the evidence bundle (§14.5)?** "Rerank by relevance, confidence, source quality, temporal fit" via what mechanism: a cross-encoder, a learned ranker, or heuristics? This is one of the harder steps in the pipeline and is currently hand-waved.

---

## Scope and phasing

9. **Should Phase 1 be split into an offline-first validation before live streaming?** Phase 1 bundles a live Godot streaming client, the full server-side memory pipeline, Neo4j, and hybrid retrieval. Given Phase 0 collects recorded data, the entire server-side memory/extraction/retrieval loop could be validated offline first, with live streaming added as a Phase 1b. Lower risk, earlier signal on whether the produced memories are useful. Why bundle them?

10. **What evidence threshold promotes a candidate event between statuses (§6.5, §21.10)?** This is already in the §21 list but worth elevating: promotion rules are a core correctness property of the whole evidence model and should be designed, not just asked.

---

## Deployment

11. **Is the cost framing (§18) labeled as prototype-stage?** "Several hundred USD/month acceptable, measured not minimized" reads as a stance rather than a temporary concession. Continuous ASR (~720 hours/month) plus VLM bursts plus LLM extraction can exceed that quickly. Is this intended to carry into later phases, and should it be re-stated as prototype-scoped?

---

## Minor

12. **Retention cross-dependency (§7):** deletion must invalidate all dependent projections. Is the dependency graph from raw observation to derived event to Neo4j projection traced and enforceable, or only asserted?

13. **Speaker-identification abstention:** identification produces candidates (PATIENT / KNOWN_FAMILY_MEMBER / UNKNOWN_PERSON / MEDIA / ECHO / UNCERTAIN). What is the policy when multiple categories are plausible, and how is abstention surfaced to retrieval and answer generation?
