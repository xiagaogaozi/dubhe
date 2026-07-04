# ADR-0001: Product Architecture

## Status

Accepted for initial planning.

## Context

The product must support Windows, macOS, iOS, and Android installation packages. It must not be a web-only product. The target users are Chinese-only non-technical investors, while the system still needs to process A-share, Hong Kong, US, and global financial news.

The product also needs an IDE-like desktop experience for AI-assisted discussion, news analysis, large-scale data analysis, and strategy creation.

## Decision

Use:

- Eclipse Theia Desktop for Windows/macOS.
- Flutter for iOS/Android.
- Self-hosted cloud backend with PostgreSQL/TimescaleDB, Redis, S3/MinIO, WebSocket, REST/gRPC, APNs, and FCM.
- QuantConnect LEAN for backtesting, paper trading, and live-trading integration boundaries.
- OpenBB, Qlib, FinGPT/FinBERT, Blockly, and charting libraries as stitched mature components.

## Consequences

Positive:

- Desktop can feel like a real IDE without rebuilding an IDE from scratch.
- Mobile can stay native-feeling and focused.
- Heavy computation stays server-side.
- Mature engines reduce custom bug surface.
- Product supports controlled trading workflows.

Negative:

- Two client stacks must be maintained.
- Theia extension development and Flutter mobile development require different skills.
- Data provider licensing is a major external dependency.
- Integration testing is critical because most value sits between stitched systems.

## Rejected Alternatives

### One Flutter app for all four platforms

Rejected because building a rich IDE-like desktop experience, editor panels, Notebook-like workflows, and plugin behavior in Flutter would increase custom code surface.

### Tauri v2 for all four platforms

Rejected for the initial plan because mobile maturity and IDE complexity are less predictable than Theia desktop plus Flutter mobile.

### Pure web app

Rejected because the product requirement explicitly asks for installable applications and not a web-only product.
