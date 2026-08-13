# Echo Companion

Echo Companion is an open-source, always-on AI companion for people living with dementia, including Alzheimer's disease. It continuously observes the surrounding environment, organizes what it detects into an evidence-backed autobiographical memory, answers questions about past events, and proactively socializes — discussing topics the patient enjoys — in a warm, patient manner.

Echo is designed for a dedicated Android tablet or phone and communicates in **Russian and English** through a lip-synced avatar with a single, stable persona: a devoted personal secretary to the patient.

> **Project status:** early design and experimentation. No production implementation exists yet.

## Core Idea

Echo does not treat model-generated summaries as unquestionable facts. It preserves the observations behind every memory—audio segments, transcripts, speaker attribution, images, camera pose, timestamps, and model outputs—and uses them to build a continuously updated event graph.

The intended loop is:

1. Capture continuous audio and selected visual observations.
2. Transcribe speech and separate speakers.
3. Identify known speakers when evidence is sufficient.
4. Detect people, objects, places, and candidate events.
5. Fuse evidence from audio, vision, time, and prior context.
6. Store the source evidence in Postgres.
7. Project people, events, routines, and relationships into Neo4j.
8. Retrieve relevant evidence when the patient asks a question.
9. Respond conversationally, expressing uncertainty naturally when evidence is insufficient — confidence lives in the data model, not in the spoken register.

## Planned Capabilities

- **Sound-gated ambient memory:** client-side voice-activity detection gates cloud ASR for Russian and English — speech is streamed, silence is not billed.
- **Media exclusion:** television and radio audio is kept out of memory by default, unless the patient explicitly asks Echo to remember something.
- **Speaker diarization and attribution:** separates speaker turns, then identifies the patient, known family members, unknown people, media, or Echo when evidence permits — and abstains when it does not.
- **Multimodal perception:** combines speech with selected camera observations.
- **Autobiographical event graph:** represents people, places, objects, routines, and events with links to supporting evidence.
- **Biographical memory:** incorporates the patient's life stories using fuzzy and relative time, family-seeded biography anchors, and consolidation of repeated tellings.
- **Proactive socialization:** initiates conversations on topics the patient enjoys, chosen from the memory graph under family-set constraints.
- **Grounded recall:** combines structured filters, vector retrieval, graph traversal, and source evidence.
- **Trusted circle:** family members provide facts, confirmations, and corrections through a text-chat channel, with trust levels and scoped access.
- **Echo-speech exclusion:** stores Echo's generated utterances directly but prevents them from being re-ingested as environmental speech.
- **Patient-facing avatar:** a warm 2D talking head with lip sync in the early phases; the long-term direction is a locally rendered photorealistic 3D avatar (MetaHuman-class, Godot) — never cloud-rendered video.
- **Optional active camera (deferred):** an independently mounted pan-tilt camera controlled by an Arduino-compatible Wi-Fi board for targeted room observation.

## Architecture

| Layer | Planned technology |
|---|---|
| Android client | Godot 4.7.1+ and GDScript |
| Native optimization, only when measured | C++ GDExtension |
| Server | Python and FastAPI |
| Evidence ledger and vector search | Postgres and pgvector |
| Autobiographical event graph | Neo4j |
| Audio transport | Resumable binary WebSocket protocol |
| Pan-tilt camera control | Godot to Arduino-compatible controller over the local network |
| ML providers | Configurable cloud ASR, LLM, vision, embedding, and TTS providers |

The Android client remains a Godot project. Kotlin is not part of the planned implementation. C++ is reserved for performance-critical paths that cannot be handled adequately in GDScript.

See [`design_docs/architecture.md`](design_docs/architecture.md) for the complete design.

## Design Principles

- **Evidence before interpretation.** Raw observations remain available after summaries and graph projections are created.
- **Events are first-class nodes.** A visit, telephone call, meal, or object movement is modeled as an event with participants, time, confidence, and provenance.
- **Uncertainty is retained.** The system distinguishes observations, assertions, inferences, confirmations, disputes, and retractions.
- **One stable persona; warm voice, rigorous data.** A single devoted-secretary persona never changes character; confidence and provenance live in the data model, not in the spoken register.
- **Postgres is the source of truth.** Neo4j is a rebuildable semantic projection populated through an idempotent outbox pipeline.
- **Quality over inference cost, at prototype stage.** Several hundred US dollars per patient per month is acceptable while the design is being validated; sound gating already removes the largest driver, and later phases revisit the budget with real measurements.
- **Godot-first client development.** GDScript is used until profiling demonstrates a concrete need for C++.
- **Provider choice belongs to the operator.** Echo protects data within its own storage, transport, accounts, logs, and backups. The privacy implications of selected cloud model providers are the operator's responsibility.

## Project Structure

```text
echo-companion/
├── design_docs/
│   ├── architecture.md
│   ├── implementation_plan.md
│   └── open_questions.md
├── server/                 # Python server and processing workers
├── client/                 # Godot Android client
├── firmware/               # Optional pan-tilt controller firmware
└── evaluation/             # Recorded-input replay and quality evaluation
```

## Initial Roadmap

1. **Probe the riskiest assumptions:** patient interaction probe with persona candidates, Godot camera and audio spikes, and an offline replay harness over representative household audio.
2. **Build the memory loop offline:** evidence-preserving ingestion, sound-gated ASR with media exclusion, diarization, event and biographical extraction, Postgres storage, Neo4j projection, grounded retrieval.
3. **Go live:** the Godot client with resumable streaming, Echo-speech exclusion, and unattended operation.
4. **Become a companion:** frozen persona, grounded conversation, proactive socialization, TTS and avatar, and the trusted-circle chat channel for the family.
5. **Add eyes:** fixed-camera observations and multimodal event fusion.
6. **Extend and harden:** optional pan-tilt active perception, family administration, retention tooling.

Details and go/no-go gates are in [`design_docs/implementation_plan.md`](design_docs/implementation_plan.md); unresolved decisions are tracked in [`design_docs/open_questions.md`](design_docs/open_questions.md).

## License

GNU Affero General Public License v3.0. See [`LICENSE`](LICENSE).
