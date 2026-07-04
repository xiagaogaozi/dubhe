# Data Sources

## 1. Source Policy

Production must use licensed APIs or official public APIs. Unauthorized scraping is not part of the production architecture.

Every data provider must define:

- provider name。
- market coverage。
- asset coverage。
- latency。
- redistribution rights。
- storage rights。
- allowed display fields。
- allowed AI processing scope。
- cost model。
- outage fallback。

## 1.1 Implemented in Core

Current runnable adapters:

| Provider | Endpoint | Market | Runtime status |
| --- | --- | --- | --- |
| SEC EDGAR | `https://data.sec.gov/submissions/CIK##########.json` | US filings | implemented for a first CIK map: NVDA, AAPL, MSFT, AMD, TSLA, AMZN, GOOGL, META |
| GDELT DOC 2.1 | `https://api.gdeltproject.org/api/v2/doc/doc` | global news index | implemented as public macro/news context, not a licensed exchange-grade source |
| Fixture | local generated `NewsEvent` | all markets | implemented as deterministic fallback for tests and outages |

Core endpoint:

```http
GET /v1/news/feed?market=US&symbol=NVDA&limit=8&live=true
```

Behavior:

- When `live=true`, Core tries SEC EDGAR and GDELT where applicable.
- Provider failures return Chinese provider status instead of crashing the client.
- If no live event is available, Core returns fixture events so the AI analysis and simulation chain remains testable.
- Returned events are persisted in SQLite and included in workspace snapshots.

Compliance notes:

- SEC EDGAR events are official public filings metadata and links; Core sets a configurable `DUBHE_SEC_USER_AGENT`.
- GDELT is a public news index; it does not grant redistribution rights for original publisher article bodies. Dubhe stores title, source URL, metadata, and license flags only.
- Commercial A-share, Hong Kong, and institutional news feeds still require contracts before production use.

## 2. A-share Sources

| Source | Use | Status |
| --- | --- | --- |
| Wind | market data, news, filings, research | commercial license required |
| iFinD | market data, news, filings, research | commercial license required |
| Choice | market data, news, filings, research | commercial license required |
| CNINFO | listed company announcements | official/API terms required |
| SSE/SZSE | exchange disclosures | official/API terms required |
| Tushare Pro | research data supplement | token and quota required |
| 财联社 | authoritative fast financial news | commercial license required |
| 华尔街见闻 | financial news | commercial license required |

## 3. Hong Kong Sources

| Source | Use | Status |
| --- | --- | --- |
| HKEXnews / HKEX IIS | issuer announcements | license/terms required |
| AASTOCKS | market news | commercial license required |
| ET Net | market news | commercial license required |
| Futu OpenAPI | market/account/trading candidate | account and API permission required |

## 4. US / Global Sources

| Source | Use | Status |
| --- | --- | --- |
| SEC EDGAR APIs | filings and company disclosures | official public API |
| Benzinga | market news and alerts | commercial API |
| Dow Jones Newswires | institutional news | commercial API |
| Nasdaq Data Link | data products | commercial/free tiers vary |
| Finnhub | company news, market data | API key and plan required |
| Alpha Vantage | news sentiment and market data | API key and plan required |
| Polygon/Massive | market data/news | API key and plan required |
| GDELT | global macro/news context | public data, not exchange-grade |

## 5. Normalized Contracts

### NewsEvent

```text
id
provider
provider_event_id
source_name
market_scope
language
title_original
title_zh
body_original_ref
body_zh_ref
published_at
received_at
url
tickers
entities
event_type
authority_score
duplicate_group_id
license_flags
```

### MarketBar

```text
symbol
market
time
open
high
low
close
volume
currency
adjustment_type
provider
data_snapshot_id
```

### FilingEvent

```text
id
provider
company_id
symbol
filing_type
published_at
received_at
document_url
document_ref
language
summary_zh
license_flags
```

## 6. Provider Adapter Requirements

Each adapter must provide:

- `fetch_latest`。
- `fetch_since`。
- `normalize`。
- `validate_license`。
- `dedupe_key`。
- `health_check`。
- `mock_fixture`。
- `replay_fixture`。

## 7. Fallback Rules

- If a provider is down, mark source health as degraded.
- If a licensed provider forbids storage of full body, store only reference and permitted fields.
- If AI processing is not licensed, disable AI on that source and show metadata-only summary.
- If two providers disagree, show source-level confidence and keep both raw references.
