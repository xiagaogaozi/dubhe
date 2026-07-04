from __future__ import annotations

from .models import OrderIntent, PaperOrder, PaperOrderStatus, RiskPolicy, RiskStatus
from .paper_broker import simulated_paper_broker
from .risk import DEFAULT_RISK_POLICY, evaluate_order_intent


def submit_paper_order(
    intent: OrderIntent,
    policy: RiskPolicy = DEFAULT_RISK_POLICY,
) -> PaperOrder:
    decision = evaluate_order_intent(intent, policy)

    if decision.status == RiskStatus.REJECTED:
        return PaperOrder(
            order_intent_id=intent.id,
            status=PaperOrderStatus.BLOCKED,
            risk_decision=decision,
            message_zh="纸面订单已被风控拦截。",
        )

    paper_order = PaperOrder(
        order_intent_id=intent.id,
        status=PaperOrderStatus.ACCEPTED,
        risk_decision=decision,
        message_zh="纸面订单已通过风控，正在提交模拟券商。",
    )
    broker_order = simulated_paper_broker.submit_order(intent, paper_order.id)
    return PaperOrder(
        id=paper_order.id,
        order_intent_id=intent.id,
        status=PaperOrderStatus.ACCEPTED,
        risk_decision=decision,
        broker_order=broker_order,
        submitted_at=paper_order.submitted_at,
        message_zh="纸面订单已通过模拟券商成交。当前版本不会连接真实券商。",
    )
