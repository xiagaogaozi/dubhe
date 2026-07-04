from __future__ import annotations

from typing import Any, Literal
from uuid import uuid4

from .models import (
    DeviceRegistrationRequest,
    DeviceSession,
    NewsAnalysis,
    PaperOrder,
    RiskDecision,
    SyncEntityType,
    SyncEvent,
    UserAccount,
    WatchlistItem,
    WatchlistUpsertRequest,
    Workspace,
    WorkspaceSnapshot,
    utc_now,
)


DEFAULT_WATCHLIST = [
    {"symbol": "NVDA", "name": "英伟达", "market": "US", "notes_zh": "美股 AI 算力龙头"},
    {"symbol": "0700.HK", "name": "腾讯控股", "market": "HK", "notes_zh": "港股互联网核心标的"},
    {"symbol": "600519.SH", "name": "贵州茅台", "market": "A_SHARE", "notes_zh": "A 股消费核心标的"},
    {"symbol": "AAPL", "name": "苹果", "market": "US", "notes_zh": "美股消费电子核心标的"},
]


class InMemoryStore:
    def __init__(self) -> None:
        self.analyses: list[NewsAnalysis] = []
        self.risk_decisions: list[RiskDecision] = []
        self.paper_orders: list[PaperOrder] = []
        self.users_by_account_key: dict[str, UserAccount] = {}
        self.devices: dict[str, DeviceSession] = {}
        self.workspaces_by_user_id: dict[str, Workspace] = {}
        self.watchlists_by_workspace_id: dict[str, list[WatchlistItem]] = {}
        self.sync_events_by_workspace_id: dict[str, list[SyncEvent]] = {}
        self.sync_sequences_by_workspace_id: dict[str, int] = {}

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

    def register_device(self, request: DeviceRegistrationRequest) -> DeviceSession:
        user = self.users_by_account_key.get(request.account_key)
        if user is None:
            user = UserAccount(account_key=request.account_key, display_name=request.account_name)
            self.users_by_account_key[request.account_key] = user
            self._create_workspace_for_user(user)

        workspace = self.workspaces_by_user_id[user.id]
        session = DeviceSession(
            user_id=user.id,
            device_id=f"device_{uuid4().hex}",
            workspace_id=workspace.id,
            access_token=f"local_{uuid4().hex}",
            platform=request.platform,
            device_name=request.device_name,
        )
        self.devices[session.device_id] = session
        return session

    def upsert_watchlist_item(
        self,
        workspace_id: str,
        request: WatchlistUpsertRequest,
    ) -> WatchlistItem:
        self._ensure_workspace_exists(workspace_id)
        watchlist = self.watchlists_by_workspace_id.setdefault(workspace_id, [])
        existing = next((item for item in watchlist if item.symbol == request.symbol), None)

        if existing is None:
            item = WatchlistItem(
                workspace_id=workspace_id,
                symbol=request.symbol,
                name=request.name,
                market=request.market,
                notes_zh=request.notes_zh,
            )
            watchlist.append(item)
            action = "created"
        else:
            existing.name = request.name
            existing.market = request.market
            existing.notes_zh = request.notes_zh
            existing.updated_at = utc_now()
            item = existing
            action = "updated"

        self._append_sync_event(
            workspace_id=workspace_id,
            entity_type=SyncEntityType.WATCHLIST_ITEM,
            entity_id=item.id,
            action=action,
            payload=item.model_dump(mode="json"),
        )
        return item

    def get_workspace_snapshot(
        self,
        workspace_id: str,
        since_sequence: int = 0,
    ) -> WorkspaceSnapshot:
        self._ensure_workspace_exists(workspace_id)
        workspace = self._workspace_by_id(workspace_id)
        events = self.list_sync_events(workspace_id, since_sequence=since_sequence)
        return WorkspaceSnapshot(
            workspace=workspace,
            watchlist=self.watchlists_by_workspace_id.get(workspace_id, []),
            analyses=self.analyses,
            risk_decisions=self.risk_decisions,
            paper_orders=self.paper_orders,
            events=events,
            server_sequence=self.sync_sequences_by_workspace_id.get(workspace_id, 0),
        )

    def list_sync_events(self, workspace_id: str, since_sequence: int = 0) -> list[SyncEvent]:
        self._ensure_workspace_exists(workspace_id)
        return [
            event
            for event in self.sync_events_by_workspace_id.get(workspace_id, [])
            if event.sequence > since_sequence
        ]

    def _create_workspace_for_user(self, user: UserAccount) -> Workspace:
        workspace = Workspace(owner_user_id=user.id, name=f"{user.display_name}的默认工作区")
        self.workspaces_by_user_id[user.id] = workspace
        self.watchlists_by_workspace_id[workspace.id] = []
        self.sync_events_by_workspace_id[workspace.id] = []
        self.sync_sequences_by_workspace_id[workspace.id] = 0
        self._append_sync_event(
            workspace_id=workspace.id,
            entity_type=SyncEntityType.WORKSPACE,
            entity_id=workspace.id,
            action="created",
            payload=workspace.model_dump(mode="json"),
        )
        for item in DEFAULT_WATCHLIST:
            self.upsert_watchlist_item(workspace.id, WatchlistUpsertRequest(**item))
        return workspace

    def _append_sync_event(
        self,
        workspace_id: str,
        entity_type: SyncEntityType,
        entity_id: str,
        action: Literal["created", "updated", "deleted"],
        payload: dict[str, Any],
    ) -> SyncEvent:
        sequence = self.sync_sequences_by_workspace_id.get(workspace_id, 0) + 1
        self.sync_sequences_by_workspace_id[workspace_id] = sequence
        event = SyncEvent(
            workspace_id=workspace_id,
            sequence=sequence,
            entity_type=entity_type,
            entity_id=entity_id,
            action=action,
            payload=payload,
        )
        self.sync_events_by_workspace_id.setdefault(workspace_id, []).append(event)
        return event

    def _workspace_by_id(self, workspace_id: str) -> Workspace:
        for workspace in self.workspaces_by_user_id.values():
            if workspace.id == workspace_id:
                return workspace
        raise KeyError(workspace_id)

    def _ensure_workspace_exists(self, workspace_id: str) -> None:
        self._workspace_by_id(workspace_id)


store = InMemoryStore()
