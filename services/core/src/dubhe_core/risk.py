from __future__ import annotations

from .models import OrderDestination, OrderIntent, RiskDecision, RiskPolicy, RiskStatus


DEFAULT_RISK_POLICY = RiskPolicy()


def estimate_notional(intent: OrderIntent) -> float:
    price = intent.limit_price if intent.limit_price is not None else intent.estimated_price
    return round(intent.quantity * price, 4)


def evaluate_order_intent(
    intent: OrderIntent,
    policy: RiskPolicy = DEFAULT_RISK_POLICY,
) -> RiskDecision:
    reasons: list[str] = []
    notional = estimate_notional(intent)

    if policy.kill_switch_enabled:
        reasons.append("Kill switch 已启用，系统禁止生成新订单。")

    disabled_symbols = {symbol.upper() for symbol in policy.disabled_symbols}
    if intent.symbol in disabled_symbols:
        reasons.append(f"{intent.symbol} 已被当前风控策略禁用。")

    if policy.require_source_refs and not intent.source_refs:
        reasons.append("订单意图缺少新闻、策略版本或回测记录等来源引用。")

    if notional > policy.max_order_notional:
        reasons.append(
            f"订单名义金额 {notional:.2f} 超过单笔上限 {policy.max_order_notional:.2f}。"
        )

    if reasons:
        return RiskDecision(
            order_intent_id=intent.id,
            status=RiskStatus.REJECTED,
            allowed_destination="none",
            notional=notional,
            reasons_zh=reasons,
        )

    if intent.destination == OrderDestination.LIVE and policy.live_requires_human_approval:
        return RiskDecision(
            order_intent_id=intent.id,
            status=RiskStatus.REQUIRES_APPROVAL,
            allowed_destination="live_after_approval",
            notional=notional,
            reasons_zh=["实盘订单必须经过人工审批，AI 或策略不能直接下单。"],
        )

    return RiskDecision(
        order_intent_id=intent.id,
        status=RiskStatus.APPROVED,
        allowed_destination="paper",
        notional=notional,
        reasons_zh=["订单通过纸面交易风控检查。"],
    )
