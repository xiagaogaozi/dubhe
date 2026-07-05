from __future__ import annotations

from .models import (
    AssistantChatRequest,
    AssistantChatResponse,
    AssistantCitation,
    BacktestResult,
    NewsAnalysis,
    NewsEvent,
    StrategyDraft,
)
from .llm import answer_with_configured_llm


def answer_research_question(request: AssistantChatRequest) -> AssistantChatResponse:
    fallback = answer_research_question_deterministic(request)
    return answer_with_configured_llm(request, fallback)


def answer_research_question_deterministic(request: AssistantChatRequest) -> AssistantChatResponse:
    """Deterministic Chinese research assistant for the local, auditable MVP."""
    question = request.question_zh.strip()
    context = request.context
    citations = _citations(context.news_event, context.analysis, context.strategy, context.backtest)
    answer_parts = [
        _context_summary(context.news_event, context.analysis, context.strategy, context.backtest)
    ]

    if _contains_any(question, ["实盘", "真实", "下单", "买入", "卖出", "交易"]):
        answer_parts.append(
            "不能把这次对话当作直接实盘指令。AI 只能解释信息、整理策略线索和生成订单意图；真实订单必须经过确定性风控、审计记录和人工审批。"
        )

    if _contains_any(question, ["影响", "新闻", "为什么", "原因", "利好", "利空"]):
        answer_parts.append(_analysis_answer(context.analysis, context.news_event))

    if _contains_any(question, ["策略", "脚本", "量化", "规则", "代码"]):
        answer_parts.append(_strategy_answer(context.strategy, context.analysis))

    if _contains_any(question, ["回测", "收益", "回撤", "胜率", "验证"]):
        answer_parts.append(_backtest_answer(context.backtest))

    if len(answer_parts) == 1:
        answer_parts.append(
            "你可以继续问：这条新闻影响哪些标的、策略规则是否太激进、回测结果是否值得继续纸面验证，或需要我把当前上下文整理成策略制作清单。"
        )

    return AssistantChatResponse(
        answer_zh="\n\n".join(part for part in answer_parts if part),
        citations=citations,
        suggested_actions_zh=_suggested_actions(
            context.analysis, context.strategy, context.backtest
        ),
        safety_notes_zh=[
            "不提供绕过风控的实盘下单建议。",
            "没有来源引用、策略草案和回测结果时，只能作为研究提示，不能作为交易依据。",
            "纸面交易用于验证流程和假设，不代表真实收益。",
        ],
    )


def _contains_any(value: str, keywords: list[str]) -> bool:
    normalized = value.lower()
    return any(keyword.lower() in normalized for keyword in keywords)


def _context_summary(
    news_event: NewsEvent | None,
    analysis: NewsAnalysis | None,
    strategy: StrategyDraft | None,
    backtest: BacktestResult | None,
) -> str:
    if analysis:
        tickers = "、".join(analysis.affected_tickers) or "暂无明确标的"
        return (
            f"我已读取当前中文研究上下文：影响分 {analysis.impact_score:.0%}，"
            f"情绪为{_sentiment_zh(analysis.sentiment.value)}，关联标的 {tickers}。"
        )
    if news_event:
        tickers = "、".join(news_event.tickers) or "暂无明确标的"
        title = news_event.title_zh or news_event.title_original
        return f"我已读取当前新闻：{title}。关联标的：{tickers}。"
    if strategy:
        return f"我已读取当前策略草案：{strategy.name}，版本 {strategy.strategy_version_id}。"
    if backtest:
        return f"我已读取当前回测：{backtest.symbol}，收益 {_percent(backtest.total_return)}。"
    return "当前没有足够的新闻、分析、策略或回测上下文；我会先给出通用研究路径。"


def _analysis_answer(analysis: NewsAnalysis | None, news_event: NewsEvent | None) -> str:
    if analysis:
        return (
            f"新闻影响解读：{analysis.summary_zh} "
            f"置信度 {analysis.confidence:.0%}，建议先把它当作待验证假设，而不是交易结论。"
        )
    if news_event:
        title = news_event.title_zh or news_event.title_original
        return f"这条新闻还没有生成影响分析。建议先点击“分析”，再根据影响分、情绪和来源引用生成策略草案。新闻标题：{title}"
    return "还没有新闻分析上下文。建议先刷新新闻并运行中文影响分析。"


def _strategy_answer(strategy: StrategyDraft | None, analysis: NewsAnalysis | None) -> str:
    if strategy:
        entries = "；".join(strategy.spec.entry_rules)
        exits = "；".join(strategy.spec.exit_rules)
        assets = "、".join(strategy.spec.asset_universe)
        return (
            f"策略制作建议：当前草案覆盖 {assets}，入场规则为：{entries}。退出规则为：{exits}。"
            "下一步应先运行回测，再进入纸面交易验证；不要直接进入实盘。"
        )
    if analysis:
        assets = "、".join(analysis.affected_tickers) or "当前新闻标的"
        return (
            f"可以先围绕 {assets} 制作低风险纸面验证策略：入场只使用新闻情绪和影响分，"
            "单笔名义金额设置上限，并把 broker 权限限制为 paper。"
        )
    return "还没有策略草案。建议先完成新闻分析，再用策略工坊或“策略”按钮生成可校验草案。"


def _backtest_answer(backtest: BacktestResult | None) -> str:
    if not backtest:
        return "还没有回测结果。建议先运行 deterministic replay，看收益、最大回撤、胜率和交易次数是否符合纸面验证门槛。"
    return (
        f"回测解读：{backtest.symbol} 在 {backtest.replay_scenario} 中收益 {_percent(backtest.total_return)}，"
        f"基准 {_percent(backtest.benchmark_return)}，最大回撤 {_percent(backtest.max_drawdown)}，"
        f"胜率 {_percent(backtest.win_rate)}，交易 {backtest.trade_count} 次。"
        f"{' 风险提示：' + '；'.join(backtest.risk_notes_zh) if backtest.risk_notes_zh else ''}"
    )


def _suggested_actions(
    analysis: NewsAnalysis | None,
    strategy: StrategyDraft | None,
    backtest: BacktestResult | None,
) -> list[str]:
    actions: list[str] = []
    if analysis is None:
        actions.append("先运行新闻影响分析，生成中文摘要、影响分和来源引用。")
    if strategy is None:
        actions.append("生成或载入策略草案，并确认 broker 权限仅为 paper。")
    if backtest is None:
        actions.append("运行回测，检查收益、最大回撤、胜率和交易次数。")
    actions.append("只在纸面账户验证；实盘必须经过风控和人工审批。")
    return actions


def _citations(
    news_event: NewsEvent | None,
    analysis: NewsAnalysis | None,
    strategy: StrategyDraft | None,
    backtest: BacktestResult | None,
) -> list[AssistantCitation]:
    citations: list[AssistantCitation] = []
    if news_event:
        citations.append(
            AssistantCitation(
                label_zh=news_event.source_name,
                ref=news_event.url or news_event.provider_event_id or news_event.id,
            )
        )
    if analysis:
        for ref in analysis.source_refs:
            citations.append(AssistantCitation(label_zh="新闻分析来源", ref=ref))
    if strategy:
        citations.append(AssistantCitation(label_zh="策略草案", ref=strategy.id))
    if backtest:
        citations.append(AssistantCitation(label_zh="回测结果", ref=backtest.id))
    return citations


def _sentiment_zh(value: str) -> str:
    if value == "positive":
        return "正面"
    if value == "negative":
        return "负面"
    return "中性"


def _percent(value: float) -> str:
    return f"{value * 100:.2f}%"
