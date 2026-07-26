# Echo Companion

Echo Companion is an open-source, always-on AI companion for people living with dementia, including Alzheimer's disease. It continuously observes the surrounding environment, organizes what it detects into an evidence-backed autobiographical memory, and answers questions about past events in a warm, patient manner.

Echo is designed for a dedicated Android tablet or phone and communicates in **Russian and English** through a lip-synced avatar.

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
9. Respond conversationally and state uncertainty when the evidence is insufficient.

## Planned Capabilities

- **Continuous ambient memory:** always-on cloud ASR for Russian and English.
- **Speaker diarization and attribution:** separates speaker turns, then identifies the patient, known family members, unknown people, media, or Echo when evidence permits.
- **Multimodal perception:** combines speech with selected camera observations.
- **Autobiographical event graph:** represents people, places, objects, routines, and events with links to supporting evidence.
- **Grounded recall:** combines structured filters, vector retrieval, graph traversal, and source evidence.
- **Echo-speech exclusion:** stores Echo's generated utterances directly but prevents them from being re-ingested as environmental speech.
- **Patient-facing avatar:** a warm 2D talking head with lip sync, implemented in Godot.
- **Optional active camera:** an independently mounted pan-tilt camera controlled by an Arduino-compatible Wi-Fi board for targeted room observation.

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
- **Postgres is the source of truth.** Neo4j is a rebuildable semantic projection populated through an idempotent outbox pipeline.
- **Quality over inference cost.** Several hundred US dollars per patient per month is acceptable when it materially improves usefulness and reliability.
- **Godot-first client development.** GDScript is used until profiling demonstrates a concrete need for C++.
- **Provider choice belongs to the operator.** Echo protects data within its own storage, transport, accounts, logs, and backups. The privacy implications of selected cloud model providers are the operator's responsibility.

## Project Structure

```text
echo-companion/
├── design_docs/
│   └── architecture.md
├── server/                 # Python server and processing workers
├── client/                 # Godot Android client
├── firmware/               # Optional pan-tilt controller firmware
└── evaluation/             # Recorded-input replay and quality evaluation
```

## Initial Roadmap

1. Build an offline replay and evaluation harness using representative household audio.
2. Implement evidence-preserving audio ingestion, ASR, diarization, and speaker attribution.
3. Implement event extraction, Postgres storage, Neo4j projection, and grounded retrieval.
4. Add the Godot avatar, wake-word interaction, TTS, and Echo-speech exclusion.
5. Add fixed-camera observations and multimodal event fusion.
6. Add the optional Arduino-controlled pan-tilt camera for active perception.
7. Evaluate usefulness with the target patient and iterate on memory and conversational behavior.

## License

GNU Affero General Public License v3.0. See [`LICENSE`](LICENSE).
