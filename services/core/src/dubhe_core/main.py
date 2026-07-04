from __future__ import annotations

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .analysis import analyze_news
from .models import (
    NewsAnalysis,
    NewsEvent,
    OrderIntent,
    PaperOrder,
    RiskDecision,
    DeviceRegistrationRequest,
    DeviceSession,
    StrategySpec,
    StrategyValidationResult,
    SyncEvent,
    WatchlistItem,
    WatchlistUpsertRequest,
    WorkspaceSnapshot,
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
            "device_registration",
            "workspace_sync_snapshot",
            "watchlist_sync",
        ],
        "live_trading": "disabled_until_risk_approval_flow_exists",
    }


@app.post("/v1/auth/devices/register", response_model=DeviceSession)
def register_device_endpoint(request: DeviceRegistrationRequest) -> DeviceSession:
    return store.register_device(request)


@app.get("/v1/workspaces/{workspace_id}/snapshot", response_model=WorkspaceSnapshot)
def workspace_snapshot_endpoint(
    workspace_id: str,
    since_sequence: int = Query(default=0, ge=0),
) -> WorkspaceSnapshot:
    try:
        return store.get_workspace_snapshot(workspace_id, since_sequence=since_sequence)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.put("/v1/workspaces/{workspace_id}/watchlist/{symbol}", response_model=WatchlistItem)
def upsert_watchlist_item_endpoint(
    workspace_id: str,
    symbol: str,
    request: WatchlistUpsertRequest,
) -> WatchlistItem:
    if request.symbol != symbol.strip().upper():
        raise HTTPException(status_code=400, detail="路径中的股票代码必须与请求体一致。")
    try:
        return store.upsert_watchlist_item(workspace_id, request)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.get("/v1/workspaces/{workspace_id}/sync-events", response_model=list[SyncEvent])
def list_sync_events_endpoint(
    workspace_id: str,
    since_sequence: int = Query(default=0, ge=0),
) -> list[SyncEvent]:
    try:
        return store.list_sync_events(workspace_id, since_sequence=since_sequence)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


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
