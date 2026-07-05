from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal
from uuid import uuid4

from pydantic import BaseModel, Field, field_validator


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Market(str, Enum):
    A_SHARE = "A_SHARE"
    HK = "HK"
    US = "US"
    GLOBAL = "GLOBAL"


class Sentiment(str, Enum):
    POSITIVE = "positive"
    NEUTRAL = "neutral"
    NEGATIVE = "negative"


class OrderSide(str, Enum):
    BUY = "buy"
    SELL = "sell"


class OrderType(str, Enum):
    MARKET = "market"
    LIMIT = "limit"


class OrderDestination(str, Enum):
    PAPER = "paper"
    LIVE = "live"


class RiskStatus(str, Enum):
    APPROVED = "approved"
    REQUIRES_APPROVAL = "requires_approval"
    REJECTED = "rejected"


class PaperOrderStatus(str, Enum):
    ACCEPTED = "accepted"
    BLOCKED = "blocked"


class BrokerOrderStatus(str, Enum):
    ACCEPTED = "accepted"
    FILLED = "filled"
    REJECTED = "rejected"
    CANCELED = "canceled"


class ApprovalStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class DevicePlatform(str, Enum):
    WINDOWS = "windows"
    MACOS = "macos"
    IOS = "ios"
    ANDROID = "android"


class UserRole(str, Enum):
    USER = "user"
    RISK_MANAGER = "risk_manager"
    ADMIN = "admin"


class SyncEntityType(str, Enum):
    WORKSPACE = "workspace"
    WATCHLIST_ITEM = "watchlist_item"
    NEWS_EVENT = "news_event"
    NEWS_ANALYSIS = "news_analysis"
    ASSISTANT_TURN = "assistant_turn"
    STRATEGY_DRAFT = "strategy_draft"
    BACKTEST_RESULT = "backtest_result"
    RISK_DECISION = "risk_decision"
    APPROVAL_REQUEST = "approval_request"
    KILL_SWITCH = "kill_switch"
    PAPER_ORDER = "paper_order"
    BROKER_ORDER = "broker_order"
    PAPER_PORTFOLIO = "paper_portfolio"


class ProviderStatus(str, Enum):
    OK = "ok"
    SKIPPED = "skipped"
    UNAVAILABLE = "unavailable"


class NewsEvent(BaseModel):
    id: str = Field(default_factory=lambda: f"news_{uuid4().hex}")
    provider: str = Field(min_length=1)
    provider_event_id: str | None = None
    source_name: str = Field(min_length=1)
    market_scope: list[Market] = Field(default_factory=list)
    language: str = "zh-CN"
    title_original: str = Field(min_length=1)
    title_zh: str | None = None
    body_original_ref: str | None = None
    body_zh_ref: str | None = None
    published_at: datetime
    received_at: datetime = Field(default_factory=utc_now)
    url: str | None = None
    tickers: list[str] = Field(default_factory=list)
    entities: list[str] = Field(default_factory=list)
    event_type: str = "unknown"
    authority_score: float = Field(default=0.5, ge=0, le=1)
    duplicate_group_id: str | None = None
    license_flags: list[str] = Field(default_factory=list)

    @field_validator("tickers")
    @classmethod
    def normalize_tickers(cls, tickers: list[str]) -> list[str]:
        return [ticker.strip().upper() for ticker in tickers if ticker.strip()]


class NewsAnalysis(BaseModel):
    id: str = Field(default_factory=lambda: f"analysis_{uuid4().hex}")
    news_event_id: str
    summary_zh: str
    sentiment: Sentiment
    impact_score: float = Field(ge=0, le=1)
    affected_tickers: list[str] = Field(default_factory=list)
    source_refs: list[str] = Field(min_length=1)
    confidence: float = Field(ge=0, le=1)
    generated_at: datetime = Field(default_factory=utc_now)


class NewsProviderStatus(BaseModel):
    provider: str
    status: ProviderStatus
    fetched_count: int = Field(default=0, ge=0)
    message_zh: str


class NewsFeedResponse(BaseModel):
    events: list[NewsEvent] = Field(default_factory=list)
    provider_status: list[NewsProviderStatus] = Field(default_factory=list)
    generated_at: datetime = Field(default_factory=utc_now)


class RuntimeConfigStatus(BaseModel):
    key: str
    label_zh: str
    configured: bool
    required_for: str
    message_zh: str


class NewsAdapterRuntimeStatus(BaseModel):
    provider: str
    label_zh: str
    market_coverage: list[Market] = Field(default_factory=list)
    configured: bool
    enabled: bool
    requires_license: bool
    message_zh: str


class NewsMarketCoverageStatus(BaseModel):
    market: Market
    label_zh: str
    demo_ready: bool
    licensed_source_ready: bool
    production_ready: bool = False
    available_sources_zh: list[str] = Field(default_factory=list)
    missing_sources_zh: list[str] = Field(default_factory=list)
    message_zh: str
    next_step_zh: str


class StorageRuntimeStatus(BaseModel):
    backend: Literal["sqlite"]
    path: str
    persistent: bool
    message_zh: str


class AuthRuntimeStatus(BaseModel):
    mode: Literal["local_dev"]
    mfa_mode: Literal["local_placeholder"]
    message_zh: str


class TradingRuntimeStatus(BaseModel):
    paper_broker_enabled: bool
    live_trading_enabled: bool
    message_zh: str


class LLMRuntimeStatus(BaseModel):
    provider: str
    model: str | None = None
    configured: bool
    enabled: bool
    fallback_available: bool = True
    message_zh: str


class InstallPackageStatus(BaseModel):
    platform: Literal["windows", "macos", "android", "ios"]
    label_zh: str
    artifact_type: str
    available: bool
    local_path: str | None = None
    size_bytes: int = 0
    build_channel_zh: str
    message_zh: str
    next_step_zh: str


class LocalLauncherStatus(BaseModel):
    id: str
    label_zh: str
    description_zh: str
    local_path: str
    available: bool
    message_zh: str
    next_step_zh: str


class ExternalServiceCheck(BaseModel):
    service: str
    label_zh: str
    configured: bool
    live_checked: bool
    status: ProviderStatus
    duration_ms: int = Field(default=0, ge=0)
    message_zh: str
    next_step_zh: str
    checked_at: datetime = Field(default_factory=utc_now)


class ExternalServiceCheckResponse(BaseModel):
    service: str = "dubhe-core"
    language: str = "zh-CN"
    live: bool
    overall_status: Literal["ready", "partial", "action_required"]
    ready_count: int = Field(ge=0)
    total_count: int = Field(ge=0)
    checks: list[ExternalServiceCheck] = Field(default_factory=list)
    message_zh: str
    generated_at: datetime = Field(default_factory=utc_now)


class ProductionReadinessItem(BaseModel):
    id: str
    category_zh: str
    requirement_zh: str
    status: Literal["pass", "warn", "fail"]
    blocking: bool
    evidence_zh: str
    next_step_zh: str


class ProductionReadinessResponse(BaseModel):
    service: str = "dubhe-core"
    language: str = "zh-CN"
    production_ready: bool
    overall_status: Literal["ready", "not_ready"]
    pass_count: int = Field(ge=0)
    warning_count: int = Field(ge=0)
    blocking_count: int = Field(ge=0)
    total_count: int = Field(ge=0)
    message_zh: str
    items: list[ProductionReadinessItem] = Field(default_factory=list)
    generated_at: datetime = Field(default_factory=utc_now)


class SystemStatusResponse(BaseModel):
    service: str = "dubhe-core"
    version: str = "0.1.0"
    language: str = "zh-CN"
    storage: StorageRuntimeStatus
    auth: AuthRuntimeStatus
    config_items: list[RuntimeConfigStatus] = Field(default_factory=list)
    news_adapters: list[NewsAdapterRuntimeStatus] = Field(default_factory=list)
    news_coverage: list[NewsMarketCoverageStatus] = Field(default_factory=list)
    install_packages: list[InstallPackageStatus] = Field(default_factory=list)
    local_launchers: list[LocalLauncherStatus] = Field(default_factory=list)
    llm: LLMRuntimeStatus
    trading: TradingRuntimeStatus
    generated_at: datetime = Field(default_factory=utc_now)


class LocalRuntimeConfigItem(BaseModel):
    key: str
    label_zh: str
    description_zh: str
    group_zh: str | None = None
    placeholder: str | None = None
    setup_hint_zh: str | None = None
    configured: bool
    secret: bool
    source: Literal["local_file", "process_env", "missing"] = "missing"
    masked_value: str | None = None
    restart_required: bool = False


class LocalRuntimeConfigResponse(BaseModel):
    editable: bool
    exists: bool
    path: str
    items: list[LocalRuntimeConfigItem] = Field(default_factory=list)
    message_zh: str
    generated_at: datetime = Field(default_factory=utc_now)


class LocalRuntimeConfigUpdateRequest(BaseModel):
    values: dict[str, str] = Field(default_factory=dict)
    clear_keys: list[str] = Field(default_factory=list)

    @field_validator("values")
    @classmethod
    def reject_multiline_values(cls, values: dict[str, str]) -> dict[str, str]:
        for key, value in values.items():
            if "\n" in key or "\r" in key:
                raise ValueError("配置项名称不能包含换行。")
            if "\n" in value or "\r" in value:
                raise ValueError(f"{key} 的配置值不能包含换行。")
        return values

    @field_validator("clear_keys")
    @classmethod
    def reject_multiline_clear_keys(cls, keys: list[str]) -> list[str]:
        for key in keys:
            if "\n" in key or "\r" in key:
                raise ValueError("配置项名称不能包含换行。")
        return keys


class OnboardingStepStatus(str, Enum):
    COMPLETE = "complete"
    ACTION_REQUIRED = "action_required"
    WARNING = "warning"


class OnboardingStep(BaseModel):
    id: str
    label_zh: str
    status: OnboardingStepStatus
    message_zh: str
    action_zh: str | None = None


class OnboardingChecklistResponse(BaseModel):
    service: str = "dubhe-core"
    language: str = "zh-CN"
    complete_count: int
    total_count: int
    next_action_zh: str
    steps: list[OnboardingStep] = Field(default_factory=list)
    generated_at: datetime = Field(default_factory=utc_now)


class SmokeWorkflowStep(BaseModel):
    name: str
    status: Literal["passed", "failed"]
    duration_ms: int = 0
    message: str = ""
    data: Any | None = None


class SmokeWorkflowReportResponse(BaseModel):
    service: str = "dubhe-core"
    language: str = "zh-CN"
    available: bool
    status: Literal["passed", "failed", "missing"]
    message_zh: str
    generated_at: datetime = Field(default_factory=utc_now)
    core_url: str = ""
    market: str = ""
    symbol: str = ""
    failure: str | None = None
    report_path: str = ""
    artifacts: dict[str, Any] = Field(default_factory=dict)
    steps: list[SmokeWorkflowStep] = Field(default_factory=list)


class StrategySpec(BaseModel):
    strategy_name: str = Field(min_length=1)
    market_scope: list[Market] = Field(min_length=1)
    asset_universe: list[str] = Field(min_length=1)
    entry_rules: list[str] = Field(min_length=1)
    exit_rules: list[str] = Field(min_length=1)
    risk_limits: dict[str, float] = Field(min_length=1)
    timeframe: str = Field(min_length=1)
    rebalance_rule: str = Field(min_length=1)
    data_dependencies: list[str] = Field(default_factory=list)
    broker_permissions: list[str] = Field(default_factory=list)


class StrategyValidationResult(BaseModel):
    valid: bool
    reasons_zh: list[str] = Field(default_factory=list)


class StrategyDraftRequest(BaseModel):
    analysis: NewsAnalysis
    symbol: str = Field(min_length=1)
    market: Market
    max_order_notional: float = Field(default=10_000, gt=0)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, symbol: str) -> str:
        return symbol.strip().upper()


class StrategyDraft(BaseModel):
    id: str = Field(default_factory=lambda: f"strategy_draft_{uuid4().hex}")
    strategy_version_id: str = Field(default_factory=lambda: f"strategy_v_{uuid4().hex}")
    name: str
    spec: StrategySpec
    explanation_zh: str
    generated_code: str
    source_analysis_id: str
    created_at: datetime = Field(default_factory=utc_now)


class BacktestRequest(BaseModel):
    strategy: StrategyDraft
    initial_cash: float = Field(default=100_000, gt=0)
    replay_scenario: str = Field(default="golden_news_sentiment_v1", min_length=1)


class BacktestPoint(BaseModel):
    date: str
    equity: float = Field(ge=0)
    benchmark: float = Field(ge=0)


class BacktestResult(BaseModel):
    id: str = Field(default_factory=lambda: f"backtest_{uuid4().hex}")
    strategy_version_id: str
    replay_scenario: str
    symbol: str
    market: Market
    initial_cash: float = Field(gt=0)
    final_equity: float = Field(ge=0)
    total_return: float
    benchmark_return: float
    max_drawdown: float = Field(ge=0)
    win_rate: float = Field(ge=0, le=1)
    trade_count: int = Field(ge=0)
    risk_notes_zh: list[str] = Field(default_factory=list)
    equity_curve: list[BacktestPoint] = Field(default_factory=list)
    generated_at: datetime = Field(default_factory=utc_now)


class AssistantCitation(BaseModel):
    label_zh: str = Field(min_length=1)
    ref: str = Field(min_length=1)


class AssistantContext(BaseModel):
    news_event: NewsEvent | None = None
    analysis: NewsAnalysis | None = None
    strategy: StrategyDraft | None = None
    backtest: BacktestResult | None = None


class AssistantChatRequest(BaseModel):
    question_zh: str = Field(min_length=1, max_length=1200)
    context: AssistantContext = Field(default_factory=AssistantContext)


class AssistantChatResponse(BaseModel):
    id: str = Field(default_factory=lambda: f"assistant_{uuid4().hex}")
    answer_zh: str
    citations: list[AssistantCitation] = Field(default_factory=list)
    suggested_actions_zh: list[str] = Field(default_factory=list)
    safety_notes_zh: list[str] = Field(default_factory=list)
    model_provider: str = "deterministic"
    model_name: str | None = None
    fallback_used: bool = True
    generated_at: datetime = Field(default_factory=utc_now)


class AssistantConversationTurn(BaseModel):
    id: str = Field(default_factory=lambda: f"assistant_turn_{uuid4().hex}")
    workspace_id: str = Field(min_length=1)
    question_zh: str = Field(min_length=1)
    answer_zh: str = Field(min_length=1)
    citations: list[AssistantCitation] = Field(default_factory=list)
    suggested_actions_zh: list[str] = Field(default_factory=list)
    safety_notes_zh: list[str] = Field(default_factory=list)
    model_provider: str = "deterministic"
    model_name: str | None = None
    fallback_used: bool = True
    context_refs: list[str] = Field(default_factory=list)
    created_by_user_id: str | None = None
    created_by_device_id: str | None = None
    generated_at: datetime = Field(default_factory=utc_now)


class OrderIntent(BaseModel):
    id: str = Field(default_factory=lambda: f"intent_{uuid4().hex}")
    account_id: str = Field(min_length=1)
    strategy_version_id: str = Field(min_length=1)
    market: Market
    symbol: str = Field(min_length=1)
    side: OrderSide
    order_type: OrderType = OrderType.MARKET
    quantity: float = Field(gt=0)
    estimated_price: float = Field(gt=0)
    limit_price: float | None = Field(default=None, gt=0)
    currency: str = Field(min_length=3, max_length=3)
    created_by: Literal["ai", "strategy", "user"]
    destination: OrderDestination = OrderDestination.PAPER
    rationale_zh: str = Field(min_length=1)
    source_refs: list[str] = Field(default_factory=list)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, symbol: str) -> str:
        return symbol.strip().upper()

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, currency: str) -> str:
        return currency.strip().upper()


class RiskPolicy(BaseModel):
    max_order_notional: float = Field(default=100_000, gt=0)
    require_source_refs: bool = True
    live_requires_human_approval: bool = True
    disabled_symbols: list[str] = Field(default_factory=list)
    kill_switch_enabled: bool = False


class RiskDecision(BaseModel):
    id: str = Field(default_factory=lambda: f"risk_{uuid4().hex}")
    order_intent_id: str
    status: RiskStatus
    allowed_destination: Literal["none", "paper", "live_after_approval"]
    notional: float = Field(ge=0)
    reasons_zh: list[str] = Field(default_factory=list)
    evaluated_at: datetime = Field(default_factory=utc_now)


class BrokerFill(BaseModel):
    id: str = Field(default_factory=lambda: f"fill_{uuid4().hex}")
    broker_order_id: str
    symbol: str
    side: OrderSide
    quantity: float = Field(gt=0)
    price: float = Field(gt=0)
    notional: float = Field(ge=0)
    commission: float = Field(default=0, ge=0)
    filled_at: datetime = Field(default_factory=utc_now)


class BrokerOrder(BaseModel):
    id: str = Field(default_factory=lambda: f"broker_order_{uuid4().hex}")
    paper_order_id: str
    order_intent_id: str
    adapter: str = "simulated_paper"
    broker_account_id: str
    market: Market
    symbol: str
    side: OrderSide
    quantity: float = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    status: BrokerOrderStatus
    filled_quantity: float = Field(default=0, ge=0)
    avg_fill_price: float | None = Field(default=None, gt=0)
    submitted_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)
    fills: list[BrokerFill] = Field(default_factory=list)
    message_zh: str
    raw_response: dict[str, Any] = Field(default_factory=dict)


class PaperOrder(BaseModel):
    id: str = Field(default_factory=lambda: f"paper_{uuid4().hex}")
    order_intent_id: str
    status: PaperOrderStatus
    risk_decision: RiskDecision
    broker_order: BrokerOrder | None = None
    submitted_at: datetime = Field(default_factory=utc_now)
    message_zh: str


class PaperPortfolioPosition(BaseModel):
    market: Market
    symbol: str = Field(min_length=1)
    currency: str = Field(min_length=3, max_length=3)
    quantity: float = 0
    avg_cost: float = Field(default=0, ge=0)
    last_price: float = Field(default=0, ge=0)
    market_value: float = 0
    unrealized_pnl: float = 0
    updated_at: datetime = Field(default_factory=utc_now)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, symbol: str) -> str:
        return symbol.strip().upper()

    @field_validator("currency")
    @classmethod
    def normalize_position_currency(cls, currency: str) -> str:
        return currency.strip().upper()


class PaperPortfolioSnapshot(BaseModel):
    account_id: str = Field(min_length=1)
    cash_by_currency: dict[str, float] = Field(default_factory=dict)
    equity_by_currency: dict[str, float] = Field(default_factory=dict)
    realized_pnl_by_currency: dict[str, float] = Field(default_factory=dict)
    positions: list[PaperPortfolioPosition] = Field(default_factory=list)
    updated_at: datetime = Field(default_factory=utc_now)


class ApprovalRequest(BaseModel):
    id: str = Field(default_factory=lambda: f"approval_{uuid4().hex}")
    order_intent_id: str
    risk_decision: RiskDecision
    status: ApprovalStatus = ApprovalStatus.PENDING
    requested_by: Literal["ai", "strategy", "user"] = "ai"
    decided_by: str | None = None
    decision_comment_zh: str | None = None
    created_at: datetime = Field(default_factory=utc_now)
    decided_at: datetime | None = None
    message_zh: str = "实盘订单需要人工审批。"


class ApprovalActionRequest(BaseModel):
    decided_by: str = Field(default="local-demo-user", min_length=1)
    decision_comment_zh: str | None = None


class KillSwitchState(BaseModel):
    enabled: bool = False
    reason_zh: str = "未启用 kill switch。"
    updated_by: str = "system"
    updated_at: datetime = Field(default_factory=utc_now)


class KillSwitchUpdateRequest(BaseModel):
    enabled: bool
    reason_zh: str = Field(min_length=1)
    updated_by: str = Field(default="local-demo-user", min_length=1)


class DeviceRegistrationRequest(BaseModel):
    account_key: str = Field(default="local-demo", min_length=3)
    account_name: str = Field(default="本地演示账户", min_length=1)
    device_name: str = Field(min_length=1)
    platform: DevicePlatform


class AccountRegistrationRequest(BaseModel):
    account_key: str = Field(min_length=3)
    account_name: str = Field(min_length=1)
    password: str = Field(min_length=8)
    mfa_code: str = Field(default="000000", min_length=6, max_length=6)
    device_name: str = Field(min_length=1)
    platform: DevicePlatform


class AccountLoginRequest(BaseModel):
    account_key: str = Field(min_length=3)
    password: str = Field(min_length=8)
    mfa_code: str = Field(min_length=6, max_length=6)
    device_name: str = Field(min_length=1)
    platform: DevicePlatform


class UserAccount(BaseModel):
    id: str = Field(default_factory=lambda: f"user_{uuid4().hex}")
    account_key: str = Field(min_length=3)
    display_name: str = Field(min_length=1)
    role: UserRole = UserRole.USER
    password_hash: str | None = None
    mfa_enabled: bool = True
    created_at: datetime = Field(default_factory=utc_now)


class UserSummary(BaseModel):
    id: str
    account_key: str
    display_name: str
    role: UserRole
    mfa_enabled: bool
    created_at: datetime


class UserRoleUpdateRequest(BaseModel):
    role: UserRole
    reason_zh: str = Field(min_length=1)


class DeviceSession(BaseModel):
    user_id: str
    device_id: str
    workspace_id: str
    access_token: str
    role: UserRole = UserRole.USER
    platform: DevicePlatform
    device_name: str
    created_at: datetime = Field(default_factory=utc_now)


class DeviceRevocation(BaseModel):
    device_id: str
    revoked: bool = True
    revoked_at: datetime = Field(default_factory=utc_now)
    message_zh: str = "设备访问令牌已撤销。"


class AuditLogEntry(BaseModel):
    id: str = Field(default_factory=lambda: f"audit_{uuid4().hex}")
    actor_user_id: str | None = None
    actor_device_id: str | None = None
    actor_role: UserRole | None = None
    action: str = Field(min_length=1)
    target_type: str = Field(min_length=1)
    target_id: str | None = None
    summary_zh: str = Field(min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=utc_now)


class Workspace(BaseModel):
    id: str = Field(default_factory=lambda: f"workspace_{uuid4().hex}")
    owner_user_id: str
    name: str = Field(min_length=1)
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class WatchlistItem(BaseModel):
    id: str = Field(default_factory=lambda: f"watch_{uuid4().hex}")
    workspace_id: str = Field(min_length=1)
    symbol: str = Field(min_length=1)
    name: str = Field(min_length=1)
    market: Market
    notes_zh: str | None = None
    added_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    @field_validator("symbol")
    @classmethod
    def normalize_watch_symbol(cls, symbol: str) -> str:
        return symbol.strip().upper()


class WatchlistUpsertRequest(BaseModel):
    symbol: str = Field(min_length=1)
    name: str = Field(min_length=1)
    market: Market
    notes_zh: str | None = None

    @field_validator("symbol")
    @classmethod
    def normalize_watch_symbol(cls, symbol: str) -> str:
        return symbol.strip().upper()


class SyncEvent(BaseModel):
    id: str = Field(default_factory=lambda: f"sync_{uuid4().hex}")
    workspace_id: str
    sequence: int = Field(ge=1)
    entity_type: SyncEntityType
    entity_id: str
    action: Literal["created", "updated", "deleted"]
    payload: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=utc_now)


class WorkspaceSnapshot(BaseModel):
    workspace: Workspace
    watchlist: list[WatchlistItem] = Field(default_factory=list)
    news_events: list[NewsEvent] = Field(default_factory=list)
    analyses: list[NewsAnalysis] = Field(default_factory=list)
    risk_decisions: list[RiskDecision] = Field(default_factory=list)
    approval_requests: list[ApprovalRequest] = Field(default_factory=list)
    paper_orders: list[PaperOrder] = Field(default_factory=list)
    broker_orders: list[BrokerOrder] = Field(default_factory=list)
    paper_portfolios: list[PaperPortfolioSnapshot] = Field(default_factory=list)
    strategy_drafts: list[StrategyDraft] = Field(default_factory=list)
    backtest_results: list[BacktestResult] = Field(default_factory=list)
    assistant_turns: list[AssistantConversationTurn] = Field(default_factory=list)
    events: list[SyncEvent] = Field(default_factory=list)
    server_sequence: int = 0
