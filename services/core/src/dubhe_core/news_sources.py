from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from hashlib import sha1
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from .models import Market, NewsEvent, NewsFeedResponse, NewsProviderStatus, ProviderStatus, utc_now

JsonFetcher = Callable[[str, dict[str, str], float], Any]

SEC_TICKERS: dict[str, tuple[str, str]] = {
    "AAPL": ("0000320193", "苹果"),
    "AMD": ("0000002488", "超威半导体"),
    "AMZN": ("0001018724", "亚马逊"),
    "GOOGL": ("0001652044", "谷歌"),
    "META": ("0001326801", "Meta"),
    "MSFT": ("0000789019", "微软"),
    "NVDA": ("0001045810", "英伟达"),
    "TSLA": ("0001318605", "特斯拉"),
}

GDELT_ENTITY_HINTS: dict[str, str] = {
    "000001.SZ": "平安银行",
    "00700.HK": "Tencent",
    "0700.HK": "Tencent",
    "600519.SH": "Kweichow Moutai",
    "AAPL": "Apple",
    "AMD": "AMD",
    "MSFT": "Microsoft",
    "NVDA": "NVIDIA",
    "TSLA": "Tesla",
}


def fetch_news_feed(
    market: Market,
    symbol: str | None,
    limit: int,
    live: bool,
    fetcher: JsonFetcher | None = None,
) -> NewsFeedResponse:
    normalized_symbol = symbol.strip().upper() if symbol else None
    events: list[NewsEvent] = []
    statuses: list[NewsProviderStatus] = []

    if live:
        http_fetcher = fetcher or fetch_json

        finnhub_events, finnhub_status = fetch_finnhub_company_news(
            market=market,
            symbol=normalized_symbol,
            limit=limit,
            fetcher=http_fetcher,
        )
        events.extend(finnhub_events)
        statuses.append(finnhub_status)

        alpha_vantage_events, alpha_vantage_status = fetch_alpha_vantage_news_sentiment(
            market=market,
            symbol=normalized_symbol,
            limit=limit,
            fetcher=http_fetcher,
        )
        events.extend(alpha_vantage_events)
        statuses.append(alpha_vantage_status)

        sec_events, sec_status = fetch_sec_edgar_filings(
            market=market,
            symbol=normalized_symbol,
            limit=limit,
            fetcher=http_fetcher,
        )
        events.extend(sec_events)
        statuses.append(sec_status)

        gdelt_events, gdelt_status = fetch_gdelt_articles(
            market=market,
            symbol=normalized_symbol,
            limit=limit,
            fetcher=http_fetcher,
        )
        events.extend(gdelt_events)
        statuses.append(gdelt_status)
    else:
        statuses.append(
            NewsProviderStatus(
                provider="live_sources",
                status=ProviderStatus.SKIPPED,
                message_zh="未请求实时源，返回本地演示新闻。",
            ),
        )

    deduped_events = dedupe_events(events)
    if not deduped_events:
        fallback = fixture_news_events(market=market, symbol=normalized_symbol, limit=limit)
        deduped_events.extend(fallback)
        statuses.append(
            NewsProviderStatus(
                provider="fixture",
                status=ProviderStatus.OK,
                fetched_count=len(fallback),
                message_zh="真实来源暂不可用，已使用本地演示新闻兜底。",
            ),
        )

    return NewsFeedResponse(
        events=deduped_events[:limit],
        provider_status=statuses,
    )


def fetch_json(url: str, headers: dict[str, str], timeout: float) -> dict[str, Any]:
    request = Request(url, headers=headers)
    with urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_finnhub_company_news(
    market: Market,
    symbol: str | None,
    limit: int,
    fetcher: JsonFetcher,
) -> tuple[list[NewsEvent], NewsProviderStatus]:
    api_key = os.environ.get("FINNHUB_API_KEY")
    if not api_key:
        return (
            [],
            NewsProviderStatus(
                provider="finnhub_company_news",
                status=ProviderStatus.SKIPPED,
                message_zh="未配置 FINNHUB_API_KEY，已跳过 Finnhub 授权新闻源。",
            ),
        )
    if market not in {Market.US, Market.GLOBAL}:
        return (
            [],
            NewsProviderStatus(
                provider="finnhub_company_news",
                status=ProviderStatus.SKIPPED,
                message_zh="Finnhub company-news 当前仅作为美股/全球新闻源调用。",
            ),
        )
    if symbol is None:
        return (
            [],
            NewsProviderStatus(
                provider="finnhub_company_news",
                status=ProviderStatus.SKIPPED,
                message_zh="Finnhub company-news 需要股票代码。",
            ),
        )

    end_date = datetime.now(timezone.utc).date()
    start_date = end_date - timedelta(days=7)
    url = "https://finnhub.io/api/v1/company-news?" + urlencode(
        {
            "symbol": symbol,
            "from": start_date.isoformat(),
            "to": end_date.isoformat(),
            "token": api_key,
        },
    )

    try:
        payload = fetcher(url, {"Accept": "application/json"}, 6)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        return (
            [],
            NewsProviderStatus(
                provider="finnhub_company_news",
                status=ProviderStatus.UNAVAILABLE,
                message_zh=f"Finnhub 授权新闻源暂不可用：{exc}",
            ),
        )

    if not isinstance(payload, list):
        return (
            [],
            NewsProviderStatus(
                provider="finnhub_company_news",
                status=ProviderStatus.UNAVAILABLE,
                message_zh="Finnhub 返回格式不是新闻列表。",
            ),
        )

    events: list[NewsEvent] = []
    for article in payload[:limit]:
        if not isinstance(article, dict):
            continue
        headline = str(article.get("headline") or "").strip()
        article_url = str(article.get("url") or "").strip()
        if not headline:
            continue
        source = str(article.get("source") or "Finnhub").strip() or "Finnhub"
        published_at = parse_unix_datetime(article.get("datetime"))
        events.append(
            NewsEvent(
                id=stable_news_id("finnhub_company_news", article_url or headline),
                provider="finnhub_company_news",
                provider_event_id=str(article.get("id") or article_url or headline),
                source_name=source,
                market_scope=[Market.US],
                language="en",
                title_original=headline,
                title_zh=headline,
                published_at=published_at,
                url=article_url or None,
                tickers=[symbol],
                entities=[GDELT_ENTITY_HINTS.get(symbol, symbol)],
                event_type=str(article.get("category") or "company_news"),
                authority_score=0.78,
                license_flags=["finnhub_api", "provider_terms_required", "metadata_only"],
            ),
        )

    return (
        events,
        NewsProviderStatus(
            provider="finnhub_company_news",
            status=ProviderStatus.OK,
            fetched_count=len(events),
            message_zh=f"已从 Finnhub 授权新闻源拉取 {len(events)} 条公司新闻。",
        ),
    )


def fetch_alpha_vantage_news_sentiment(
    market: Market,
    symbol: str | None,
    limit: int,
    fetcher: JsonFetcher,
) -> tuple[list[NewsEvent], NewsProviderStatus]:
    api_key = os.environ.get("ALPHA_VANTAGE_API_KEY")
    if not api_key:
        return (
            [],
            NewsProviderStatus(
                provider="alpha_vantage_news_sentiment",
                status=ProviderStatus.SKIPPED,
                message_zh="未配置 ALPHA_VANTAGE_API_KEY，已跳过 Alpha Vantage 新闻情绪源。",
            ),
        )
    if symbol is None:
        return (
            [],
            NewsProviderStatus(
                provider="alpha_vantage_news_sentiment",
                status=ProviderStatus.SKIPPED,
                message_zh="Alpha Vantage NEWS_SENTIMENT 需要股票代码。",
            ),
        )

    url = "https://www.alphavantage.co/query?" + urlencode(
        {
            "function": "NEWS_SENTIMENT",
            "tickers": symbol,
            "sort": "LATEST",
            "limit": str(max(1, min(limit, 50))),
            "apikey": api_key,
        },
    )

    try:
        payload = fetcher(url, {"Accept": "application/json"}, 6)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        return (
            [],
            NewsProviderStatus(
                provider="alpha_vantage_news_sentiment",
                status=ProviderStatus.UNAVAILABLE,
                message_zh=f"Alpha Vantage 新闻情绪源暂不可用：{exc}",
            ),
        )

    if not isinstance(payload, dict):
        return (
            [],
            NewsProviderStatus(
                provider="alpha_vantage_news_sentiment",
                status=ProviderStatus.UNAVAILABLE,
                message_zh="Alpha Vantage 返回格式不是 JSON 对象。",
            ),
        )
    provider_error = payload.get("Error Message") or payload.get("Note") or payload.get("Information")
    if provider_error:
        return (
            [],
            NewsProviderStatus(
                provider="alpha_vantage_news_sentiment",
                status=ProviderStatus.UNAVAILABLE,
                message_zh=f"Alpha Vantage 返回提示：{provider_error}",
            ),
        )

    feed = payload.get("feed", [])
    if not isinstance(feed, list):
        feed = []

    events: list[NewsEvent] = []
    scope = [market] if market != Market.GLOBAL else [Market.GLOBAL]
    for article in feed[:limit]:
        if not isinstance(article, dict):
            continue
        title = str(article.get("title") or "").strip()
        article_url = str(article.get("url") or "").strip()
        if not title:
            continue
        source = str(article.get("source") or "Alpha Vantage").strip() or "Alpha Vantage"
        mentioned_tickers = alpha_vantage_tickers(article.get("ticker_sentiment"), fallback=symbol)
        events.append(
            NewsEvent(
                id=stable_news_id("alpha_vantage_news_sentiment", article_url or title),
                provider="alpha_vantage_news_sentiment",
                provider_event_id=article_url or title,
                source_name=source,
                market_scope=scope,
                language="en",
                title_original=title,
                title_zh=title,
                published_at=parse_alpha_vantage_time(article.get("time_published")),
                url=article_url or None,
                tickers=mentioned_tickers,
                entities=[GDELT_ENTITY_HINTS.get(symbol, symbol)],
                event_type=str(article.get("category_within_source") or "news_sentiment"),
                authority_score=0.72,
                license_flags=["alpha_vantage_api", "provider_terms_required", "metadata_only"],
            ),
        )

    return (
        events,
        NewsProviderStatus(
            provider="alpha_vantage_news_sentiment",
            status=ProviderStatus.OK,
            fetched_count=len(events),
            message_zh=f"已从 Alpha Vantage 新闻情绪源拉取 {len(events)} 条新闻。",
        ),
    )


def fetch_sec_edgar_filings(
    market: Market,
    symbol: str | None,
    limit: int,
    fetcher: JsonFetcher,
) -> tuple[list[NewsEvent], NewsProviderStatus]:
    if market not in {Market.US, Market.GLOBAL}:
        return (
            [],
            NewsProviderStatus(
                provider="sec_edgar",
                status=ProviderStatus.SKIPPED,
                message_zh="SEC EDGAR 只覆盖美股与全球视图，本次市场未调用。",
            ),
        )
    if symbol is None or symbol not in SEC_TICKERS:
        return (
            [],
            NewsProviderStatus(
                provider="sec_edgar",
                status=ProviderStatus.SKIPPED,
                message_zh="暂未配置该股票代码的 SEC CIK 映射。",
            ),
        )

    cik, company_zh = SEC_TICKERS[symbol]
    url = f"https://data.sec.gov/submissions/CIK{cik}.json"
    headers = {
        "Accept": "application/json",
        "User-Agent": os.environ.get("DUBHE_SEC_USER_AGENT", "Dubhe/0.1 contact@example.com"),
    }

    try:
        payload = fetcher(url, headers, 6)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        return (
            [],
            NewsProviderStatus(
                provider="sec_edgar",
                status=ProviderStatus.UNAVAILABLE,
                message_zh=f"SEC EDGAR 暂不可用：{exc}",
            ),
        )

    recent = payload.get("filings", {}).get("recent", {})
    accession_numbers = recent.get("accessionNumber", [])
    forms = recent.get("form", [])
    filing_dates = recent.get("filingDate", [])
    primary_documents = recent.get("primaryDocument", [])
    cik_number = str(int(cik))
    events: list[NewsEvent] = []

    for index, accession_number in enumerate(accession_numbers[:limit]):
        form = _list_get(forms, index, "UNKNOWN")
        filing_date = parse_datetime(_list_get(filing_dates, index, None))
        primary_document = _list_get(primary_documents, index, "")
        accession_path = str(accession_number).replace("-", "")
        filing_url = (
            f"https://www.sec.gov/Archives/edgar/data/{cik_number}/{accession_path}/"
            f"{primary_document}"
            if primary_document
            else f"https://www.sec.gov/Archives/edgar/data/{cik_number}/{accession_path}/"
        )
        title_zh = f"{company_zh}提交 SEC {form} 文件"
        events.append(
            NewsEvent(
                id=stable_news_id("sec_edgar", f"{symbol}:{accession_number}:{form}"),
                provider="sec_edgar",
                provider_event_id=str(accession_number),
                source_name="SEC EDGAR",
                market_scope=[Market.US],
                language="en",
                title_original=f"{symbol} SEC {form} filing",
                title_zh=title_zh,
                published_at=filing_date,
                url=filing_url,
                tickers=[symbol],
                entities=[company_zh, symbol],
                event_type="filing",
                authority_score=0.96,
                license_flags=["sec_public_data"],
            ),
        )

    return (
        events,
        NewsProviderStatus(
            provider="sec_edgar",
            status=ProviderStatus.OK,
            fetched_count=len(events),
            message_zh=f"已从 SEC EDGAR 拉取 {len(events)} 条公告文件。",
        ),
    )


def fetch_gdelt_articles(
    market: Market,
    symbol: str | None,
    limit: int,
    fetcher: JsonFetcher,
) -> tuple[list[NewsEvent], NewsProviderStatus]:
    query = build_gdelt_query(symbol)
    params = {
        "query": query,
        "mode": "artlist",
        "format": "json",
        "maxrecords": str(max(1, min(limit, 20))),
        "sort": "hybridrel",
        "timespan": "48h",
    }
    url = f"https://api.gdeltproject.org/api/v2/doc/doc?{urlencode(params, quote_via=quote)}"

    try:
        payload = fetcher(url, {"Accept": "application/json"}, 6)
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        return (
            [],
            NewsProviderStatus(
                provider="gdelt_doc",
                status=ProviderStatus.UNAVAILABLE,
                message_zh=f"GDELT 新闻索引暂不可用：{exc}",
            ),
        )

    articles = payload.get("articles", [])
    events: list[NewsEvent] = []
    scope = [market] if market != Market.GLOBAL else [Market.GLOBAL]
    ticker_list = [symbol] if symbol else []

    for article in articles[:limit]:
        title = str(article.get("title") or "GDELT article")
        article_url = str(article.get("url") or "")
        domain = str(article.get("domain") or "GDELT")
        seen_date = parse_datetime(article.get("seendate"))
        events.append(
            NewsEvent(
                id=stable_news_id("gdelt_doc", article_url or title),
                provider="gdelt_doc",
                provider_event_id=article_url or title,
                source_name=domain,
                market_scope=scope,
                language=str(article.get("language") or "unknown"),
                title_original=title,
                title_zh=title,
                published_at=seen_date,
                url=article_url or None,
                tickers=ticker_list,
                entities=[GDELT_ENTITY_HINTS.get(symbol or "", symbol or "全球市场")],
                event_type="news",
                authority_score=0.62,
                license_flags=["gdelt_index", "source_license_must_be_checked"],
            ),
        )

    return (
        events,
        NewsProviderStatus(
            provider="gdelt_doc",
            status=ProviderStatus.OK,
            fetched_count=len(events),
            message_zh=f"已从 GDELT 新闻索引拉取 {len(events)} 条新闻。",
        ),
    )


def fixture_news_events(market: Market, symbol: str | None, limit: int) -> list[NewsEvent]:
    ticker = symbol or "NVDA"
    company = GDELT_ENTITY_HINTS.get(ticker, SEC_TICKERS.get(ticker, ("", ticker))[1])
    return [
        NewsEvent(
            id=stable_news_id("fixture", f"{ticker}:earnings"),
            provider="fixture",
            provider_event_id=f"{ticker}-fixture-earnings",
            source_name="本地演示新闻源",
            market_scope=[market],
            language="zh-CN",
            title_original=f"{company}业绩超预期并宣布回购",
            title_zh=f"{company}业绩超预期并宣布回购",
            published_at=utc_now(),
            url="https://example.com/news/fixture-earnings",
            tickers=[ticker],
            entities=[company],
            event_type="earnings",
            authority_score=0.75,
            license_flags=["fixture"],
        )
    ][:limit]


def dedupe_events(events: list[NewsEvent]) -> list[NewsEvent]:
    seen: set[str] = set()
    deduped: list[NewsEvent] = []
    for event in sorted(events, key=lambda item: item.published_at, reverse=True):
        key = event.url or event.provider_event_id or event.id
        if key in seen:
            continue
        seen.add(key)
        deduped.append(event)
    return deduped


def build_gdelt_query(symbol: str | None) -> str:
    if not symbol:
        return '"stock market" OR earnings OR "central bank"'
    hint = GDELT_ENTITY_HINTS.get(symbol, symbol)
    return f'"{hint}" OR "{symbol}"'


def parse_datetime(value: object) -> datetime:
    if not value:
        return utc_now()
    text = str(value)
    for fmt in ("%Y-%m-%d", "%Y%m%d%H%M%S"):
        try:
            return datetime.strptime(text, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return utc_now()


def parse_unix_datetime(value: object) -> datetime:
    try:
        return datetime.fromtimestamp(float(str(value)), tz=timezone.utc)
    except (TypeError, ValueError, OSError):
        return utc_now()


def parse_alpha_vantage_time(value: object) -> datetime:
    if not value:
        return utc_now()
    text = str(value)
    try:
        return datetime.strptime(text, "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return parse_datetime(text)


def alpha_vantage_tickers(value: object, fallback: str) -> list[str]:
    if not isinstance(value, list):
        return [fallback]
    tickers: list[str] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        ticker = str(item.get("ticker") or "").strip().upper()
        if ticker:
            tickers.append(ticker)
    return tickers or [fallback]


def stable_news_id(provider: str, key: str) -> str:
    digest = sha1(f"{provider}:{key}".encode("utf-8")).hexdigest()[:24]
    return f"news_{provider}_{digest}"


def _list_get(values: object, index: int, default: str | None) -> str | None:
    if not isinstance(values, list) or index >= len(values):
        return default
    value = values[index]
    return str(value) if value is not None else default
