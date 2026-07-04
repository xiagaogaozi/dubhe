# Architecture

## 1. Chosen Architecture

Dubhe uses a two-client, one-cloud architecture:

- Desktop: Eclipse Theia Desktop for Windows and macOS.
- Mobile: Flutter for iOS and Android.
- Cloud: self-hosted backend with PostgreSQL/TimescaleDB, Redis, S3/MinIO, WebSocket, REST/gRPC, APNs, and FCM.

The desktop app is the full research and strategy workspace. The mobile app is a companion app for news, AI discussion, alerts, monitoring, and approvals.

Current repository status:

- `apps/desktop` is a React + Vite desktop prototype, not the final Theia Desktop shell.
- `apps/theia-desktop` is the Eclipse Theia Desktop shell skeleton. It defines an Electron target application package and a Dubhe Theia extension that will gradually absorb the React prototype panels.
- `apps/mobile` is the Flutter Companion source skeleton. It can log in through Dubhe Core, read news, request a Chinese analysis, show the paper portfolio, and handle approval actions once Flutter platform projects are generated.
- The four installable packages are not complete yet. Windows/macOS still need the Theia Desktop packaging path; iOS/Android still need generated Flutter platform projects, signing, icons, push notification setup, and release builds.

## 2. Runtime Boundaries

```text
Client layer
  desktop-theia
  mobile-flutter

API layer
  auth-api
  workspace-api
  news-api
  ai-api
  strategy-api
  backtest-api
  risk-api
  notification-api

Worker layer
  news-ingestion-worker
  ai-analysis-worker
  lean-backtest-worker
  qlib-research-worker
  paper-trading-worker
  replay-test-worker

Data layer
  postgres-timescale
  redis
  minio

External layer
  news providers
  market data providers
  AI model providers
  paper/live brokers
```

## 3. Backend Service Responsibilities

| Service | Responsibility |
| --- | --- |
| Auth Service | account, device, token, roles |
| Workspace Service | watchlists, preferences, projects |
| News Service | provider adapters, normalization, dedupe, ticker mapping |
| AI Service | summarization, event extraction, tool-calling |
| Strategy Service | project/version/template management |
| Backtest Service | LEAN orchestration and result parsing |
| Risk Service | deterministic risk checks and order gate |
| Order Service | paper/live broker adapter boundary |
| Notification Service | WebSocket, APNs, FCM |
| Audit Service | immutable event log |

## 4. Adapter Pattern

Every external provider must be behind an adapter:

```text
Provider SDK/API
  -> provider adapter
  -> normalized contract
  -> core service
```

Adapters must include:

- schema validation。
- rate-limit handling。
- retry/backoff。
- license flags。
- mock fixtures。
- replay fixtures。
- outage behavior。

## 5. Strategy Execution Boundary

No client executes production strategies. Clients only create, edit, approve, and inspect.

```text
Desktop/mobile action
  -> API
  -> Strategy Service
  -> Backtest/Simulation Worker
  -> Risk Service
  -> Order Service
  -> Broker Adapter
```

## 6. AI Safety Boundary

AI can call tools that read data or create drafts. AI cannot call live broker adapters.

Allowed AI tools:

- search_news。
- summarize_news。
- analyze_impact。
- explain_backtest。
- draft_strategy。
- propose_order_intent。

Forbidden AI tools:

- place_live_order。
- modify_risk_policy。
- disable_kill_switch。
- approve_order。

## 7. Deployment Environments

| Environment | Purpose |
| --- | --- |
| local | developer workstation |
| dev | shared integration |
| staging | production-like dry run |
| paper | real-time paper trading |
| production | guarded live trading |

## 8. Packaging Targets

| Platform | Target |
| --- | --- |
| Windows | `.exe` / `.msi` |
| macOS | `.dmg` / `.pkg` / `.app` |
| iOS | TestFlight / App Store / enterprise distribution |
| Android | `.aab` / `.apk` |
