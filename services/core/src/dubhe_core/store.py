from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from threading import RLock
from typing import Any, Literal, TypeVar
from uuid import uuid4

from pydantic import BaseModel

from .models import (
    DeviceRegistrationRequest,
    DeviceSession,
    NewsEvent,
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

ModelT = TypeVar("ModelT", bound=BaseModel)


def default_db_path() -> str:
    configured = os.environ.get("DUBHE_CORE_DB_PATH")
    if configured:
        return configured

    service_root = Path(__file__).resolve().parents[2]
    return str(service_root / "data" / "dubhe-core.sqlite")


class SQLiteStore:
    def __init__(self, db_path: str | Path | None = None) -> None:
        self.db_path = str(db_path or default_db_path())
        if self.db_path != ":memory:":
            Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)

        self._lock = RLock()
        self._connection = sqlite3.connect(self.db_path, check_same_thread=False)
        self._connection.row_factory = sqlite3.Row
        self._initialize_schema()

    @property
    def news_events(self) -> list[NewsEvent]:
        return self._load_payloads("news_events", NewsEvent, "published_at DESC, id")

    @property
    def analyses(self) -> list[NewsAnalysis]:
        return self._load_payloads("news_analyses", NewsAnalysis, "generated_at, id")

    @property
    def risk_decisions(self) -> list[RiskDecision]:
        return self._load_payloads("risk_decisions", RiskDecision, "evaluated_at, id")

    @property
    def paper_orders(self) -> list[PaperOrder]:
        return self._load_payloads("paper_orders", PaperOrder, "submitted_at, id")

    def close(self) -> None:
        with self._lock:
            self._connection.close()

    def add_news_event(self, event: NewsEvent) -> NewsEvent:
        with self._lock:
            self._save_news_event(event)
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.NEWS_EVENT,
                entity_id=event.id,
                payload=event.model_dump(mode="json"),
            )
            self._connection.commit()
            return event

    def add_news_events(self, events: list[NewsEvent]) -> list[NewsEvent]:
        with self._lock:
            for event in events:
                self._save_news_event(event)
                self._append_entity_event_to_all_workspaces(
                    entity_type=SyncEntityType.NEWS_EVENT,
                    entity_id=event.id,
                    payload=event.model_dump(mode="json"),
                )
            self._connection.commit()
            return events

    def add_analysis(self, analysis: NewsAnalysis) -> NewsAnalysis:
        with self._lock:
            self._upsert_payload(
                table="news_analyses",
                model_id=analysis.id,
                payload=analysis,
                timestamp=analysis.generated_at.isoformat(),
            )
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.NEWS_ANALYSIS,
                entity_id=analysis.id,
                payload=analysis.model_dump(mode="json"),
            )
            self._connection.commit()
            return analysis

    def add_risk_decision(self, decision: RiskDecision) -> RiskDecision:
        with self._lock:
            self._save_risk_decision(decision)
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.RISK_DECISION,
                entity_id=decision.id,
                payload=decision.model_dump(mode="json"),
            )
            self._connection.commit()
            return decision

    def add_paper_order(self, order: PaperOrder) -> PaperOrder:
        with self._lock:
            self._save_risk_decision(order.risk_decision)
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.RISK_DECISION,
                entity_id=order.risk_decision.id,
                payload=order.risk_decision.model_dump(mode="json"),
            )
            self._upsert_payload(
                table="paper_orders",
                model_id=order.id,
                payload=order,
                timestamp=order.submitted_at.isoformat(),
            )
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.PAPER_ORDER,
                entity_id=order.id,
                payload=order.model_dump(mode="json"),
            )
            self._connection.commit()
            return order

    def register_device(self, request: DeviceRegistrationRequest) -> DeviceSession:
        with self._lock:
            user = self._user_by_account_key(request.account_key)
            if user is None:
                user = UserAccount(account_key=request.account_key, display_name=request.account_name)
                self._save_user(user)
                workspace = self._create_workspace_for_user(user)
            else:
                workspace = self._workspace_by_user_id(user.id)

            session = DeviceSession(
                user_id=user.id,
                device_id=f"device_{uuid4().hex}",
                workspace_id=workspace.id,
                access_token=f"local_{uuid4().hex}",
                platform=request.platform,
                device_name=request.device_name,
            )
            self._connection.execute(
                """
                INSERT INTO devices (id, user_id, workspace_id, platform, created_at, payload)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    session.device_id,
                    session.user_id,
                    session.workspace_id,
                    session.platform.value,
                    session.created_at.isoformat(),
                    session.model_dump_json(),
                ),
            )
            self._connection.commit()
            return session

    def upsert_watchlist_item(
        self,
        workspace_id: str,
        request: WatchlistUpsertRequest,
    ) -> WatchlistItem:
        with self._lock:
            self._ensure_workspace_exists(workspace_id)
            item = self._upsert_watchlist_item(workspace_id, request)
            self._connection.commit()
            return item

    def get_workspace_snapshot(
        self,
        workspace_id: str,
        since_sequence: int = 0,
    ) -> WorkspaceSnapshot:
        with self._lock:
            workspace = self._workspace_by_id(workspace_id)
            return WorkspaceSnapshot(
                workspace=workspace,
                watchlist=self._watchlist_for_workspace(workspace_id),
                news_events=self.news_events,
                analyses=self.analyses,
                risk_decisions=self.risk_decisions,
                paper_orders=self.paper_orders,
                events=self.list_sync_events(workspace_id, since_sequence=since_sequence),
                server_sequence=self._server_sequence(workspace_id),
            )

    def list_sync_events(self, workspace_id: str, since_sequence: int = 0) -> list[SyncEvent]:
        with self._lock:
            self._ensure_workspace_exists(workspace_id)
            rows = self._connection.execute(
                """
                SELECT payload FROM sync_events
                WHERE workspace_id = ? AND sequence > ?
                ORDER BY sequence
                """,
                (workspace_id, since_sequence),
            ).fetchall()
            return [SyncEvent.model_validate_json(row["payload"]) for row in rows]

    def _initialize_schema(self) -> None:
        with self._lock:
            if self.db_path != ":memory:":
                self._connection.execute("PRAGMA journal_mode=WAL")
            self._connection.execute("PRAGMA foreign_keys=ON")
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    account_key TEXT NOT NULL UNIQUE,
                    display_name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS workspaces (
                    id TEXT PRIMARY KEY,
                    owner_user_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    workspace_id TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS watchlist_items (
                    id TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    symbol TEXT NOT NULL,
                    added_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    UNIQUE(workspace_id, symbol)
                );

                CREATE TABLE IF NOT EXISTS sync_events (
                    id TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    sequence INTEGER NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    UNIQUE(workspace_id, sequence)
                );

                CREATE TABLE IF NOT EXISTS news_analyses (
                    id TEXT PRIMARY KEY,
                    generated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS news_events (
                    id TEXT PRIMARY KEY,
                    provider TEXT NOT NULL,
                    provider_event_id TEXT,
                    published_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS risk_decisions (
                    id TEXT PRIMARY KEY,
                    evaluated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS paper_orders (
                    id TEXT PRIMARY KEY,
                    submitted_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
                CREATE INDEX IF NOT EXISTS idx_workspaces_owner_user_id ON workspaces(owner_user_id);
                CREATE INDEX IF NOT EXISTS idx_watchlist_workspace ON watchlist_items(workspace_id);
                CREATE INDEX IF NOT EXISTS idx_sync_events_workspace_sequence
                    ON sync_events(workspace_id, sequence);
                """
            )
            self._ensure_column("watchlist_items", "added_at", "TEXT NOT NULL DEFAULT ''")
            self._connection.commit()

    def _load_payloads(
        self,
        table: str,
        model_type: type[ModelT],
        order_by: str,
    ) -> list[ModelT]:
        with self._lock:
            rows = self._connection.execute(
                f"SELECT payload FROM {table} ORDER BY {order_by}",
            ).fetchall()
            return [model_type.model_validate_json(row["payload"]) for row in rows]

    def _upsert_payload(
        self,
        table: Literal["news_analyses", "risk_decisions", "paper_orders"],
        model_id: str,
        payload: BaseModel,
        timestamp: str,
    ) -> None:
        timestamp_column = {
            "news_analyses": "generated_at",
            "risk_decisions": "evaluated_at",
            "paper_orders": "submitted_at",
        }[table]
        self._connection.execute(
            f"""
            INSERT OR REPLACE INTO {table} (id, {timestamp_column}, payload)
            VALUES (?, ?, ?)
            """,
            (model_id, timestamp, payload.model_dump_json()),
        )

    def _save_news_event(self, event: NewsEvent) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO news_events
                (id, provider, provider_event_id, published_at, payload)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                event.id,
                event.provider,
                event.provider_event_id,
                event.published_at.isoformat(),
                event.model_dump_json(),
            ),
        )

    def _save_risk_decision(self, decision: RiskDecision) -> None:
        self._upsert_payload(
            table="risk_decisions",
            model_id=decision.id,
            payload=decision,
            timestamp=decision.evaluated_at.isoformat(),
        )

    def _save_user(self, user: UserAccount) -> None:
        self._connection.execute(
            """
            INSERT INTO users (id, account_key, display_name, created_at, payload)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                user.id,
                user.account_key,
                user.display_name,
                user.created_at.isoformat(),
                user.model_dump_json(),
            ),
        )

    def _save_workspace(self, workspace: Workspace) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO workspaces (id, owner_user_id, name, updated_at, payload)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                workspace.id,
                workspace.owner_user_id,
                workspace.name,
                workspace.updated_at.isoformat(),
                workspace.model_dump_json(),
            ),
        )

    def _create_workspace_for_user(self, user: UserAccount) -> Workspace:
        workspace = Workspace(owner_user_id=user.id, name=f"{user.display_name}的默认工作区")
        self._save_workspace(workspace)
        self._append_sync_event(
            workspace_id=workspace.id,
            entity_type=SyncEntityType.WORKSPACE,
            entity_id=workspace.id,
            action="created",
            payload=workspace.model_dump(mode="json"),
        )
        for item in DEFAULT_WATCHLIST:
            self._upsert_watchlist_item(workspace.id, WatchlistUpsertRequest(**item))
        return workspace

    def _upsert_watchlist_item(
        self,
        workspace_id: str,
        request: WatchlistUpsertRequest,
    ) -> WatchlistItem:
        existing = self._watchlist_item_by_symbol(workspace_id, request.symbol)

        if existing is None:
            item = WatchlistItem(
                workspace_id=workspace_id,
                symbol=request.symbol,
                name=request.name,
                market=request.market,
                notes_zh=request.notes_zh,
            )
            action: Literal["created", "updated"] = "created"
        else:
            item = existing.model_copy(
                update={
                    "name": request.name,
                    "market": request.market,
                    "notes_zh": request.notes_zh,
                    "updated_at": utc_now(),
                },
            )
            action = "updated"

        self._connection.execute(
            """
            INSERT OR REPLACE INTO watchlist_items
                (id, workspace_id, symbol, added_at, updated_at, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                item.id,
                item.workspace_id,
                item.symbol,
                item.added_at.isoformat(),
                item.updated_at.isoformat(),
                item.model_dump_json(),
            ),
        )
        self._append_sync_event(
            workspace_id=workspace_id,
            entity_type=SyncEntityType.WATCHLIST_ITEM,
            entity_id=item.id,
            action=action,
            payload=item.model_dump(mode="json"),
        )
        return item

    def _append_sync_event(
        self,
        workspace_id: str,
        entity_type: SyncEntityType,
        entity_id: str,
        action: Literal["created", "updated", "deleted"],
        payload: dict[str, Any],
    ) -> SyncEvent:
        sequence = self._server_sequence(workspace_id) + 1
        event = SyncEvent(
            workspace_id=workspace_id,
            sequence=sequence,
            entity_type=entity_type,
            entity_id=entity_id,
            action=action,
            payload=payload,
        )
        self._connection.execute(
            """
            INSERT INTO sync_events
                (id, workspace_id, sequence, entity_type, entity_id, created_at, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event.id,
                event.workspace_id,
                event.sequence,
                event.entity_type.value,
                event.entity_id,
                event.created_at.isoformat(),
                event.model_dump_json(),
            ),
        )
        return event

    def _append_entity_event_to_all_workspaces(
        self,
        entity_type: SyncEntityType,
        entity_id: str,
        payload: dict[str, Any],
    ) -> None:
        rows = self._connection.execute("SELECT id FROM workspaces ORDER BY id").fetchall()
        for row in rows:
            self._append_sync_event(
                workspace_id=row["id"],
                entity_type=entity_type,
                entity_id=entity_id,
                action="created",
                payload=payload,
            )

    def _user_by_account_key(self, account_key: str) -> UserAccount | None:
        row = self._connection.execute(
            "SELECT payload FROM users WHERE account_key = ?",
            (account_key,),
        ).fetchone()
        if row is None:
            return None
        return UserAccount.model_validate_json(row["payload"])

    def _workspace_by_user_id(self, user_id: str) -> Workspace:
        row = self._connection.execute(
            "SELECT payload FROM workspaces WHERE owner_user_id = ? ORDER BY updated_at DESC LIMIT 1",
            (user_id,),
        ).fetchone()
        if row is None:
            raise KeyError(user_id)
        return Workspace.model_validate_json(row["payload"])

    def _workspace_by_id(self, workspace_id: str) -> Workspace:
        row = self._connection.execute(
            "SELECT payload FROM workspaces WHERE id = ?",
            (workspace_id,),
        ).fetchone()
        if row is None:
            raise KeyError(workspace_id)
        return Workspace.model_validate_json(row["payload"])

    def _watchlist_item_by_symbol(
        self,
        workspace_id: str,
        symbol: str,
    ) -> WatchlistItem | None:
        row = self._connection.execute(
            "SELECT payload FROM watchlist_items WHERE workspace_id = ? AND symbol = ?",
            (workspace_id, symbol),
        ).fetchone()
        if row is None:
            return None
        return WatchlistItem.model_validate_json(row["payload"])

    def _watchlist_for_workspace(self, workspace_id: str) -> list[WatchlistItem]:
        rows = self._connection.execute(
            """
            SELECT payload FROM watchlist_items
            WHERE workspace_id = ?
            ORDER BY added_at, symbol
            """,
            (workspace_id,),
        ).fetchall()
        return [WatchlistItem.model_validate_json(row["payload"]) for row in rows]

    def _server_sequence(self, workspace_id: str) -> int:
        row = self._connection.execute(
            "SELECT COALESCE(MAX(sequence), 0) AS sequence FROM sync_events WHERE workspace_id = ?",
            (workspace_id,),
        ).fetchone()
        return int(row["sequence"])

    def _ensure_workspace_exists(self, workspace_id: str) -> None:
        self._workspace_by_id(workspace_id)

    def _ensure_column(self, table: str, column: str, definition: str) -> None:
        rows = self._connection.execute(f"PRAGMA table_info({table})").fetchall()
        if any(row["name"] == column for row in rows):
            return
        self._connection.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


store = SQLiteStore()
