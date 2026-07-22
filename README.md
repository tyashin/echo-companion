# Echo Companion

An always-on AI companion for elderly individuals with dementia and Alzheimer's disease. It continuously listens, memorizes daily events, and answers questions about the past — helping patients recall what happened and stay oriented.

Communicates in **Russian and English** through a lip-synced avatar with a warm, patient voice.

## How It Works

- **Always listening.** Continuously captures and transcribes ambient audio.
- **Lives in memory.** Summarizes events into an episodic memory store and a knowledge graph of people, places, and routines.
- **Answers naturally.** When the patient asks, the companion retrieves relevant memories and responds conversationally, grounded in what actually happened.
- **Dementia-aware.** Conversational tone is tuned for dementia care: gentle, never argumentative, never fabricates.

## Tech Stack

| Layer | Technology |
|---|---|
| Client | Godot (GDScript) — Android tablet/phone, 2D avatar, lip-sync |
| Server (MVP) | Python (FastAPI), Postgres + pgvector, Neo4j |
| Server (Scale) | Go + C++ (whisper.cpp, ONNX Runtime) |
| ML | Whisper (ASR), Claude/GPT (LLM), ElevenLabs/Yandex/Silero (TTS) |

## Project Structure

```
echo-companion/
  design_docs/
    architecture.md    — full architecture and design decisions
  server/              — Python server (MVP)
  client/              — Godot client (Android)
```

## Status

Early design phase. See [`design_docs/architecture.md`](design_docs/architecture.md) for the full architecture, rationale, and phased roadmap.
