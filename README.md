# QuantPilot Studio

中文名：寰量智舱

QuantPilot Studio is an AI-first investment research and quantitative trading workspace for non-technical users. It combines a desktop IDE-style workspace, mobile companion apps, licensed financial news APIs, AI analysis, backtesting, paper trading, and guarded live-trading workflows.

This repository starts as a planning and integration blueprint. The product strategy is to stitch mature open-source systems together, keeping custom code limited to adapters, orchestration, user experience, permissions, and risk controls.

## Product Shape

- Desktop apps: Windows and macOS, based on Eclipse Theia Desktop.
- Mobile apps: iOS and Android, based on Flutter.
- Backend sync: self-hosted cloud backend with PostgreSQL/TimescaleDB, Redis, S3/MinIO, WebSocket, REST/gRPC, APNs, and FCM.
- Quant engine: QuantConnect LEAN.
- Financial data layer: OpenBB plus licensed market/news providers.
- AI research: Qlib, FinGPT/FinBERT, and LLM tool-calling.
- Beginner strategy authoring: Blockly, with advanced code editing kept in the desktop workspace.

## Core Documents

- [Project Plan](docs/PROJECT_PLAN.md)
- [Simulation Test Chain](docs/SIMULATION_TEST_CHAIN.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Data Sources](docs/DATA_SOURCES.md)
- [ADR-0001: Product Architecture](docs/adr/0001-product-architecture.md)

## Safety Principle

AI can analyze, explain, draft, and propose. AI cannot directly place live orders. Every live order must pass deterministic risk checks, audit logging, and user-controlled approval rules.

