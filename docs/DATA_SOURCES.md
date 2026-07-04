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
title_en
body_original_ref
body_en_ref
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
summary_en
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

