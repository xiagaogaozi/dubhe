from __future__ import annotations

from .models import OrderIntent, PaperOrder, PaperOrderStatus, RiskStatus
from .risk import evaluate_order_intent


def submit_paper_order(intent: OrderIntent) -> PaperOrder:
    decision = evaluate_order_intent(intent)

    if decision.status == RiskStatus.REJECTED:
        return PaperOrder(
            order_intent_id=intent.id,
            status=PaperOrderStatus.BLOCKED,
            risk_decision=decision,
            message_zh="纸面订单已被风控拦截。",
        )

    return PaperOrder(
        order_intent_id=intent.id,
        status=PaperOrderStatus.ACCEPTED,
        risk_decision=decision,
        message_zh="纸面订单已接受。当前版本不会连接真实券商。",
    )

