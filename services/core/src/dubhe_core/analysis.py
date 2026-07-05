from __future__ import annotations

from .models import NewsAnalysis, NewsEvent, Sentiment

POSITIVE_KEYWORDS = ("增长", "上调", "盈利", "超预期", "批准", "回购", "中标", "突破")
NEGATIVE_KEYWORDS = ("下跌", "亏损", "调查", "处罚", "违约", "裁员", "下调", "风险")


def analyze_news(event: NewsEvent) -> NewsAnalysis:
    text = f"{event.title_zh or event.title_original} {event.event_type} {' '.join(event.entities)}"
    positive_hits = sum(1 for keyword in POSITIVE_KEYWORDS if keyword in text)
    negative_hits = sum(1 for keyword in NEGATIVE_KEYWORDS if keyword in text)

    if positive_hits > negative_hits:
        sentiment = Sentiment.POSITIVE
    elif negative_hits > positive_hits:
        sentiment = Sentiment.NEGATIVE
    else:
        sentiment = Sentiment.NEUTRAL

    ticker_factor = min(len(event.tickers) * 0.08, 0.24)
    keyword_factor = min((positive_hits + negative_hits) * 0.1, 0.3)
    impact_score = min(1.0, round(event.authority_score * 0.45 + ticker_factor + keyword_factor, 3))
    confidence = min(1.0, round(0.45 + event.authority_score * 0.35 + ticker_factor, 3))
    title = event.title_zh or event.title_original
    source = event.url or event.provider_event_id or event.id

    return NewsAnalysis(
        news_event_id=event.id,
        summary_zh=f"这条来自{event.source_name}的消息显示：{title}",
        sentiment=sentiment,
        impact_score=impact_score,
        affected_tickers=event.tickers,
        source_refs=[source],
        confidence=confidence,
    )
