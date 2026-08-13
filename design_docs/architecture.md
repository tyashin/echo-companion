# Echo Companion: Architecture and Design

## Document Status

This document describes the intended architecture for the first usable Echo Companion system. The project is in the design and experimentation phase; there is no production implementation yet.

The design prioritizes usefulness for a single patient, evidence quality, and rapid iteration. It does not include a planned rewrite into another server language. Python is treated as the production implementation unless measurements demonstrate a concrete reason to change a component.

---

## 1. Overview

Echo Companion is an always-on, multimodal AI companion for a person living with dementia, including Alzheimer's disease. It runs primarily on a dedicated Android tablet or phone, communicates in Russian and English through a lip-synced avatar, continuously observes the surrounding environment, and helps the patient recall past events.

The central technical object is a **continuously updated, multimodal, provenance-bearing autobiographical event graph**.

Echo does not claim direct knowledge of everything that happened. It records observations and model interpretations with their provenance and confidence. For example, audio alone can establish that a speaker said, "I took my medicine," but it cannot prove that medicine was swallowed. Visual evidence may raise confidence but can remain incomplete. The data model must preserve that distinction.

### Target deployment

- One patient in a household.
- Russian and English speech.
- Dedicated Android tablet or phone, normally plugged in and running in the foreground.
- Cloud ASR, LLM, vision, and TTS are acceptable.
- Several hundred US dollars per patient per month is an acceptable operating range when justified by quality.
- Optional fixed and rotating room cameras.
- Family members administer the deployment and choose external model providers.

---

## 2. Product Goals

Echo should:

1. Preserve a searchable history of speech and visible activity around the patient.
2. Separate and, where possible, identify speakers.
3. Represent people, places, objects, routines, and events in a temporal graph.
4. Answer questions using retrievable evidence rather than unsupported model recall.
5. Retain uncertainty, contradictions, corrections, and provenance.
6. Communicate briefly, warmly, and patiently.
7. Operate unattended for long periods and recover from network or process failures.
8. Support progressively richer perception without requiring a client rewrite.
9. Provide proactive socialization: initiate and sustain conversations on topics the patient finds engaging, drawing on the memory graph and family-provided knowledge of the patient's interests and biography.

### Non-goals for the first implementation

- Medical diagnosis.
- Autonomous clinical decision-making.
- Treating an LLM inference as a verified physical event.
- Cloud-rendered avatar video at any fidelity; a photorealistic avatar is a later-phase, locally rendered goal (§15.3), not part of the first implementation.
- Background Android operation with the application routinely hidden.
- A server-language migration roadmap.
- Cost minimization at the expense of model quality.

---

## 3. Core Design Principles

### 3.1 Evidence before facts

Every durable memory must link back to the evidence that produced it. Summaries and graph nodes are derived representations, not substitutes for source observations.

### 3.2 Uncertainty is part of the data

The system stores confidence, competing interpretations, corrections, and model versions. It must be possible to revise the semantic graph without losing the historical evidence or the earlier interpretation.

### 3.3 Events are first-class graph nodes

Calls, visits, conversations, meals, object movements, and medication-related activity are modeled as event nodes. Direct person-to-person relationships may be derived for convenience but are not the sole event representation.

### 3.4 Postgres is the source of truth

Postgres stores immutable or append-oriented observations, transcripts, detections, model outputs, and graph-projection jobs. Neo4j is a semantic projection that can be rebuilt from Postgres.

### 3.5 Multimodal perception is event-driven

Audio may be continuous. Expensive visual interpretation should be triggered by motion, scene changes, person tracks, speech, questions, uncertainty, or periodic activity snapshots—not by sending every camera frame to a vision-language model.

### 3.6 Godot is the Android client stack

The Android client is implemented in Godot and GDScript. Kotlin is not part of the planned implementation. A C++ GDExtension may be added only for a measured performance bottleneck or integration with a native inference or codec library.

### 3.7 Provider quality takes priority over provider cost

Continuous cloud inference is acceptable. Usage is measured to detect accidental duplication, retry storms, and provider anomalies rather than to enforce aggressive cost reduction.

---

## 4. High-Level Architecture

```text
┌──────────────────────────── Android client: Godot ────────────────────────────┐
│                                                                               │
│  Microphone ──► audio capture ──► framed WebSocket stream                     │
│                         │                                                     │
│                         └──── Echo playback exclusion                         │
│                                                                               │
│  Tablet camera ──► motion/keyframe selection ──► visual observations          │
│                                                                               │
│  Avatar ◄── TTS audio + viseme timing                                         │
│  Speaker ◄── TTS audio                                                        │
│                                                                               │
│  Optional pan-tilt controller ◄── local UDP commands                          │
│                                                                               │
│  Local durable spool: unacknowledged audio, observations, and commands        │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                    │ secure WebSocket / HTTPS
                                    ▼
┌──────────────────────────── Python server and workers ────────────────────────┐
│                                                                               │
│  Ingestion ─► ASR ─► diarization ─► speaker identification                    │
│       │                         │                                               │
│       │                         └──────────┐                                    │
│       │                                    ▼                                   │
│       └────► visual analysis ─────► multimodal event fusion                    │
│                                             │                                 │
│                                             ▼                                 │
│                            evidence and event extraction                       │
│                                │                   │                           │
│                                ▼                   ▼                           │
│                    Postgres + pgvector      graph projector                    │
│                                │                   │                           │
│                                │                   ▼                           │
│                                │                 Neo4j                         │
│                                │                   │                           │
│                                └──── hybrid retrieval ────┐                    │
│                                                          ▼                    │
│                                             grounded response generation       │
│                                                          │                    │
│                                                   TTS + visemes                │
└──────────────────────────────────────────────────────────┬────────────────────┘
                                                           │
                                                           ▼
                                                     Godot avatar
```

---

## 5. Technology Decisions

### 5.1 Android client: Godot 4.7.1+ and GDScript

Godot is selected because the client is an always-visible audiovisual application whose central interface is an animated avatar.

Responsibilities:

- microphone capture;
- audio framing and streaming;
- camera access and keyframe selection;
- TTS playback;
- Echo-speech exclusion state;
- 2D avatar rendering and lip sync;
- wake-word interaction;
- WebSocket and local-network communication;
- durable local retransmission spool;
- optional pan-tilt camera control.

Relevant Godot facilities include:

- `AudioStreamMicrophone` with `AudioEffectCapture` for raw microphone frames;
- `WebSocketPeer` for binary and text transport;
- `CameraServer` and `CameraFeed` for Android camera feeds in Godot 4.7.1+;
- `PacketPeerUDP` for local pan-tilt controller commands;
- GDExtension for native C++ integration when necessary.

### Development workflow

Most client functionality — audio capture, transport, spool, avatar, state machines — is platform-independent GDScript and is developed and tested on a Linux development PC, not by continuous tablet deployment. Camera frame acquisition is hidden behind a small interface with two backends: a `CameraFeed` backend for the tablet and a file/replay backend on desktop that serves recorded frames from disk (doubling as input for the evaluation harness). The tablet is required only for validating the `CameraFeed` backend itself and for performance profiling; one-click deploy over adb (including adb over Wi-Fi) keeps that iteration tolerable.

### C++ escalation rule

GDScript remains the default. Add a C++ GDExtension only after profiling demonstrates a specific issue such as:

- excessive GPU-to-CPU camera readback;
- image conversion or encoding overhead;
- audio resampling or codec overhead;
- acoustic echo cancellation;
- local object or face inference;
- native ONNX Runtime integration;
- inability to meet a measured latency, CPU, or memory target.

The C++ extension should expose a small Godot-facing API and remain replaceable. It is an optimization boundary, not a second application architecture.

### 5.2 Server: Python

Python is the production server language for the foreseeable project horizon.

Recommended components:

| Component | Technology |
|---|---|
| API and WebSocket server | FastAPI |
| Data validation and configuration | Pydantic |
| Relational access | SQLAlchemy or SQLModel with explicit migrations |
| Database | Postgres |
| Vector search | pgvector |
| Graph database | Neo4j |
| Background processing | Initially an in-process or simple database-backed worker; add a queue only when required |
| External APIs | Provider adapters over `httpx` or official SDKs |
| Evaluation | Python notebooks and reproducible command-line runners |

External providers must be behind narrow interfaces, but not to prepare for a language port. The purposes are testing, substitution, replay, and controlled experimentation.

Suggested modules:

```text
server/
├── api/                 # REST and WebSocket endpoints
├── transport/           # framing, acknowledgements, resumable sessions
├── audio/               # audio normalization and playback exclusion metadata
├── asr/                 # ASR provider adapters
├── diarization/         # speaker segmentation
├── speakers/            # voice enrollment and identity inference
├── vision/              # visual detection and VLM adapters
├── fusion/              # multimodal event inference
├── memory/              # episodes, consolidation, retrieval
├── graph/               # graph schema and projector
├── llm/                 # extraction and response generation
├── tts/                 # TTS and viseme timing
├── models/              # relational models and schemas
├── workers/             # durable processing jobs
└── evaluation/          # replay, benchmarks, and regression tests
```

---

## 6. Evidence Model

Echo must distinguish at least four semantic levels.

### 6.1 Observation

A direct machine observation:

- audio samples;
- ASR transcript with timestamps;
- speaker segment;
- face or person track;
- object detection;
- camera pose;
- generated Echo utterance;
- device or transport event.

### 6.2 Assertion

A proposition expressed by a speaker.

Example:

```text
At 15:10, speaker cluster S17 said:
"I took my medicine after lunch."
```

This is evidence that the speaker made the assertion. It is not yet proof that medication was taken.

### 6.3 Inference

A model-derived interpretation of one or more observations.

Example:

```text
Candidate event: medication taken
Confidence: 0.64
Evidence: patient assertion + package visible + glass raised
```

### 6.4 Confirmed or externally verified event

An event that has stronger confirmation, such as a family correction, a device signal, or a configured verification rule. Confirmation is still represented with provenance rather than by deleting the prior uncertainty.

### 6.5 Status values

```text
PROPOSED
SUPPORTED
CONFIRMED
DISPUTED
RETRACTED
SUPERSEDED
```

The system must preserve polarity and modality. These utterances must not create the same event:

```text
"I took the medicine."
"I did not take the medicine."
"Did you take the medicine?"
"I will take the medicine later."
"The television said to take the medicine."
```

### 6.6 Family-provided facts and verification

The trusted circle (see §17) is a first-class evidence channel. Facts entered by a trusted family member — prescribed medications, appointments, the biography skeleton, topic approach/avoid marks — are stored with `origin: FAMILY_PROVIDED` and their own provenance (who, when, which channel). They typically enter at `SUPPORTED` or `CONFIRMED` and serve as external ground truth that sensors cannot provide: a family-maintained medication plan, for example, allows "medication taken" candidate events to be cross-checked against an actual prescription schedule.

Confirmation or dispute by a trusted principal is the first concrete rule for promoting candidate events between the statuses in §6.5. Trust actions never modify or delete existing evidence; they append new provenance-bearing records, and the patient's own contradicting assertions remain stored as evidence of the patient's beliefs.

---

## 7. Postgres: Evidence Ledger and Operational Source of Truth

Postgres stores source observations and processing history. Records should be immutable where practical; corrections should append new interpretations or status changes.

Suggested logical tables:

```text
devices
capture_sessions
audio_frames
audio_segments
visual_frames
visual_observations
camera_poses
speaker_segments
speaker_clusters
speaker_candidates
utterances
assertions
candidate_events
event_evidence
entities
entity_mentions
entity_candidates
model_runs
processing_jobs
conversation_turns
embeddings
principals
trust_actions
graph_outbox
graph_projection_checkpoints
```

### Required provenance fields

Most derived records should include:

```text
id
source_observation_ids
captured_at
processed_at
model_provider
model_name
model_version
prompt_or_extractor_version
confidence
status
created_at
supersedes_id
```

### Storage retention

Retention should be configurable by evidence type. The architecture must permit keeping raw audio, selected clips, transcripts, keyframes, and derived events for different durations. Deletion must remove or invalidate all dependent projections.

---

## 8. Neo4j: Autobiographical Event Graph

Neo4j is retained because the graph is a primary memory representation, not merely a query optimization.

### 8.1 Core node types

```text
Person
Place
Object
Medication
Organization
Topic
Routine
Event
ObservationReference
TimeInterval
```

### 8.2 Events are nodes

A telephone call should not exist only as a timestamped `CALLED` edge.

```cypher
(:Event {
  id: $event_id,
  type: "PHONE_CALL",
  occurred_at: $occurred_at,
  occurred_at_precision: $precision, // "minute" | "hour" | "day" | "year" | "decade" — see §8.5
  ended_at: $ended_at,
  confidence: $confidence,
  status: $status,
  origin: $origin // OBSERVED | REPORTED | FAMILY_PROVIDED
})
```

Relationships may include:

```text
(Event)-[:PARTICIPANT {role: "caller"}]->(Person)
(Event)-[:PARTICIPANT {role: "recipient"}]->(Person)
(Event)-[:OCCURRED_AT]->(Place)
(Event)-[:ABOUT]->(Topic)
(Event)-[:INVOLVED]->(Object)
(Event)-[:INSTANCE_OF]->(Routine)
(Event)-[:SUPPORTED_BY]->(ObservationReference)
(Event)-[:CONTRADICTS]->(Event)
(Event)-[:SUPERSEDES]->(Event)
(Event)-[:BEFORE]->(Event)
(Event)-[:AFTER]->(Event)
(Event)-[:CONFIRMED_BY {at: $at, via: $channel}]->(Person)
(Person)-[:ENGAGED_WITH {last_discussed_at: $at, engagement: $score}]->(Topic)
```

### 8.3 Mentions and identity resolution

Do not immediately merge uncertain aliases.

```text
(Mention {text: "Лена"})
  -[:REFERS_TO {confidence: 0.93}]->
(Person {canonical_name: "Елена"})
```

Voice and face identities are also probabilistic references until sufficient evidence exists.

### 8.4 Graph projection

The server must not rely on an unsafe Postgres-then-Neo4j dual write.

Projection sequence:

1. Store observations, candidate events, entities, and a graph-outbox record in one Postgres transaction.
2. A graph projector claims the outbox record.
3. It performs idempotent Neo4j writes using stable IDs and `MERGE`.
4. It records the projection result and checkpoint.
5. Failures are retried safely.
6. Neo4j can be rebuilt entirely from Postgres.

### 8.5 Biographical events and life stories

The patient will discuss events from their entire life. These enter through the assertion path (§6.2): what they say about their past is evidence that they said it. Two timelines are kept distinct — `told_at` (when they said it; precise, observed) and `occurred_at` (when it happened; often fuzzy, reported).

Requirements:

- **Fuzzy and relative time.** Partial dates (year, decade), interval bounds, and `BEFORE`/`AFTER` ordering edges between life events that carry relational truth even when no absolute dates are known ("after the army, before the move").
- **Era anchors.** A family-seeded skeleton biography (birth, places lived, education, service, career, marriage, children, retirement) stored as anchor events and time intervals with `origin: FAMILY_PROVIDED`; incoming reminiscences attach to anchors instead of floating free.
- **Retelling consolidation.** Repeated tellings of the same story merge into one canonical story node: each telling linked as evidence, new details extracted and attached per retelling, contradictions across tellings preserved with provenance and never resolved by deletion. Drift across tellings is clinically significant and is surfaced to the family (admin scope) only, never to the patient.
- **Origin marker.** Every event carries `origin`: `OBSERVED` (sensors), `REPORTED` (the patient's speech), or `FAMILY_PROVIDED` (trusted circle). Retrieval phrasing keys off it ("вы рассказывали..." vs. "я видела..." vs. "Елена передала...").
- **Valence flags.** Stories and topics carry approach/avoid signals inferred from engagement and affect, plus explicit family marks. Family-marked avoidances are hard constraints on proactive topic selection (§15.5).

### 8.6 Neo4j operational guardrails

Single-patient scale (worst case: low millions of nodes over years) is far below Neo4j limits; the risks are schema and operations, not performance.

- Uniqueness constraints on every stable ID projected from Postgres; the §8.4 projector's `MERGE` path must never degrade into scans.
- The patient's `Person` node will accumulate very large numbers of relationships (supernode). Queries lead with an indexed `Event.occurred_at` range rather than traversing outward from the patient's node; add a time-tree layer only if measurements demand it.
- Variable-length traversals in retrieval are capped (2–3 hops) and anchored on indexed properties.
- Community Edition has no online hot backup: schedule regular dumps, and rely on the rebuild-from-Postgres invariant as the primary recovery path.
- Vector search stays in pgvector; do not maintain a second embedding index in Neo4j.

---

## 9. Audio Pipeline

### 9.1 Capture

The Godot client uses an `AudioStreamMicrophone` routed through an `AudioEffectCapture` bus. Application code consumes the ring buffer and creates transport frames.

Each frame or batch should include:

```text
device_id
capture_session_id
stream_epoch
sequence_number
captured_at
codec
sample_rate
channel_count
duration_ms
payload
```

The server acknowledges durable receipt. Unacknowledged frames remain in the local spool and may be retransmitted idempotently.

### 9.2 Sound-gated ASR

The client does not stream silence. A client-side VAD ("wake on sound") gates transmission: a pre-roll buffer keeps utterance onsets intact, and client-side timestamps remain continuous across gated segments so the server still sees one coherent timeline. VAD decisions are logged as observations — "sound present but not ingested" is itself evidence for retention and audit questions.

Cloud ASR runs on the gated segments. Provider session-duration limits must be hidden behind an adapter that rotates sessions while retaining continuous timestamps and limited overlap for boundary recovery.

Usage accounting must detect:

- duplicate active streams;
- retry storms;
- unexpectedly high billed duration;
- silent or malformed capture;
- a device sending from multiple stream epochs simultaneously.

### 9.3 Segmentation

Do not divide memory into arbitrary 5–15-minute blocks. Segmentation should combine:

- voice activity;
- pauses;
- speaker changes;
- topic changes;
- explicit temporal references;
- scene changes;
- a maximum-duration fallback.

Summaries are derived views. Source utterances and observation links remain available.

### 9.4 Diarization

Diarization determines who spoke when without necessarily knowing the person's identity.

```text
Speaker cluster S17: 14:02:01–14:02:08
Speaker cluster S04: 14:02:09–14:02:13
```

Speaker identification then maps a cluster to candidates such as:

```text
PATIENT
KNOWN_FAMILY_MEMBER
UNKNOWN_PERSON
MEDIA
ECHO
UNCERTAIN
```

Each utterance stores both diarization and identification confidence.

Identification evidence may include:

- voice embedding similarity;
- enrolled speaker profiles;
- visible face identity;
- active-mouth correlation;
- self-identification in speech;
- conversational context.

### 9.5 Media exclusion gate

Audio identified as media (television, radio) is excluded from memory ingestion by default: most of it is irrelevant to the patient's life, and ingesting it would pollute transcripts, speaker clusters, and extracted events. A media/household gate therefore runs before ASR and diarization commit utterances to the evidence ledger.

Two qualifications:

- The gate must survive overlap: television playing while the patient talks to a visitor is the normal case, not an edge case. ASR and diarization are still evaluated with TV in the background (§19), and household speech during media playback must not be discarded — the media false-negative rate matters as much as the false-positive rate.
- The patient can explicitly ask Echo to remember something from media ("Эхо, запиши это"). This depends on intent-of-address detection (§15.4) and is stored as a media-derived observation with its own provenance.

### 9.6 Echo-speech exclusion

Echo's generated turn must be stored directly as a generated conversation utterance. It must not be learned again through the microphone.

Initial implementation: half-duplex memory ingestion.

```text
1. Server sends generated text, TTS audio, and playback ID.
2. Client emits `playback_started`.
3. Microphone frames are suppressed or marked non-ingestible for memory.
4. Client plays the TTS audio.
5. Client emits `playback_ended`.
6. After a short acoustic tail interval, normal ingestion resumes.
```

Failure paths are part of the design, not an afterthought: the suppression window is server-authoritative and bounded by the known playback duration plus a bounded tail; if `playback_ended` is lost or the client crashes, ingestion resumes at window expiry rather than staying suppressed indefinitely or leaking Echo's voice; on reconnect, client and server re-sync suppression state idempotently. Concrete timeout values are set during Phase 1b soak testing.

Generated Echo turns remain in conversation history so that references such as "she" or "that call" can be resolved in subsequent patient speech.

Later, barge-in may be supported through acoustic echo cancellation and comparison against the known playback waveform.

---

## 10. Vision Pipeline

### 10.1 Camera roles

### Fixed tablet camera

Primary purposes:

- patient-facing interaction;
- face and person tracking;
- active-speaker evidence;
- direct visual context for questions;
- continuous stable reference view.

### Optional independent pan-tilt camera

Primary purposes:

- following a person leaving the fixed view;
- observing a doorway, table, or room zone;
- obtaining a better face or object angle;
- searching for a named object;
- resolving uncertain visual events.

The tablet itself should remain stationary. Rotating the tablet would turn the avatar away from the patient and complicate charging and interaction.

### 10.2 Godot camera access

Godot 4.7.1+ exposes Android cameras through `CameraServer` and `CameraFeed`. The client may display the feed directly and extract selected frames for transmission.

GPU-to-CPU texture readback must not occur every rendered frame. `Texture2D.get_image()` creates a CPU-side copy and may be expensive. The first implementation should use a low selected-frame rate and profile on the target tablet. If this path is inadequate, implement efficient frame access or encoding through a C++ GDExtension.

### 10.3 Local lightweight selection

The client should perform inexpensive selection before cloud vision analysis:

- motion score;
- scene-change score;
- periodic snapshot during activity;
- camera-settled state;
- server-requested observation;
- optional lightweight local person or face detection if performance permits.

Cloud visual analysis is triggered by selected frames or short bursts rather than every camera frame.

### 10.4 Visual observation schema

```text
observation_id
camera_id
captured_at
frame_id
track_id
observation_type
candidate_entity_id
bounding_box
confidence
model_id
model_version
pan_deg
tilt_deg
pose_confidence
movement_state
room_zone
calibration_version
```

A vision model should produce bounded observations such as:

```text
"A medication package is visible in the patient's hand."
"A glass is raised toward the mouth."
"A person matching Elena entered the doorway."
```

It should not silently convert incomplete visual cues into verified actions.

---

## 11. Arduino-Controlled Pan-Tilt Camera

### 11.1 Hardware role

An Arduino-compatible Wi-Fi microcontroller controls pan and tilt motors. It is a deterministic actuator and pose reporter, not the main vision-inference computer.

An ESP32-based Arduino-compatible board is preferred for compact size and integrated networking.

Recommended prototype hardware:

- independent camera module or small network camera;
- pan-tilt bracket;
- two positional servos;
- Arduino-compatible Wi-Fi controller;
- separate regulated servo power supply;
- common electrical ground;
- optional limit switches, encoders, or feedback-capable servos.

Do not use continuous-rotation hobby servos when absolute camera orientation is required. Start with positional servos; move to feedback servos or steppers with homing when pose accuracy becomes important.

### 11.2 Communication

Preferred local control path:

```text
Python server
    │ target or scan request over existing secure connection
    ▼
Godot client
    │ local UDP command
    ▼
Pan-tilt controller
```

The Godot client remains authoritative for local device commands and reports actuator state to the server.

Example commands:

```text
LOOK_AT command_id=481 pan=35 tilt=-10
HOME command_id=482
SWEEP command_id=483 from=-70 to=70 step=20
STOP command_id=484
STATUS command_id=485
```

Example response:

```json
{
  "command_id": 481,
  "status": "settled",
  "pan_deg": 34.8,
  "tilt_deg": -10.2,
  "pose_confidence": 0.92
}
```

Commands require IDs, acknowledgements, timeouts, bounded retries, and a fail-safe stop.

### 11.3 Active-perception state machine

The camera should not sweep continuously.

```text
HOME
  Stable view of the primary room zone.

TRIGGERED
  A person, sound, question, edge motion, or uncertain event requests another view.

MOVING
  Camera rotates. Frames are not accepted as stable evidence.

SETTLING
  Wait for motor vibration and autofocus to stabilize.

OBSERVING
  Capture one or more keyframes or a short burst.

TRACKING
  Follow a selected person or object within bounded movement and time limits.

RETURNING
  Return to the home pose unless another request is pending.
```

Possible triggers:

- unknown speaker detected;
- a known face leaves the fixed view;
- motion appears near the image boundary;
- the patient asks where an object is;
- face or object confidence is low;
- a door-opening sound is detected;
- a periodic scan is requested while activity is present.

### 11.4 Spatial calibration

Camera orientation should map to semantic room zones where possible:

```text
pan -55° to -25°  -> doorway
pan -20° to  15°  -> patient chair
pan  20° to  55°  -> dining table
```

Every visual observation must store camera pose, calibration version, and movement state. Spatial claims should rely on calibrated pose plus visual evidence, not only on an LLM's image description.

---

## 12. Multimodal Event Fusion

The fusion layer combines temporally aligned evidence without erasing modality-specific uncertainty.

Example evidence:

```text
14:31:02  Person track enters doorway.
14:31:03  Face candidate Elena, confidence 0.89.
14:31:05  New audio speaker cluster begins.
14:31:06  Visible mouth activity aligns with speech.
14:31:08  Transcript: "Hello, Mum."
```

Candidate graph event:

```text
type: VISIT_STARTED
person: Elena
occurred_at: 14:31:02
confidence: 0.95
status: SUPPORTED
```

The event links to all supporting observations. If the face match is later corrected, the event may be superseded without deleting the original audio and visual records.

Fusion should consider:

- temporal overlap;
- spatial compatibility;
- speaker and face identity confidence;
- active-mouth evidence;
- object continuity across frames;
- prior entity aliases;
- explicit speech content;
- contradictions and negative evidence.

The initial implementation can use deterministic rules plus LLM extraction. More sophisticated probabilistic fusion is deferred until real data identifies where it is useful.

---

## 13. Memory Pipeline

### 13.1 Raw observation layer

Stores timestamped audio, transcripts, speaker segments, images, detections, generated Echo turns, and device events.

### 13.2 Utterance and assertion layer

Creates speaker-attributed utterances and extracts explicit assertions while preserving polarity, tense, and modality.

### 13.3 Candidate-event layer

Combines assertions and visual observations into event candidates with confidence and evidence links.

### 13.4 Entity-resolution layer

Resolves mentions to people, places, objects, medications, and routines. Uncertain matches remain candidate links rather than destructive merges.

### 13.5 Episodic layer

Groups related utterances and observations using speaker, activity, topic, and temporal boundaries. Generates human-readable summaries and embeddings without replacing the underlying evidence.

### 13.6 Graph-projection layer

Projects stable IDs, events, entities, and relationships into Neo4j through the Postgres outbox.

### 13.7 Consolidation layer

Builds daily digests, recurring routines, canonical life stories (merging repeated tellings; see §8.5), and higher-level patterns. Consolidation produces new derived records and graph structures; it does not discard contradictory source history.

Consolidated artifacts are human-readable, versioned records stored in Postgres and rendered as text the family can review: digests, learned routines, "topics that engage the patient," "what calms the patient." The family can correct or reject them through the trusted-circle channel (§17); corrections are appended with provenance, never overwritten. The pattern worth copying from personal-agent systems (e.g., Hermes Agent's inspectable, approvable learned artifacts) is the curation UX, not the file storage.

---

## 14. Retrieval and Answer Generation

Retrieval is hybrid.

1. Parse the question for people, objects, places, temporal constraints, and intent.
2. Apply structured Postgres filters for time, speaker, entity, and event type.
3. Search utterances and summaries using lexical and vector retrieval.
4. Traverse Neo4j for relationships, event sequences, routines, and multi-hop context.
5. Rerank evidence by relevance, confidence, source quality, and temporal fit.
6. Assemble an evidence bundle with IDs, timestamps, and uncertainty.
7. Generate a concise answer using only the evidence bundle and conversation context.
8. State uncertainty or lack of evidence when appropriate.

Recency is not always the dominant ranking criterion. It should depend on the query. "When did Elena last call?" requires strict temporal ordering; "What did Elena say about university?" may require older semantically relevant evidence.

Retrieval has two modes. "What happened" answers retrospective questions as above. "What to talk about" serves proactive socialization (§15.5): least-recently-discussed high-engagement topics, upcoming events and anniversaries from the graph, era anchors and favorite stories from the biographical layer — always filtered through valence approach/avoid constraints before anything reaches the patient.

Answers should distinguish source types where useful:

```text
"Elena said this morning that she would visit tomorrow."
"The camera saw someone who was probably Elena, but the identification is uncertain."
"I heard you discuss the medicine, but I do not have enough evidence that it was taken."
```

---

## 15. Conversation, Persona, and Avatar

### 15.1 Persona

Echo has exactly one patient-facing persona: a stable, predictable identity that never changes. Multiple characters would be a confusion engine for this user; consistency itself is the therapeutic value.

The baseline persona — validated against alternatives during the Phase 0 probe — is a devoted personal secretary: warm, mature female voice; respectful Russian «вы» register; unhurried speech. The frame preserves the patient's status (the boss whose affairs deserve tracking, not a patient being monitored) and makes the system's capabilities legible in character: the secretary keeps notes (observations), remembers what people told her (assertions), and checks her records before answering. Alternatives tested in the probe: a peer/old-friend register, and a plain warm companion with no role frame. The family shortlists candidates; the patient's reactions choose; the result is frozen as versioned configuration. Voice, name, and role-frame specifics are validated with the actual patient in the probe before freezing.

Rules:

- **Minimal backstory.** She is a role, not a fictional biography. Invented facts become consistency liabilities over months of conversation; texture comes only from what the patient actually tells her, which becomes real memory.
- **Name.** Short, easy in both Russian and English, and never colliding with a real family member's name. Optionally the patient names her; once chosen, the name is frozen.
- **Registers, not personas.** One identity with several tempos: briefing (morning summary), conversation, calming (slower, shorter, validating — for agitation and sundowning), and quiet (minimal speech).
- **No voice cloning of real people** and no avatar resembling a real relative, except by explicit, informed family decision.

### 15.2 Behavioral invariants

1. **Never quiz.** State, don't test: "Елена звонила вчера," never «А помните, кто звонил вчера?». Open reminiscence invitations («Расскажите ещё раз, как вы...») have no wrong answer and are encouraged; memory tests are cruelty.
2. **The fortieth answer is as warm as the first.** Repeated questions are the norm, not the exception. Any detectable impatience is a persona-critical defect and a harness metric (§19).
3. **Warmth unlimited about feelings; diplomacy about facts.** Confabulations are never confirmed and never argued with: "В моих записях немного по-другому... расскажите мне лучше про..." — validate the emotion, redirect, move on. The confabulation-agreement rate is measured (§19).
4. **Confidence lives in the data, not the voice.** Evidence levels modulate phrasing and selection — plain statements when evidence is solid, natural softening when it is not, low-confidence inferences simply not volunteered. She distinguishes what she observed, what somebody said, and what she inferred — in register, not jargon. Never statistical language; never invented facts.
5. **Orient naturally.** Use time and recent context to ground the patient without lecturing or testing.
6. **Brief by default.** One or two sentences per turn unless the patient is engaged and asking for more.
7. **Admiration is specific.** Grounded in the patient's real biography from family seeding and the graph — never generic flattery.
8. **Encourage real contact.** Echo points toward people ("Елена обещала приехать завтра — с нетерпением ждём") rather than substituting for them.

The family owns the honesty policy — what Echo says if asked directly whether she is real, how far the therapeutic fiction goes — as explicit configuration, not ad-hoc prompt text.

### 15.3 Avatar

The avatar roadmap is staged: deliberately simple in the early phases, photorealistic at the end state.

Early phases:

- The Phase 0 probe uses a placeholder avatar — just enough to test engagement.
- The Phase 2 avatar is an on-device 2D talking head rendered by Godot: simple warm stylized design, blinking and restrained idle motion, viseme-based mouth shapes driven by TTS timing, expression states such as listening, thinking, speaking, and uncertain.

End state: a photorealistic, locally rendered 3D avatar — optionally a full-body figure rather than a head only. Since Unreal Engine 5.6 (2025), the MetaHuman license permits using MetaHuman characters and animations in other engines, including Godot, royalty-free. The intended path is therefore MetaHuman-class assets exported (FBX/USD) into the existing Godot client and driven by the same TTS viseme timing — no client-stack migration and no cloud-rendered video.

Durable constraints at any fidelity:

- no cloud-generated talking-head video in the primary loop (latency per §15.6, privacy);
- rendering is local, on the device;
- the avatar never resembles a real relative (§15.1), except by explicit, informed family decision;
- adoption of the photorealistic avatar is gated on tablet GPU/thermal measurements and on probe/pilot evidence that the patient responds well to it — the uncanny-valley and misidentification risks do not expire with phases, because the patient cannot reason "this is just an animation."

### 15.4 Intent of address and permission to speak

An always-on companion must solve two gating problems before any utterance:

- **Was the patient speaking to Echo?** A hard wake word is rejected: the target user may not reliably produce one, especially under stress or sundowning. The gate is a high-recall named-address detector ("Эхо, ...") plus push-to-talk as an explicit fallback, with recall favored over precision — a false trigger costs a harmless "Да, я слушаю," a missed trigger costs the relationship.
- **May Echo speak now?** Proactive speech requires permission from context: current activity, time of day, who else is present, recent engagement, and affect state. Wrong-time speech is worse than silence. The policy is conservative at launch and loosens only from measured engagement.

### 15.5 Proactive socialization

Echo initiates conversation, not only answers. Topic selection uses the "what to talk about" retrieval mode (§14): high-engagement topics not discussed recently, upcoming events and anniversaries, era anchors and favorite stories from the biographical layer, family-seeded interests. Hard constraints: family-marked avoid topics, inferred valence avoid signals, time-of-day and affect appropriateness, strict rate limits. Reminiscence invitations double as data acquisition — each retelling enriches the canonical story nodes (§8.5).

Repetition works differently for this user: the patient may not remember yesterday's conversation, which makes topic reuse forgiving — but engagement is measured per topic rather than assumed, and the patient must never feel tested.

Prompt, persona, and policy behavior require iterative evaluation with the target patient and remain versioned configuration; versions are recorded on every derived record.

### 15.6 Interactive-loop latency budget

Latency is part of the persona contract. For this user a 2–3 s pause reads as a normal conversational beat — the persona is explicitly unhurried — but past ~5 s she may repeat the question or conclude she was not heard. The budget is defined on the interactive question-answer loop and measured from the end of the patient's speech to the start of TTS playback:

- first audio within 2 s at p50 and within 4 s at p95;
- an in-persona acknowledgment («Сейчас посмотрю…») may precede the answer; it starts within 0.5 s of end-of-speech, keeping perceived latency under 1 s even when the full answer takes 2–3 s;
- a strictly sequential pipeline (batch ASR, full-answer generation, non-streaming TTS) is expected to take 5–10 s and is acceptable only as Phase 0 probe scaffolding, never for the Phase 2 companion.

Meeting the budget requires pipelining, not faster individual stages:

- **Streaming ASR with partial transcripts.** The §9.2 continuous gated stream means the transcript largely exists by end-of-speech; ASR contributes only finalization (~0.3 s), not full processing time.
- **Speculative retrieval on partials.** §14 retrieval starts on partial transcripts before the question ends; by end-of-speech the evidence bundle is normally ready and retrieval is off the critical path. Any LLM-based reranking (§21.15) must stay off this path.
- **Sentence-streamed generation.** The LLM token stream is cut at sentence boundaries and fed to streaming TTS; the critical path is LLM time-to-first-token plus TTS time-to-first-byte, not full-answer generation.
- **Answer caching.** Repeated questions are the norm (§15.2). Answers are cached keyed by question intent and evidence version, invalidated when new relevant evidence arrives; a cache hit starts playback in under 0.5 s. Caching also serves §15.2 repetition warmth: the fortieth answer is instant, never degraded.
- **Pre-rendered acknowledgment clips.** A small set of persona-consistent fillers is stored on the device and played at endpointing; no TTS latency on that path.
- **Persistent provider connections.** ASR, LLM, and TTS connections are long-lived; per-call handshake time never appears in the loop.
- **Adaptive endpointing.** The end-of-speech wait is tuned to the patient's pause pattern; catching true endings takes priority over shaving the wait.

LLM placement — cloud fast-tier versus a local model on one GPU — stays a provider-adapter decision (§5.2), settled by probe measurements rather than fixed here. Local execution mainly buys p95 stability and privacy (patient transcripts stay in the house) at a modest p50 gain; self-hosting very large models is not cost-effective on this critical path. Russian register quality of any candidate is validated in the Phase 0 probe before adoption.

Every interactive turn records per-stage timings (endpointing, ASR finalization, retrieval, LLM first token, TTS first byte, playback start); the budget is enforced from these measurements (§19), not assumed.

---

## 16. Transport and Reliability

A single uninterrupted connection must not be assumed.

### WebSocket protocol requirements

- binary audio frames;
- text or compact structured control messages;
- stream epochs and sequence numbers;
- durable receipt acknowledgements;
- heartbeat and liveness detection;
- bounded buffers and backpressure;
- resumable offsets;
- idempotent retransmission;
- explicit playback-started and playback-ended messages;
- camera-command and camera-state messages;
- provider session rotation hidden from the client.

### Client recovery

The Godot client should:

- reconnect with bounded exponential backoff;
- persist unacknowledged observations locally;
- resume after server restart;
- rotate local files safely;
- detect microphone or camera failure;
- expose a simple family-facing status screen;
- start in a dedicated foreground or kiosk-like configuration where practical.

### Server recovery

The server should:

- make processing jobs idempotent;
- retain provider request IDs where available;
- avoid duplicating graph events after retries;
- monitor queue age, ASR gaps, dropped frames, graph-projection lag, and storage growth;
- preserve enough audit metadata to reproduce an extraction decision.

---

## 17. Privacy Boundary and Trusted Circle

Echo is responsible for protecting data within its own boundaries, including:

- transport between the client and Echo server;
- access control;
- server storage;
- logs;
- backups;
- tenant or household isolation if multi-user support is added;
- deletion and retention behavior.

The family or operator chooses external ASR, LLM, vision, embedding, and TTS providers and accepts the provider-side privacy implications of those choices. Echo should make provider routing and transmitted data categories visible and configurable rather than claiming responsibility for third-party processing policies.

### 17.1 Trusted circle

A small set of identified people (family, caregivers) interacts with Echo on the patient's behalf: providing facts, confirming or disputing candidate events, seeding biography and interests, reviewing consolidated artifacts, and querying memory within scope.

A **principal** is an identified trusted person linked to their `Person` entity in the graph, an enrolled voice profile, and remote-channel identities. Roles are deliberately flat:

- **Admin** (one or two people): everything — trust management, persona and honesty-policy configuration, retention and deletion, provider choices, full query access.
- **Contributor**: provide facts, confirm or dispute events, mark topic approach/avoid, review consolidations, query within scope.
- **Known person** (any identified non-circle speaker): no authority; their speech is ordinary evidence.

The patient's assertions are never overridden in storage — they remain evidence of what the patient believes — but family-provided facts take precedence in answer generation when they conflict, handled diplomatically (§15.2).

### 17.2 Channels

The primary trusted-circle channel is **text chat** (e.g., a Telegram bot), not audio: account-bound identity is strong, asynchronous messages respect scarce family attention, every action is self-documenting, and members can send rich evidence — a photo of a prescription becomes a provenance-bearing observation. In-person voice remains available, but speaker identification is probabilistic (§9.4), so trust-sensitive actions taken by voice carry reduced authority or require remote confirmation.

Echo may actively request verification from the circle ("Елена, подтвердите: ...") under strict rate limits — family attention is the scarcest resource in the system.

Every trust action — confirmation, dispute, seeding edit, correction — is recorded with provenance (who, when, which channel, what changed) and appends rather than modifies (§6.6).

### 17.3 Scoped access and dignity

Access is scoped per member with conservative defaults: not every contributor may ask "what did the patient say about me?"; sensitive derived data (confabulation drift, affect patterns) defaults to admin-only; visitor speech inside transcripts is access-controlled, and its visibility is an explicit, visible family policy choice.

---

## 18. Deployment and Operating Cost

### Initial deployment

- one Android tablet or phone;
- one Python server;
- Postgres with pgvector;
- Neo4j;
- cloud ASR, LLM, vision, and TTS;
- optional object storage for raw media and backups;
- optional Arduino-controlled pan-tilt camera.

The architecture accepts continuous cloud ASR and potentially several hundred US dollars per month for one patient. Cost estimates must be based on measured provider usage rather than a fixed low estimate.

This cost stance is prototype-scoped: it exists to buy evidence quality while the design is being validated, not as a permanent budget. Sound-gated ASR (§9.2) already removes the largest driver — billing for silence. Later phases revisit the budget with real measurements; per-patient cost must eventually fall well below the prototype range for the system to be deployable at any scale.

Track at least:

- billed ASR audio hours;
- LLM input and output tokens by task;
- visual frames and image tokens submitted;
- TTS characters or seconds;
- duplicated or retried provider calls;
- storage growth by evidence type.

Cost monitoring is primarily an operational-correctness mechanism. A bug opening duplicate ASR streams must be detected even when normal monthly cost is acceptable.

---

## 19. Evaluation Strategy

Before relying on live operation, build an offline replay harness that can process recorded household sessions repeatedly through different pipelines.

### Audio metrics

- word error rate for Russian, English, and code-switching;
- diarization error rate;
- patient-versus-other speaker classification;
- media false-positive rate (media ingested as household speech);
- media false-negative rate (household speech discarded as media);
- Echo-playback leakage rate;
- timestamp continuity across ASR session rotation.

### Extraction metrics

- event precision and recall;
- negation errors;
- future-versus-past tense errors;
- person and alias resolution;
- false medication or visit events;
- contradiction and correction handling.

### Vision metrics

- person and face track stability;
- face-identification precision with abstention;
- active-speaker correlation;
- object continuity;
- motion-trigger usefulness;
- visual event precision;
- camera-pose accuracy and settled-frame quality.

### Retrieval metrics

- recall of relevant source evidence;
- temporal-query correctness;
- graph traversal correctness;
- unsupported-answer rate;
- answer usefulness judged by the family and target patient.

### Interaction and persona metrics

- engagement: conversation length, patient-initiated follow-ups, abandonment rate;
- intent-of-address quality: false-trigger and missed-trigger rates;
- persona consistency: character breaks, register appropriateness;
- repetition warmth: no detectable impatience across repeated questions;
- confabulation-agreement rate;
- reminiscence-invitation acceptance rate;
- interactive-loop latency: end-of-speech to first-audio p50 and p95 against the §15.6 budget;
- per-stage latency breakdown recorded per interactive turn;
- answer cache-hit rate for repeated questions.

### Biographical-extraction metrics

- fuzzy and relative time parsing correctness (partial dates, BEFORE/AFTER ordering);
- retelling-merge precision and recall (same story linked, distinct stories kept apart);
- new-detail attachment across retellings;
- contradiction preservation and drift reporting;
- era-anchor attachment accuracy.

Every model, prompt, or persona change should be replayable against a fixed evaluation set.

---

## 20. Phased Roadmap

## Phase 0: Probe, spikes, and evaluation harness

- Patient interaction probe: minimal avatar, named-address or push-to-talk trigger, LLM over hand-curated memory; test 2–3 persona candidates; measure engagement (§15.1) and per-stage provider latency against the §15.6 budget.
- Godot camera spike on the target tablet: measure achievable frame-extraction rate and latency; decide GDScript vs. C++ GDExtension for the readback path.
- Godot audio streaming spike on the Linux dev PC: VAD gating with pre-roll, framed WebSocket transport (§9.1, §9.2).
- Collect representative consented household audio, including TV/radio overlap and code-switching.
- Build replayable ASR, diarization, media-gate, extraction, and retrieval experiments.
- Establish baseline metrics and provider costs.
- Define initial Postgres schemas (including `principals`, `trust_actions`, and the `origin` marker) and event ontology.

**Goal:** determine whether the patient engages with the persona, and whether the audio evidence is sufficient to create useful memories. Both are go/no-go.

## Phase 1: Evidence-preserving audio memory

Split into two stages so the memory loop is validated before live transport exists.

**Phase 1a (offline pipeline):**

- File-based ingestion of recorded sessions into the Postgres evidence ledger.
- Sound-gated, media-filtered ASR; diarization and conservative speaker identification with abstention.
- Utterance, assertion, and candidate-event extraction preserving polarity, tense, and modality.
- Entity resolution with candidate links; no destructive merges.
- Biographical layer: fuzzy/relative time, era anchors, family-seeded skeleton biography, retelling consolidation, valence flags (§8.5).
- Neo4j event graph through the outbox projector; rebuild-from-Postgres verified.
- Hybrid retrieval and evidence-bundle generation; CLI Q&A over recordings.
- Trusted-principal verification channel (manual entry at this stage) with the §6.6 promotion rule.

**Phase 1b (live client):**

- Godot microphone capture, VAD gating, and resumable streaming with durable spool.
- Long-running connection recovery; idempotent retransmission.
- Echo-speech exclusion with failure handling (§9.6).
- Minimal family-facing status screen.

**Goal:** answer retrospective questions from recorded and then live household speech with traceable evidence.

## Phase 2: Interactive companion

- Frozen persona configuration from the Phase 0 probe, with registers (§15.1, §15.2).
- Intent-of-address detection (high-recall named-address plus push-to-talk) and the permission-to-speak policy (§15.4).
- Grounded response generation with confidence-to-phrasing rules (§15.2).
- Proactive socialization loop under valence and rate constraints (§15.5).
- TTS and viseme timing; 2D Godot avatar.
- Interactive-loop pipelining per §15.6: streaming ASR partials, speculative retrieval, sentence-streamed LLM→TTS, answer caching, pre-rendered acknowledgment clips.
- Trusted circle v1: chat channel for seeding, verification queue, and corrections; Admin/Contributor roles; scoped access (§17).
- Echo's own turns stored as generated utterances for reference resolution.

**Goal:** validate whether the patient finds the interaction understandable, useful, and socially valuable over a multi-week pilot.

## Phase 3: Fixed-camera multimodal memory

- Godot camera capture on the target Android device.
- Activity and keyframe selection.
- Cloud vision analysis.
- Face and person tracks.
- Audio-visual speaker association.
- Multimodal event fusion and provenance.

**Goal:** improve identity, event, and object-memory accuracy beyond audio alone.

## Phase 4: Active pan-tilt perception

Explicitly deferred: nothing in earlier phases depends on this capability, and the visual-observation schema (§10.4) already carries the pose fields it will need.

- Independent rotating room camera.
- Arduino-compatible Wi-Fi controller.
- Godot UDP control and state reporting.
- Camera calibration and room-zone mapping.
- Event-driven active-perception state machine.
- Object search and uncertain-event follow-up views.
- Smart-home sensor ingestion (thermometer and similar household sensors) as a new device class in the evidence ledger: timestamped, provenance-bearing indoor-context observations via an MQTT/Home Assistant bridge or direct integration. These supply the indoor context that open question 19 identifies as stronger than outdoor weather (e.g., room temperature when the patient says «мне холодно»).

**Goal:** allow Echo to deliberately acquire better evidence outside the tablet camera's fixed view.

## Phase 5: Reliability and broader deployment

- family administration tools, including the "what Echo learned" timeline over consolidated artifacts, confirmations, and corrections;
- configurable retention and deletion;
- stronger monitoring and backup restoration tests;
- multiple devices or cameras;
- optional multi-household isolation;
- measured performance optimization, including C++ GDExtensions only where necessary.

**Goal:** make the system dependable without changing its evidence model.

---

## 21. Open Questions

1. Which cloud ASR performs best on the patient's Russian, English, and code-switched speech?
2. Which diarization pipeline remains reliable with television audio and overlapping speakers?
3. How should speaker voice enrollment be presented and maintained?
4. Which event ontology is useful without becoming excessively complex?
5. What raw-audio and image retention periods provide enough evidence for correction?
6. How often should visual snapshots be selected during ordinary activity?
7. Which fixed-camera placement gives the best patient and room coverage?
8. Which pan-tilt mechanism provides sufficiently accurate pose feedback without excessive noise?
9. What rules should trigger active camera movement without making the system distracting?
10. What evidence threshold should promote a candidate event from `PROPOSED` to `SUPPORTED` or `CONFIRMED`?
11. Which retrieval blend works best for temporal, relational, and semantic questions?
12. Which avatar style and voice are most comfortable for the target patient?
13. Which named-address detection approach achieves high recall on this patient's speech without constant false triggers? (§15.4)
14. How are confidence values from different providers made comparable during fusion — per-provider calibration, or ordinal/rank-based fusion? Default until answered: fuse ordinal/rank evidence.
15. What mechanism reranks the evidence bundle (§14) — heuristics, cross-encoder, or learned ranker? Heuristics first; decide before Phase 1a retrieval ships.
16. What affect-detection signals are reliable enough to drive the calming register and proactive-speech gating? (§15.1, §15.4)
17. Which media/household separation approach meets the precision and recall targets on real household audio, including overlap? (§9.5)
18. What authority should in-person voice actions from trusted-circle members carry, given probabilistic speaker identification? (§17.2)
19. How should valence (approach/avoid) signals be validated, and when must family marks override inference? (§8.5, §15.5)
20. What per-stage latency do the chosen ASR, LLM, and TTS providers achieve on the patient's Russian, and does the pipelined loop meet the §15.6 budget? Measured in the Phase 0 probe; re-checked in the Phase 2 pilot.

---

## 22. Technical References

- [Godot CameraServer](https://docs.godotengine.org/en/stable/classes/class_cameraserver.html)
- [Godot CameraFeed](https://docs.godotengine.org/en/stable/classes/class_camerafeed.html)
- [Godot AudioStreamMicrophone](https://docs.godotengine.org/en/stable/classes/class_audiostreammicrophone.html)
- [Godot AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html)
- [Godot WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html)
- [Godot PacketPeerUDP](https://docs.godotengine.org/en/stable/classes/class_packetpeerudp.html)
- [Godot GDExtension](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/)
- [Neo4j data modeling documentation](https://neo4j.com/docs/getting-started/data-modeling/)
- [PostgreSQL recursive queries](https://www.postgresql.org/docs/current/queries-with.html)
