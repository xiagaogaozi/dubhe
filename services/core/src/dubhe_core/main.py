from __future__ import annotations

import asyncio

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .analysis import analyze_news
from .backtest import draft_strategy_from_analysis, run_replay_backtest
from .models import (
    AccountLoginRequest,
    AccountRegistrationRequest,
    AuditLogEntry,
    ApprovalActionRequest,
    ApprovalRequest,
    ApprovalStatus,
    BacktestRequest,
    BacktestResult,
    BrokerOrder,
    DeviceRevocation,
    KillSwitchState,
    KillSwitchUpdateRequest,
    NewsAnalysis,
    NewsEvent,
    NewsFeedResponse,
    OrderIntent,
    OrderSide,
    PaperOrder,
    PaperOrderStatus,
    PaperPortfolioSnapshot,
    RiskDecision,
    RiskStatus,
    DeviceRegistrationRequest,
    DeviceSession,
    Market,
    StrategySpec,
    StrategyDraft,
    StrategyDraftRequest,
    StrategyValidationResult,
    SyncEvent,
    UserRole,
    UserRoleUpdateRequest,
    UserSummary,
    WatchlistItem,
    WatchlistUpsertRequest,
    WorkspaceSnapshot,
)
from .news_sources import fetch_news_feed
from .risk import evaluate_order_intent
from .simulation import submit_paper_order
from .store import store
from .strategy import validate_strategy_spec

SYNC_WEBSOCKET_POLL_SECONDS = 0.25

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
    allow_origin_regex=r"https?://(127\.0\.0\.1|localhost)(:\d+)?",
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
            "simulated_paper_broker_adapter",
            "paper_portfolio_ledger",
            "device_registration",
            "workspace_sync_snapshot",
            "watchlist_sync",
            "local_sqlite_persistence",
            "public_news_feed_adapters",
            "licensed_news_api_adapters",
            "strategy_draft_from_news_analysis",
            "deterministic_replay_backtest",
            "approval_requests",
            "kill_switch",
            "device_bearer_token_auth",
            "device_token_revocation",
            "account_password_login",
            "local_mfa_placeholder",
            "role_based_risk_controls",
            "admin_user_role_management",
            "audit_log",
            "workspace_sync_websocket",
        ],
        "live_trading": "disabled_until_risk_approval_flow_exists",
    }


def authenticate_device_token(access_token: str) -> DeviceSession | None:
    session = store.device_session_by_access_token(access_token)
    if session is None:
        return None
    return session


def require_device_session(authorization: str | None = Header(default=None)) -> DeviceSession:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="需要设备访问令牌。")

    session = authenticate_device_token(token)
    if session is None:
        raise HTTPException(status_code=401, detail="设备访问令牌无效或已失效。")
    return session


def require_workspace_access(workspace_id: str, session: DeviceSession) -> None:
    if session.workspace_id != workspace_id:
        raise HTTPException(status_code=403, detail="当前设备无权访问该工作区。")


def require_roles(session: DeviceSession, allowed_roles: set[UserRole]) -> None:
    if session.role not in allowed_roles:
        raise HTTPException(status_code=403, detail="当前账号权限不足。")


def require_risk_manager_session(
    session: DeviceSession = Depends(require_device_session),
) -> DeviceSession:
    require_roles(session, {UserRole.RISK_MANAGER, UserRole.ADMIN})
    return session


def require_admin_session(
    session: DeviceSession = Depends(require_device_session),
) -> DeviceSession:
    require_roles(session, {UserRole.ADMIN})
    return session


@app.post("/v1/auth/devices/register", response_model=DeviceSession)
def register_device_endpoint(request: DeviceRegistrationRequest) -> DeviceSession:
    return store.register_device(request)


@app.post("/v1/auth/accounts/register", response_model=DeviceSession)
def register_account_endpoint(request: AccountRegistrationRequest) -> DeviceSession:
    try:
        return store.register_account(request)
    except ValueError as exc:
        store.append_audit_log(
            action="auth.account_registration_failed",
            target_type="user",
            summary_zh="账号注册失败：账号已存在。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=409, detail="账号已存在，请直接登录。") from exc
    except PermissionError as exc:
        store.append_audit_log(
            action="auth.account_registration_failed",
            target_type="user",
            summary_zh="账号注册失败：MFA 验证码不正确。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=401, detail="MFA 验证码不正确。") from exc


@app.post("/v1/auth/login", response_model=DeviceSession)
def login_account_endpoint(request: AccountLoginRequest) -> DeviceSession:
    try:
        return store.login_account(request)
    except PermissionError as exc:
        store.append_audit_log(
            action="auth.login_failed",
            target_type="user",
            summary_zh="账号登录失败：账号、密码或 MFA 验证码不正确。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=401, detail="账号、密码或 MFA 验证码不正确。") from exc
    except KeyError as exc:
        store.append_audit_log(
            action="auth.login_failed",
            target_type="user",
            summary_zh="账号登录失败：账号工作区不存在。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=404, detail="账号工作区不存在。") from exc


@app.post("/v1/auth/devices/current/revoke", response_model=DeviceRevocation)
def revoke_current_device_endpoint(
    session: DeviceSession = Depends(require_device_session),
) -> DeviceRevocation:
    return store.revoke_device_session(session)


@app.get("/v1/admin/users", response_model=list[UserSummary])
def list_users_endpoint(
    _session: DeviceSession = Depends(require_admin_session),
) -> list[UserSummary]:
    return store.list_users()


@app.post("/v1/admin/users/{user_id}/role", response_model=UserSummary)
def update_user_role_endpoint(
    user_id: str,
    request: UserRoleUpdateRequest,
    session: DeviceSession = Depends(require_admin_session),
) -> UserSummary:
    try:
        return store.update_user_role(user_id, request, session)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="账号不存在。") from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail="不能移除最后一个管理员。") from exc


@app.get("/v1/audit/logs", response_model=list[AuditLogEntry])
def list_audit_logs_endpoint(
    limit: int = Query(default=50, ge=1, le=200),
    _session: DeviceSession = Depends(require_risk_manager_session),
) -> list[AuditLogEntry]:
    return store.list_audit_logs(limit=limit)


@app.get("/v1/workspaces/{workspace_id}/snapshot", response_model=WorkspaceSnapshot)
def workspace_snapshot_endpoint(
    workspace_id: str,
    since_sequence: int = Query(default=0, ge=0),
    session: DeviceSession = Depends(require_device_session),
) -> WorkspaceSnapshot:
    require_workspace_access(workspace_id, session)
    try:
        return store.get_workspace_snapshot(workspace_id, since_sequence=since_sequence)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.put("/v1/workspaces/{workspace_id}/watchlist/{symbol}", response_model=WatchlistItem)
def upsert_watchlist_item_endpoint(
    workspace_id: str,
    symbol: str,
    request: WatchlistUpsertRequest,
    session: DeviceSession = Depends(require_device_session),
) -> WatchlistItem:
    require_workspace_access(workspace_id, session)
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
    session: DeviceSession = Depends(require_device_session),
) -> list[SyncEvent]:
    require_workspace_access(workspace_id, session)
    try:
        return store.list_sync_events(workspace_id, since_sequence=since_sequence)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.websocket("/v1/workspaces/{workspace_id}/sync-events/ws")
async def workspace_sync_events_websocket(
    websocket: WebSocket,
    workspace_id: str,
    access_token: str = Query(min_length=1),
    since_sequence: int = Query(default=0, ge=0),
) -> None:
    session = authenticate_device_token(access_token)
    if session is None or session.workspace_id != workspace_id:
        await websocket.close(code=1008)
        return

    try:
        store.get_workspace_snapshot(workspace_id, since_sequence=since_sequence)
    except KeyError:
        await websocket.close(code=1008)
        return

    await websocket.accept()
    cursor = since_sequence
    try:
        while True:
            events = store.list_sync_events(workspace_id, since_sequence=cursor)
            for event in events:
                await websocket.send_json(event.model_dump(mode="json"))
                cursor = max(cursor, event.sequence)
            await asyncio.sleep(SYNC_WEBSOCKET_POLL_SECONDS)
    except WebSocketDisconnect:
        return


@app.post("/v1/news/analyze", response_model=NewsAnalysis)
def analyze_news_endpoint(event: NewsEvent) -> NewsAnalysis:
    store.add_news_event(event)
    return store.add_analysis(analyze_news(event))


@app.get("/v1/news/feed", response_model=NewsFeedResponse)
def news_feed_endpoint(
    market: Market = Query(default=Market.US),
    symbol: str | None = Query(default=None, min_length=1),
    limit: int = Query(default=8, ge=1, le=20),
    live: bool = Query(default=True),
) -> NewsFeedResponse:
    feed = fetch_news_feed(market=market, symbol=symbol, limit=limit, live=live)
    store.add_news_events(feed.events)
    return feed


@app.get("/v1/news/events", response_model=list[NewsEvent])
def list_news_events_endpoint() -> list[NewsEvent]:
    return store.news_events


@app.get("/v1/news/analyses", response_model=list[NewsAnalysis])
def list_news_analyses_endpoint() -> list[NewsAnalysis]:
    return store.analyses


@app.post("/v1/strategy/spec/validate", response_model=StrategyValidationResult)
def validate_strategy_endpoint(spec: StrategySpec) -> StrategyValidationResult:
    return validate_strategy_spec(spec)


@app.post("/v1/strategy/drafts/from-analysis", response_model=StrategyDraft)
def draft_strategy_from_analysis_endpoint(request: StrategyDraftRequest) -> StrategyDraft:
    return store.add_strategy_draft(draft_strategy_from_analysis(request))


@app.get("/v1/strategy/drafts", response_model=list[StrategyDraft])
def list_strategy_drafts_endpoint() -> list[StrategyDraft]:
    return store.strategy_drafts


@app.post("/v1/backtests/replay", response_model=BacktestResult)
def run_replay_backtest_endpoint(request: BacktestRequest) -> BacktestResult:
    return store.add_backtest_result(run_replay_backtest(request))


@app.get("/v1/backtests", response_model=list[BacktestResult])
def list_backtests_endpoint() -> list[BacktestResult]:
    return store.backtest_results


@app.post("/v1/risk/evaluate", response_model=RiskDecision)
def evaluate_risk_endpoint(
    intent: OrderIntent,
    session: DeviceSession = Depends(require_device_session),
) -> RiskDecision:
    decision = store.add_risk_decision(evaluate_order_intent(intent, store.current_risk_policy()))
    if decision.status == RiskStatus.REQUIRES_APPROVAL:
        store.create_approval_request(decision, intent.created_by)
    store.append_audit_log(
        actor_session=session,
        action="risk.order_evaluated",
        target_type="risk_decision",
        target_id=decision.id,
        summary_zh=f"订单意图已完成风控评估：{decision.status.value}。",
        metadata={
            "order_intent_id": decision.order_intent_id,
            "symbol": intent.symbol,
            "destination": intent.destination.value,
            "notional": decision.notional,
        },
    )
    return decision


@app.get("/v1/risk/decisions", response_model=list[RiskDecision])
def list_risk_decisions_endpoint(
    _session: DeviceSession = Depends(require_device_session),
) -> list[RiskDecision]:
    return store.risk_decisions


@app.get("/v1/approvals", response_model=list[ApprovalRequest])
def list_approval_requests_endpoint(
    status: ApprovalStatus | None = Query(default=None),
    _session: DeviceSession = Depends(require_risk_manager_session),
) -> list[ApprovalRequest]:
    return store.list_approval_requests(status=status)


@app.post("/v1/approvals/{approval_id}/approve", response_model=ApprovalRequest)
def approve_request_endpoint(
    approval_id: str,
    request: ApprovalActionRequest,
    session: DeviceSession = Depends(require_risk_manager_session),
) -> ApprovalRequest:
    try:
        return store.decide_approval(approval_id, ApprovalStatus.APPROVED, request, session)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="审批请求不存在。") from exc


@app.post("/v1/approvals/{approval_id}/reject", response_model=ApprovalRequest)
def reject_request_endpoint(
    approval_id: str,
    request: ApprovalActionRequest,
    session: DeviceSession = Depends(require_risk_manager_session),
) -> ApprovalRequest:
    try:
        return store.decide_approval(approval_id, ApprovalStatus.REJECTED, request, session)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="审批请求不存在。") from exc


@app.get("/v1/risk/kill-switch", response_model=KillSwitchState)
def get_kill_switch_endpoint(
    _session: DeviceSession = Depends(require_risk_manager_session),
) -> KillSwitchState:
    return store.get_kill_switch_state()


@app.post("/v1/risk/kill-switch", response_model=KillSwitchState)
def set_kill_switch_endpoint(
    request: KillSwitchUpdateRequest,
    session: DeviceSession = Depends(require_risk_manager_session),
) -> KillSwitchState:
    return store.set_kill_switch_state(request, session)


@app.post("/v1/simulation/paper-orders", response_model=PaperOrder)
def submit_paper_order_endpoint(
    intent: OrderIntent,
    session: DeviceSession = Depends(require_device_session),
) -> PaperOrder:
    if intent.side == OrderSide.SELL:
        portfolio = store.get_paper_portfolio(intent.account_id)
        held_quantity = 0.0
        for position in portfolio.positions:
            if (
                position.market == intent.market
                and position.symbol == intent.symbol
                and position.currency == intent.currency
            ):
                held_quantity = position.quantity
                break

        if held_quantity + 0.00000001 < intent.quantity:
            decision = evaluate_order_intent(intent, store.current_risk_policy())
            reasons = list(decision.reasons_zh)
            reasons.append(
                f"纸面组合中 {intent.symbol} 可卖数量 {held_quantity:g}，不足以卖出 {intent.quantity:g}。"
            )
            blocked_order = PaperOrder(
                order_intent_id=intent.id,
                status=PaperOrderStatus.BLOCKED,
                risk_decision=decision.model_copy(
                    update={
                        "status": RiskStatus.REJECTED,
                        "allowed_destination": "none",
                        "reasons_zh": reasons,
                    },
                ),
                message_zh="纸面订单已被纸面组合持仓校验拦截。",
            )
            return store.add_paper_order(blocked_order, session)

    return store.add_paper_order(submit_paper_order(intent, store.current_risk_policy()), session)


@app.get("/v1/simulation/paper-orders", response_model=list[PaperOrder])
def list_paper_orders_endpoint(
    _session: DeviceSession = Depends(require_device_session),
) -> list[PaperOrder]:
    return store.paper_orders


@app.get("/v1/simulation/broker-orders", response_model=list[BrokerOrder])
def list_broker_orders_endpoint(
    _session: DeviceSession = Depends(require_device_session),
) -> list[BrokerOrder]:
    return store.broker_orders


@app.get("/v1/simulation/paper-portfolio/{account_id}", response_model=PaperPortfolioSnapshot)
def get_paper_portfolio_endpoint(
    account_id: str,
    _session: DeviceSession = Depends(require_device_session),
) -> PaperPortfolioSnapshot:
    return store.get_paper_portfolio(account_id)
