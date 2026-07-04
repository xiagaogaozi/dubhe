from __future__ import annotations

from .models import NewsAnalysis, PaperOrder, RiskDecision


class InMemoryStore:
    def __init__(self) -> None:
        self.analyses: list[NewsAnalysis] = []
        self.risk_decisions: list[RiskDecision] = []
        self.paper_orders: list[PaperOrder] = []

    def add_analysis(self, analysis: NewsAnalysis) -> NewsAnalysis:
        self.analyses.append(analysis)
        return analysis

    def add_risk_decision(self, decision: RiskDecision) -> RiskDecision:
        self.risk_decisions.append(decision)
        return decision

    def add_paper_order(self, order: PaperOrder) -> PaperOrder:
        self.paper_orders.append(order)
        self.risk_decisions.append(order.risk_decision)
        return order


store = InMemoryStore()

