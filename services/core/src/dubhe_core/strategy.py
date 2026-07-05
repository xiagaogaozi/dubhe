from __future__ import annotations

from .models import (
    Market,
    StrategyDraft,
    StrategySpec,
    StrategyTemplate,
    StrategyTemplateDraftRequest,
    StrategyValidationResult,
)


STRATEGY_TEMPLATES: tuple[StrategyTemplate, ...] = (
    StrategyTemplate(
        id="news_sentiment_replay",
        label_zh="新闻情绪事件驱动",
        summary_zh="适合先把一条高权威新闻转成纸面买入候选，再用 deterministic replay 做兜底验证。",
        suitable_markets=[Market.A_SHARE, Market.HK, Market.US, Market.GLOBAL],
        default_timeframe="1d",
        default_rebalance_rule="event_driven",
        default_risk_limits={"max_order_notional": 10_000, "max_drawdown_stop": 0.06},
        data_dependencies=["news", "market_bars", "filings"],
        entry_rules_zh=[
            "新闻情绪为正面，且影响分不低于 0.70",
            "新闻必须带来源引用，不能只依赖 AI 推测",
            "只允许进入纸面交易候选，不直接进入实盘",
        ],
        exit_rules_zh=[
            "持有 5 个交易日后退出",
            "回撤达到 6% 时退出",
            "出现负面高影响新闻时退出",
        ],
        guardrails_zh=[
            "必须先通过策略静态校验和 replay 回测",
            "纸面订单必须携带新闻、策略或回测来源引用",
            "实盘权限保持关闭，后续必须走人工审批",
        ],
        source_projects_zh=["QuantConnect LEAN 事件驱动范式", "Qlib 数据/回测分层思想", "Blockly 小白策略积木"],
        next_step_zh="选择标的后生成草案，再运行 replay 回测，最后只提交 1 股纸面订单验证账本。",
    ),
    StrategyTemplate(
        id="announcement_confirmation",
        label_zh="公告确认后再行动",
        summary_zh="适合财报、交易所公告和监管披露；先要求公告/新闻双来源确认，再进入低仓位纸面验证。",
        suitable_markets=[Market.A_SHARE, Market.HK, Market.US],
        default_timeframe="1d",
        default_rebalance_rule="manual_review",
        default_risk_limits={"max_order_notional": 5_000, "max_drawdown_stop": 0.04},
        data_dependencies=["news", "filings", "market_bars"],
        entry_rules_zh=[
            "公告或披露为正面，且至少有一个权威来源引用",
            "AI 摘要必须列出影响标的和不确定点",
            "人工确认公告语义后才允许进入纸面候选",
        ],
        exit_rules_zh=[
            "公告影响兑现或被澄清后退出",
            "回撤达到 4% 时退出",
            "后续披露与原始结论冲突时退出",
        ],
        guardrails_zh=[
            "未确认授权数据源时只能做演示/内测",
            "人工确认前不允许自动下单",
            "实盘必须重新走生产门禁和审批",
        ],
        source_projects_zh=["SEC EDGAR / 交易所公告流", "QuantConnect LEAN RiskManagement 模式", "Qlib replay 验证思想"],
        next_step_zh="先查看来源引用和公告原文，再让 AI 给出核验清单，确认后运行回测。",
    ),
    StrategyTemplate(
        id="watchlist_rebalance",
        label_zh="自选股低仓位再平衡",
        summary_zh="适合把自选股组合做成低仓位纸面观察，不依赖单条新闻直接触发交易。",
        suitable_markets=[Market.A_SHARE, Market.HK, Market.US],
        default_timeframe="1d",
        default_rebalance_rule="daily",
        default_risk_limits={"max_order_notional": 3_000, "max_drawdown_stop": 0.03},
        data_dependencies=["market_bars", "news"],
        entry_rules_zh=[
            "标的在自选池内，且近期新闻没有高影响负面信号",
            "单标的纸面名义金额不超过模板上限",
            "每日只复核一次，不做高频交易",
        ],
        exit_rules_zh=[
            "回撤达到 3% 时退出",
            "出现负面高影响新闻时退出",
            "达到观察期后回到现金并复盘",
        ],
        guardrails_zh=[
            "只用于纸面组合观察，不用于真实资金自动交易",
            "不允许绕过 Dubhe Risk Service",
            "回测通过不代表未来收益",
        ],
        source_projects_zh=["Qlib 组合研究分层", "LEAN PortfolioConstruction 模式", "Blockly 参数化积木"],
        next_step_zh="选择自选股标的，生成草案后先看回测收益、最大回撤和风险说明。",
    ),
)


def validate_strategy_spec(spec: StrategySpec) -> StrategyValidationResult:
    reasons: list[str] = []

    if "max_order_notional" not in spec.risk_limits:
        reasons.append("缺少 `max_order_notional` 风控限制。")

    if not spec.data_dependencies:
        reasons.append("缺少数据依赖声明，例如 news、market_bars 或 filings。")

    if not spec.broker_permissions:
        reasons.append("缺少券商权限声明，至少应声明 paper。")

    return StrategyValidationResult(valid=not reasons, reasons_zh=reasons)


def list_strategy_templates() -> list[StrategyTemplate]:
    return list(STRATEGY_TEMPLATES)


def draft_strategy_from_template(request: StrategyTemplateDraftRequest) -> StrategyDraft:
    template = next(
        (item for item in STRATEGY_TEMPLATES if item.id == request.template_id),
        None,
    )
    if template is None:
        raise ValueError(f"未知策略模板：{request.template_id}")

    risk_limits = dict(template.default_risk_limits)
    risk_limits["max_order_notional"] = request.max_order_notional
    symbol = request.symbol
    spec = StrategySpec(
        strategy_name=f"{symbol} {template.label_zh}",
        market_scope=[request.market],
        asset_universe=[symbol],
        entry_rules=[_render_rule(rule, symbol) for rule in template.entry_rules_zh],
        exit_rules=[_render_rule(rule, symbol) for rule in template.exit_rules_zh],
        risk_limits=risk_limits,
        timeframe=template.default_timeframe,
        rebalance_rule=template.default_rebalance_rule,
        data_dependencies=template.data_dependencies,
        broker_permissions=["paper"],
    )
    validation = validate_strategy_spec(spec)
    validation_text = (
        "已通过策略静态校验。"
        if validation.valid
        else "策略静态校验未通过：" + "；".join(validation.reasons_zh)
    )

    return StrategyDraft(
        name=spec.strategy_name,
        spec=spec,
        explanation_zh=(
            f"由“{template.label_zh}”模板生成。{template.summary_zh}"
            f"{validation_text} 下一步：{template.next_step_zh}"
        ),
        generated_code=_generate_template_pseudocode(template, spec),
        source_analysis_id=request.source_analysis_id or f"template:{template.id}",
    )


def _render_rule(rule: str, symbol: str) -> str:
    return rule.replace("{symbol}", symbol)


def _generate_template_pseudocode(template: StrategyTemplate, spec: StrategySpec) -> str:
    return "\n".join(
        [
            f"# Dubhe template: {template.id}",
            "# References: " + " / ".join(template.source_projects_zh),
            f"strategy_name = {spec.strategy_name!r}",
            f"asset_universe = {spec.asset_universe!r}",
            f"timeframe = {spec.timeframe!r}",
            f"rebalance_rule = {spec.rebalance_rule!r}",
            f"risk_limits = {spec.risk_limits!r}",
            "entry_rules = [",
            *[f"    {rule!r}," for rule in spec.entry_rules],
            "]",
            "exit_rules = [",
            *[f"    {rule!r}," for rule in spec.exit_rules],
            "]",
            "# Production execution remains behind Dubhe Risk Service.",
        ]
    )
