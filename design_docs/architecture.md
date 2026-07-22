# Echo Companion

## Overview

An always-on AI companion ("Echo") for an elderly person with dementia, including Alzheimer's Disease (AD). The companion listens continuously, memorizes everything happening in the environment, and answers questions about past events. It communicates in Russian and English with a warm, patient demeanor tuned for dementia patients. A lip-synced avatar provides a human presence.

## Target User

- Elderly person with dementia (including Alzheimer's Disease)
- Primary languages: Russian and English
- Runs on an Android tablet or phone
- 24/7 always-on operation (plugged in, foreground)

---

## Technology Decisions

### Client: Godot / GDScript

**Chosen over:** Flutter, VueJS (PWA), GioUI

Godot is a game engine, and the client's centerpiece is an avatar that will grow in realism over time. Key reasons:

- **Avatar-first.** 2D/3D rendering, blendshapes, visemes, skeletal animation, and lip-sync are native. If the avatar evolves from 2D talking-head to 3D character (MetaHuman-style), Godot is already the right tool. Flutter/Vue/Gio would force a rewrite at that point.
- **Real-time audio is first-class.** `AudioStreamRecord` for continuous mic capture, `WebSocketPeer` for streaming to server. Purpose-built for media loops.
- **Always-on foreground is the natural model.** Runs as a full-screen Android activity. Android's aggressive background-process killing is avoided.
- **Lightweight, free, no licensing.** Clean APK export to Android.
- **Future video (v2).** Camera access and frame processing are straightforward.

GDScript is quick to pick up; C# or GDExtension (C++) available for performance-critical paths.

### Server (MVP): Python + Postgres + Neo4j

**Chosen over:** Go for MVP, all-Go, Mojo

#### Why Python for MVP

The MVP's job is to answer one question: **does this actually help the patient?** That is a product question, not an engineering question. The uncertainty lives in:

1. **Dementia-aware conversation behavior.** The system prompt and grounding logic will iterate dozens of times based on real interaction with patients. Dynamic language = fast iteration loop.
2. **Memory pipeline quality.** Episodic summarization cadence, retrieval strategy, consolidation rules are all empirical unknowns. Python enables REPL prototyping and rapid experimentation.
3. **Model selection.** ASR model size, embedding model, TTS voice are all unresolved. Python + HuggingFace is hours per experiment vs days with ONNX export.

The eventual port to Go is mechanical, not novel, **provided** the Python is written with clean interfaces (see Architecture Discipline below).

#### Stack

| Component | Technology |
|---|---|
| Web framework | FastAPI (WebSocket + REST) |
| Database (relational + vector) | Postgres + pgvector |
| Knowledge graph | Neo4j |
| ASR | faster-whisper (local) or Yandex SpeechKit (cloud) |
| LLM | Claude / GPT-4o via API (multilingual: Russian + English) |
| TTS | ElevenLabs, Yandex SpeechKit, or Silero (local) |
| Embeddings | sentence-transformers (multilingual, Russian + English) |
| HTTP client | httpx |
| Validation/config | Pydantic |

#### Postgres + pgvector

Stores: raw timestamped transcripts, episodic summaries, daily digests, entities, session metadata. pgvector provides vector similarity search in the same transaction as structured queries. No separate vector DB needed at this scale.

#### Neo4j (Knowledge Graph)

Stores the **memory graph**: people, places, routines, medications, recurring events, and their relationships. This complements pgvector (semantic similarity) with structured relational reasoning:

- "Who visited this week?" → traverse `VISITED` edges
- "When did Elena last call?" → `CALLED` relationship with timestamps
- "What medications were discussed?" → `MENTIONED` edges filtered by entity type
- Entity resolution: "Лена" and "Елена" are the same person (`SAME_AS`)

The graph is populated by the memory pipeline as it extracts entities and relationships from episodic summaries. Queries combine vector retrieval (pgvector, for "what was said about X") with graph traversal (Neo4j, for "how does X relate to Y").

### Server (Stage 2): Go + C++

When SaaS demand is real (multiple users, cost pressure, scaling needs), the production server ports to Go with C++ for ML inference.

**Chosen because:**

- **Single static binary deployment.** No virtualenvs, no dependency drift. Reliability win for 24/7 unattended operation.
- **WebSocket + streaming concurrency.** Goroutines handle hundreds of always-on audio streams per instance with predictable memory and latency.
- **Lower memory footprint.** Go + whisper.cpp + ONNX Runtime is tens of MB baseline vs Python + PyTorch at 2-4GB. Direct cost savings at scale.
- **The logic layer is CRUD + glue.** Memory pipeline (scheduling, retrieval, DB, LLM API calls, consolidation) is business logic. Go's strong typing and tooling express this well.

#### Stack

| Component | Technology |
|---|---|
| Language | Go |
| ASR | whisper.cpp (CGo binding or gRPC sidecar) |
| Embeddings | ONNX Runtime (Go bindings) |
| LLM / TTS | net/http (API calls, same as Python) |
| DB driver | pgx (Postgres) |
| Neo4j driver | neo4j-go-driver |
| Deployment | Single static binary, Docker |

**Key principle: Python as workshop, Go as factory.** Model experimentation, evaluation, and ONNX export happen in Python on the developer machine. The Go binary ships only stable ONNX artifacts to production. The ONNX model is the clean handoff boundary.

### What we ruled out and why

**Mojo** — promising long-term (Python syntax, C/CUDA speed), but the ML ecosystem doesn't exist in Mojo yet. Calling Python via FFI adds a boundary for zero gain. No measured bottleneck justifies it. Revisit when a specific hot loop needs it.

**All-Go for MVP** — the ML ecosystem is Python. Writing a companion server entirely in Go means fighting the ecosystem for every model operation before the product is validated.

**VPS as scaling endpoint** — fine for MVP (one user), wrong for SaaS. Single box = single point of failure, GPU ceiling, no redundancy. SaaS requires container orchestration with sticky WebSocket sessions and shared state.

---

## Architecture Discipline (Critical)

The Python MVP must be written as if it were already services, so the Go port is extraction, not rewrite:

```
server/
  asr/          — interface + implementations (whisper, yandex, ...)
  llm/          — interface + implementations (claude, gpt, local)
  tts/          — interface + implementations (elevenlabs, yandex, silero)
  memory/       — episodic summarization, retrieval, consolidation
  graph/        — Neo4j entity/relationship management
  avatar/       — viseme/blendshape generation
  transport/    — WebSocket handlers, audio framing
  models/       — SQLAlchemy models
  config.py     — vendor selection via config
```

Every external dependency behind a Protocol/abstract interface. Memory pipeline as isolated, testable functions. DB access behind repository pattern. Config-driven vendor selection.

---

## High-Level Architecture

```
┌─────────────────────────── Android Client (Godot) ───────────────────────────┐
│                                                                               │
│  Mic (continuous) ──────── stream ───────► [Server]                          │
│  Camera (v2) ──────────── stream ────────► [Server]                          │
│                                                                               │
│  Avatar (lip-synced) ◄── audio + visemes ◄── [Server]                       │
│  Speaker ◄── TTS audio ◄── [Server]                                         │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
┌──────────────────────── Server (Python MVP) ─────────────────────────────────┐
│                                                                               │
│  ASR (RU/EN)    ──►  Memory Pipeline  ──►  RAG Retrieval                    │
│  (always-on)          │                        │                              │
│                    summarize               vector + graph                    │
│                    extract                  (pgvector + Neo4j)               │
│                    consolidate                  │                            │
│                       │                         │                            │
│                       └────►  LLM (dementia-tuned) ◄──┘                      │
│                                      │                                        │
│                              ┌───────┴───────┐                                │
│                              │               │                                │
│                            TTS           viseme/timing                        │
│                              │               │                                │
│                              └───────┬───────┘                                │
│                                      │                                        │
│                                      ▼                                        │
│                              WebSocket to client                              │
│                                                                               │
│  Storage:                                                                    │
│    Postgres + pgvector — transcripts, episodes, digests, vectors             │
│    Neo4j               — knowledge graph (entities, relationships)           │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## Memory Pipeline

The differentiator. Raw transcripts are useless to query. The pipeline transforms continuous audio into queryable memory.

### Layers

1. **Raw layer.** Timestamped transcript chunks from ASR. Cheap store (Postgres). Rolling buffer; detail degrades over time.

2. **Episodic layer.** Every 5-15 minutes, an LLM summarizes the chunk into discrete events:
   - `14:32 — Дочь Елена позвонила. Говорили про внука, он сдал экзамен.`
   - `15:10 — Приняла лекарство после обеда.`
   Stored in Postgres with embeddings in pgvector.

3. **Knowledge graph layer.** Entities and relationships extracted from episodes, stored in Neo4j:
   - People, places, objects, medications, routines
   - Relationships: VISITED, CALLED, MENTIONED, TOOK, SAME_AS
   - Enables structured queries ("who visited this week?") that vector search alone cannot answer well

4. **Consolidation layer.** Daily digests. Important recurring entities promoted to long-term memory graph. Reduces storage and sharpens retrieval signal over time.

### Query Path

The patient asks a question → retrieve relevant context via:
- **Vector search** (pgvector): semantic similarity to the question
- **Graph traversal** (Neo4j): relational reasoning about entities
- **Recency weighting**: recent events prioritized
- → LLM answers grounded in retrieved memory (cites time: "Это было сегодня утром...")
- → Never fabricates. States clearly when it doesn't know.

---

## Avatar

### v1: 2D Talking-Head

A single portrait animated via visemes/blendshapes from TTS audio. Best realism/effort ratio for MVP.

**Options:** D-ID, SadTalker, SyncLabs (cloud), or on-device animation in Godot from viseme data.

### v2+: 3D / MetaHuman (deferred)

MetaHuman (Unreal Engine) requires heavy GPU and pixel-streaming from server. Adds ~200ms latency and a GPU server cost. Only pursue if 2D realism proves insufficient for patient comfort. Godot's 3D capabilities offer a middle ground without the Unreal overhead.

**Dementia-specific concern:** The avatar must not look uncanny/creepy. That can distress patients. Warm, simple, friendly beats photorealistic-but-eerie.

---

## Dementia-Specific Behavior

The companion's conversational behavior is tuned for patients with dementia and Alzheimer's:

- **Never argue with confabulation.** Redirect gently, don't harshly correct.
- **Orient without lecturing.** "Сейчас вечер, вторник..." woven naturally.
- **Be warm and patient.** Repeat information without frustration.
- **Ground strictly in memory.** Never invent memories. Clearly distinguish what it knows vs doesn't know.
- **Don't overwhelm.** Short answers. One thought at a time.

This is a specialty requiring heavy iteration on the system prompt based on real interaction with patients.

---

## Privacy

Stance for MVP: tolerate cloud processing (Yandex, Claude/GPT, ElevenLabs) for better experience. All viable.

For SaaS (other people's data): revisit. Health-adjacent data (conversations with dementia patients) carries compliance obligations (GDPR/HIPAA-adjacent). Encryption at rest, audit trails, managed backups become mandatory.

---

## Phased Roadmap

### Phase 1: MVP (Single Patient)

- Python server on a VPS (Hetzner, CPU-only, cloud ML APIs)
- Postgres + pgvector + Neo4j on-box
- Godot client: continuous mic, 2D avatar, speaker
- Always-on transcription, episodic memory, RAG retrieval
- Dementia-tuned system prompt
- Wake word ("помощник") to trigger responses; always-on silent memory
- Defer: video, MetaHuman, on-device inference

**Goal:** Validate that the memory pipeline and dementia-aware conversation actually help the patient.

### Phase 2: Early SaaS (10-50 users)

- Same Python + auth + multi-tenant Postgres/Neo4j + billing
- Managed Postgres (RDS / Cloud SQL), managed Neo4j (AuraDB)
- Docker, 2-3 replicas behind load balancer with WebSocket support
- Redis for shared session state
- Cost optimization focus (per-user inference cost is the killer)

**Goal:** Do people pay for this? What breaks? Establish unit economics.

### Phase 3: Scale (Go + C++ port)

- Port server to Go + whisper.cpp + ONNX Runtime
- Single static binary, containerized
- Kubernetes (managed: EKS/GKE) or strong PaaS (Fly.io)
- GPU node pools for local ASR/TTS where unit economics demand
- Multi-AZ redundancy, observability

**Goal:** Margin, reliability, drive cost-per-user down.

---

## Deployment (MVP)

- **VPS:** Hetzner (best price/performance, Yandex API latency fine from EU)
- **CPU-only:** cloud APIs for all ML (Whisper via Yandex, Claude/GPT, Yandex TTS)
- **Postgres + pgvector + Neo4j:** on-box
- **Cloudflare:** in front (DDoS, TLS)
- **Backups:** encrypted daily to S3/R2
- **Cost estimate:** EUR 20-40/month for one user

---

## Open Questions (Non-Blocking)

1. **ASR vendor.** faster-whisper (local, multilingual, needs GPU VPS) vs Yandex SpeechKit (cloud, excellent Russian, cheap) vs cloud APIs for English. Decide after testing both against real patient audio in both languages.
2. **TTS voice.** ElevenLabs (natural, multilingual, costly) vs Yandex (best Russian prosody) vs Silero (local, free, both languages). Test warmth and clarity with patients in both languages.
3. **Wake word engine.** Porcupine (Picovoice, free tier, supports custom Russian and English wake words) vs Vosk vs simple volume/keyword detection on transcript stream.
4. **Avatar v1 approach.** Cloud (D-ID, adds latency + cost) vs on-device Godot animation from visemes (lower latency, less realistic). Latency budget may decide this.
