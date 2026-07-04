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


class DevicePlatform(str, Enum):
    WINDOWS = "windows"
    MACOS = "macos"
    IOS = "ios"
    ANDROID = "android"


class SyncEntityType(str, Enum):
    WORKSPACE = "workspace"
    WATCHLIST_ITEM = "watchlist_item"
    NEWS_EVENT = "news_event"
    NEWS_ANALYSIS = "news_analysis"
    RISK_DECISION = "risk_decision"
    PAPER_ORDER = "paper_order"


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


class RiskDecision(BaseModel):
    id: str = Field(default_factory=lambda: f"risk_{uuid4().hex}")
    order_intent_id: str
    status: RiskStatus
    allowed_destination: Literal["none", "paper", "live_after_approval"]
    notional: float = Field(ge=0)
    reasons_zh: list[str] = Field(default_factory=list)
    evaluated_at: datetime = Field(default_factory=utc_now)


class PaperOrder(BaseModel):
    id: str = Field(default_factory=lambda: f"paper_{uuid4().hex}")
    order_intent_id: str
    status: PaperOrderStatus
    risk_decision: RiskDecision
    submitted_at: datetime = Field(default_factory=utc_now)
    message_zh: str


class DeviceRegistrationRequest(BaseModel):
    account_key: str = Field(default="local-demo", min_length=3)
    account_name: str = Field(default="本地演示账户", min_length=1)
    device_name: str = Field(min_length=1)
    platform: DevicePlatform


class UserAccount(BaseModel):
    id: str = Field(default_factory=lambda: f"user_{uuid4().hex}")
    account_key: str = Field(min_length=3)
    display_name: str = Field(min_length=1)
    created_at: datetime = Field(default_factory=utc_now)


class DeviceSession(BaseModel):
    user_id: str
    device_id: str
    workspace_id: str
    access_token: str
    platform: DevicePlatform
    device_name: str
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
    paper_orders: list[PaperOrder] = Field(default_factory=list)
    events: list[SyncEvent] = Field(default_factory=list)
    server_sequence: int = 0
