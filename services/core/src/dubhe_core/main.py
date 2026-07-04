from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .analysis import analyze_news
from .models import (
    NewsAnalysis,
    NewsEvent,
    OrderIntent,
    PaperOrder,
    RiskDecision,
    StrategySpec,
    StrategyValidationResult,
)
from .risk import evaluate_order_intent
from .simulation import submit_paper_order
from .store import store
from .strategy import validate_strategy_spec

app = FastAPI(
    title="Dubhe Core",
    version="0.1.0",
    description="中文优先的 AI 投资研究与受控量化交易后端 API。",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://127.0.0.1:3000",
        "http://localhost:3000",
        "http://127.0.0.1:5173",
        "http://localhost:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "dubhe-core"}


@app.get("/v1/capabilities")
def capabilities() -> dict[str, object]:
    return {
        "language": "zh-CN",
        "markets": ["A_SHARE", "HK", "US", "GLOBAL"],
        "features": [
            "news_analysis_mock",
            "strategy_spec_validation",
            "risk_gate",
            "paper_order_mock",
        ],
        "live_trading": "disabled_until_risk_approval_flow_exists",
    }


@app.post("/v1/news/analyze", response_model=NewsAnalysis)
def analyze_news_endpoint(event: NewsEvent) -> NewsAnalysis:
    return store.add_analysis(analyze_news(event))


@app.get("/v1/news/analyses", response_model=list[NewsAnalysis])
def list_news_analyses_endpoint() -> list[NewsAnalysis]:
    return store.analyses


@app.post("/v1/strategy/spec/validate", response_model=StrategyValidationResult)
def validate_strategy_endpoint(spec: StrategySpec) -> StrategyValidationResult:
    return validate_strategy_spec(spec)


@app.post("/v1/risk/evaluate", response_model=RiskDecision)
def evaluate_risk_endpoint(intent: OrderIntent) -> RiskDecision:
    return store.add_risk_decision(evaluate_order_intent(intent))


@app.get("/v1/risk/decisions", response_model=list[RiskDecision])
def list_risk_decisions_endpoint() -> list[RiskDecision]:
    return store.risk_decisions


@app.post("/v1/simulation/paper-orders", response_model=PaperOrder)
def submit_paper_order_endpoint(intent: OrderIntent) -> PaperOrder:
    return store.add_paper_order(submit_paper_order(intent))


@app.get("/v1/simulation/paper-orders", response_model=list[PaperOrder])
def list_paper_orders_endpoint() -> list[PaperOrder]:
    return store.paper_orders
