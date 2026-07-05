from __future__ import annotations

import hmac
import hashlib
import os
import secrets
import sqlite3
from pathlib import Path
from threading import RLock
from typing import Any, Literal, TypeVar
from uuid import uuid4

from pydantic import BaseModel

from .models import (
    AccountLoginRequest,
    AccountRegistrationRequest,
    AssistantConversationTurn,
    AuditLogEntry,
    ApprovalActionRequest,
    ApprovalRequest,
    ApprovalStatus,
    DeviceRegistrationRequest,
    DeviceRevocation,
    DeviceSession,
    DevicePlatform,
    BacktestResult,
    BrokerOrder,
    KillSwitchState,
    KillSwitchUpdateRequest,
    NewsEvent,
    NewsAnalysis,
    PaperOrder,
    PaperPortfolioPosition,
    PaperPortfolioSnapshot,
    RiskDecision,
    RiskPolicy,
    StrategyDraft,
    SyncEntityType,
    SyncEvent,
    UserAccount,
    UserRole,
    UserRoleUpdateRequest,
    UserSummary,
    WatchlistItem,
    WatchlistUpsertRequest,
    Workspace,
    WorkspaceSnapshot,
    utc_now,
)


DEFAULT_WATCHLIST = [
    {"symbol": "NVDA", "name": "英伟达", "market": "US", "notes_zh": "美股 AI 算力龙头"},
    {"symbol": "0700.HK", "name": "腾讯控股", "market": "HK", "notes_zh": "港股互联网核心标的"},
    {
        "symbol": "600519.SH",
        "name": "贵州茅台",
        "market": "A_SHARE",
        "notes_zh": "A 股消费核心标的",
    },
    {"symbol": "AAPL", "name": "苹果", "market": "US", "notes_zh": "美股消费电子核心标的"},
]
DEFAULT_PAPER_CASH_BY_CURRENCY = {
    "USD": 100_000.0,
    "HKD": 1_000_000.0,
    "CNY": 1_000_000.0,
}

ModelT = TypeVar("ModelT", bound=BaseModel)
PASSWORD_HASH_ALGORITHM = "pbkdf2_sha256"
PASSWORD_HASH_ITERATIONS = 120_000
LOCAL_MFA_CODE = os.environ.get("DUBHE_LOCAL_MFA_CODE", "000000")


def hash_access_token(access_token: str) -> str:
    return hashlib.sha256(access_token.encode("utf-8")).hexdigest()


def hash_password(password: str, salt: str | None = None) -> str:
    actual_salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        actual_salt.encode("utf-8"),
        PASSWORD_HASH_ITERATIONS,
    ).hex()
    return f"{PASSWORD_HASH_ALGORITHM}${PASSWORD_HASH_ITERATIONS}${actual_salt}${digest}"


def verify_password(password: str, stored_hash: str | None) -> bool:
    if not stored_hash:
        return False
    try:
        algorithm, iterations, salt, expected = stored_hash.split("$", 3)
    except ValueError:
        return False
    if algorithm != PASSWORD_HASH_ALGORITHM:
        return False
    try:
        iteration_count = int(iterations)
    except ValueError:
        return False
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        iteration_count,
    ).hex()
    return hmac.compare_digest(digest, expected)


def verify_local_mfa_code(mfa_code: str) -> bool:
    return hmac.compare_digest(mfa_code, LOCAL_MFA_CODE)


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

    @property
    def broker_orders(self) -> list[BrokerOrder]:
        return self._load_payloads("broker_orders", BrokerOrder, "submitted_at, id")

    @property
    def paper_portfolios(self) -> list[PaperPortfolioSnapshot]:
        return self._load_payloads(
            "paper_portfolios", PaperPortfolioSnapshot, "updated_at DESC, account_id"
        )

    @property
    def strategy_drafts(self) -> list[StrategyDraft]:
        return self._load_payloads("strategy_drafts", StrategyDraft, "created_at DESC, id")

    @property
    def backtest_results(self) -> list[BacktestResult]:
        return self._load_payloads("backtest_results", BacktestResult, "generated_at DESC, id")

    @property
    def approval_requests(self) -> list[ApprovalRequest]:
        return self._load_payloads("approval_requests", ApprovalRequest, "created_at DESC, id")

    @property
    def audit_logs(self) -> list[AuditLogEntry]:
        return self._load_payloads("audit_logs", AuditLogEntry, "created_at DESC, id DESC")

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

    def create_approval_request(
        self,
        decision: RiskDecision,
        requested_by: Literal["ai", "strategy", "user"],
    ) -> ApprovalRequest:
        with self._lock:
            existing = self._approval_by_order_intent_id(decision.order_intent_id)
            if existing is not None and existing.status == ApprovalStatus.PENDING:
                return existing
            approval = ApprovalRequest(
                order_intent_id=decision.order_intent_id,
                risk_decision=decision,
                requested_by=requested_by,
            )
            self._save_approval_request(approval)
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.APPROVAL_REQUEST,
                entity_id=approval.id,
                payload=approval.model_dump(mode="json"),
            )
            self._connection.commit()
            return approval

    def decide_approval(
        self,
        approval_id: str,
        status: ApprovalStatus,
        request: ApprovalActionRequest,
        actor_session: DeviceSession | None = None,
    ) -> ApprovalRequest:
        with self._lock:
            approval = self._approval_by_id(approval_id)
            if approval.status != ApprovalStatus.PENDING:
                return approval
            decided = approval.model_copy(
                update={
                    "status": status,
                    "decided_by": request.decided_by,
                    "decision_comment_zh": request.decision_comment_zh,
                    "decided_at": utc_now(),
                    "message_zh": "审批已通过。"
                    if status == ApprovalStatus.APPROVED
                    else "审批已拒绝。",
                },
            )
            self._save_approval_request(decided)
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.APPROVAL_REQUEST,
                entity_id=decided.id,
                action="updated",
                payload=decided.model_dump(mode="json"),
            )
            self._append_audit_log(
                actor_session=actor_session,
                action=f"approval.{status.value}",
                target_type="approval_request",
                target_id=decided.id,
                summary_zh=f"审批请求已{'通过' if status == ApprovalStatus.APPROVED else '拒绝'}。",
                metadata={
                    "order_intent_id": decided.order_intent_id,
                    "decided_by": request.decided_by,
                },
            )
            self._connection.commit()
            return decided

    def list_approval_requests(
        self,
        status: ApprovalStatus | None = None,
    ) -> list[ApprovalRequest]:
        approvals = self.approval_requests
        if status is None:
            return approvals
        return [approval for approval in approvals if approval.status == status]

    def get_kill_switch_state(self) -> KillSwitchState:
        with self._lock:
            row = self._connection.execute(
                "SELECT payload FROM kill_switch_state WHERE id = 'global'",
            ).fetchone()
            if row is None:
                return KillSwitchState()
            return KillSwitchState.model_validate_json(row["payload"])

    def set_kill_switch_state(
        self,
        request: KillSwitchUpdateRequest,
        actor_session: DeviceSession | None = None,
    ) -> KillSwitchState:
        with self._lock:
            state = KillSwitchState(
                enabled=request.enabled,
                reason_zh=request.reason_zh,
                updated_by=request.updated_by,
            )
            self._save_kill_switch_state(state)
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.KILL_SWITCH,
                entity_id="global",
                action="updated",
                payload=state.model_dump(mode="json"),
            )
            self._append_audit_log(
                actor_session=actor_session,
                action="risk.kill_switch_updated",
                target_type="kill_switch",
                target_id="global",
                summary_zh="Kill switch 已更新。",
                metadata={
                    "enabled": state.enabled,
                    "updated_by": request.updated_by,
                    "reason_zh": request.reason_zh,
                },
            )
            self._connection.commit()
            return state

    def current_risk_policy(self) -> RiskPolicy:
        return RiskPolicy(kill_switch_enabled=self.get_kill_switch_state().enabled)

    def add_paper_order(
        self,
        order: PaperOrder,
        actor_session: DeviceSession | None = None,
    ) -> PaperOrder:
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
            if order.broker_order is not None:
                self._upsert_payload(
                    table="broker_orders",
                    model_id=order.broker_order.id,
                    payload=order.broker_order,
                    timestamp=order.broker_order.submitted_at.isoformat(),
                )
                self._append_entity_event_to_all_workspaces(
                    entity_type=SyncEntityType.BROKER_ORDER,
                    entity_id=order.broker_order.id,
                    payload=order.broker_order.model_dump(mode="json"),
                )
                portfolio = self._apply_broker_order_to_portfolio(order.broker_order)
                self._append_entity_event_to_all_workspaces(
                    entity_type=SyncEntityType.PAPER_PORTFOLIO,
                    entity_id=portfolio.account_id,
                    action="updated",
                    payload=portfolio.model_dump(mode="json"),
                )
            self._append_audit_log(
                actor_session=actor_session,
                action="simulation.paper_order_submitted",
                target_type="paper_order",
                target_id=order.id,
                summary_zh=order.message_zh,
                metadata={
                    "status": order.status.value,
                    "order_intent_id": order.order_intent_id,
                    "broker_order_id": order.broker_order.id if order.broker_order else None,
                },
            )
            self._connection.commit()
            return order

    def get_paper_portfolio(self, account_id: str) -> PaperPortfolioSnapshot:
        with self._lock:
            portfolio = self._paper_portfolio_by_account_id(account_id)
            if portfolio is None:
                portfolio = self._default_paper_portfolio(account_id)
                self._save_paper_portfolio(portfolio)
                self._append_entity_event_to_all_workspaces(
                    entity_type=SyncEntityType.PAPER_PORTFOLIO,
                    entity_id=portfolio.account_id,
                    payload=portfolio.model_dump(mode="json"),
                )
                self._connection.commit()
            return portfolio

    def add_strategy_draft(self, draft: StrategyDraft) -> StrategyDraft:
        with self._lock:
            self._upsert_payload(
                table="strategy_drafts",
                model_id=draft.id,
                payload=draft,
                timestamp=draft.created_at.isoformat(),
            )
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.STRATEGY_DRAFT,
                entity_id=draft.id,
                payload=draft.model_dump(mode="json"),
            )
            self._connection.commit()
            return draft

    def add_backtest_result(self, result: BacktestResult) -> BacktestResult:
        with self._lock:
            self._upsert_payload(
                table="backtest_results",
                model_id=result.id,
                payload=result,
                timestamp=result.generated_at.isoformat(),
            )
            self._append_entity_event_to_all_workspaces(
                entity_type=SyncEntityType.BACKTEST_RESULT,
                entity_id=result.id,
                payload=result.model_dump(mode="json"),
            )
            self._connection.commit()
            return result

    def add_assistant_turn(self, turn: AssistantConversationTurn) -> AssistantConversationTurn:
        with self._lock:
            self._ensure_workspace_exists(turn.workspace_id)
            self._save_assistant_turn(turn)
            self._append_sync_event(
                workspace_id=turn.workspace_id,
                entity_type=SyncEntityType.ASSISTANT_TURN,
                entity_id=turn.id,
                action="created",
                payload=turn.model_dump(mode="json"),
            )
            self._connection.commit()
            return turn

    def list_assistant_turns(
        self,
        workspace_id: str,
        limit: int = 20,
    ) -> list[AssistantConversationTurn]:
        with self._lock:
            self._ensure_workspace_exists(workspace_id)
            rows = self._connection.execute(
                """
                SELECT payload FROM assistant_turns
                WHERE workspace_id = ?
                ORDER BY generated_at DESC, id DESC
                LIMIT ?
                """,
                (workspace_id, limit),
            ).fetchall()
            return [
                AssistantConversationTurn.model_validate_json(row["payload"])
                for row in reversed(rows)
            ]

    def register_device(self, request: DeviceRegistrationRequest) -> DeviceSession:
        with self._lock:
            user = self._user_by_account_key(request.account_key)
            if user is None:
                user = UserAccount(
                    account_key=request.account_key,
                    display_name=request.account_name,
                    role=UserRole.ADMIN,
                    mfa_enabled=False,
                )
                self._save_user(user)
                workspace = self._create_workspace_for_user(user)
            else:
                workspace = self._workspace_by_user_id(user.id)

            session = self._create_device_session(
                user, workspace.id, request.device_name, request.platform
            )
            self._append_audit_log(
                actor_session=session,
                action="auth.device_registered",
                target_type="device",
                target_id=session.device_id,
                summary_zh="开发级设备会话已创建。",
                metadata={
                    "account_key": user.account_key,
                    "platform": request.platform.value,
                },
            )
            self._connection.commit()
            return session

    def register_account(self, request: AccountRegistrationRequest) -> DeviceSession:
        with self._lock:
            existing_user = self._user_by_account_key(request.account_key)
            is_claiming_existing = existing_user is not None
            if existing_user is not None and existing_user.password_hash is not None:
                raise ValueError("account_exists")
            if not verify_local_mfa_code(request.mfa_code):
                raise PermissionError("invalid_mfa")

            if existing_user is None:
                user = UserAccount(
                    account_key=request.account_key,
                    display_name=request.account_name,
                    role=UserRole.ADMIN if self._user_count() == 0 else UserRole.USER,
                    password_hash=hash_password(request.password),
                    mfa_enabled=True,
                )
                self._save_user(user)
                workspace = self._create_workspace_for_user(user)
            else:
                user = existing_user.model_copy(
                    update={
                        "display_name": request.account_name,
                        "password_hash": hash_password(request.password),
                        "mfa_enabled": True,
                    },
                )
                self._save_user(user)
                workspace = self._workspace_by_user_id(user.id)
            session = self._create_device_session(
                user, workspace.id, request.device_name, request.platform
            )
            self._append_audit_log(
                actor_session=session,
                action="auth.account_claimed"
                if is_claiming_existing
                else "auth.account_registered",
                target_type="user",
                target_id=user.id,
                summary_zh="账号已接管并启用密码登录。"
                if is_claiming_existing
                else "本地账号已创建。",
                metadata={
                    "account_key": user.account_key,
                    "role": user.role.value,
                    "platform": request.platform.value,
                },
            )
            self._connection.commit()
            return session

    def login_account(self, request: AccountLoginRequest) -> DeviceSession:
        with self._lock:
            user = self._user_by_account_key(request.account_key)
            if user is None or not verify_password(request.password, user.password_hash):
                raise PermissionError("invalid_credentials")
            if user.mfa_enabled and not verify_local_mfa_code(request.mfa_code):
                raise PermissionError("invalid_mfa")

            workspace = self._workspace_by_user_id(user.id)
            session = self._create_device_session(
                user, workspace.id, request.device_name, request.platform
            )
            self._append_audit_log(
                actor_session=session,
                action="auth.login_succeeded",
                target_type="user",
                target_id=user.id,
                summary_zh="账号登录成功。",
                metadata={
                    "account_key": user.account_key,
                    "platform": request.platform.value,
                },
            )
            self._connection.commit()
            return session

    def list_users(self) -> list[UserSummary]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT payload FROM users ORDER BY account_key",
            ).fetchall()
            return [
                self._user_summary(UserAccount.model_validate_json(row["payload"])) for row in rows
            ]

    def update_user_role(
        self,
        user_id: str,
        request: UserRoleUpdateRequest,
        actor_session: DeviceSession,
    ) -> UserSummary:
        with self._lock:
            user = self._user_by_id(user_id)
            if (
                user.role == UserRole.ADMIN
                and request.role != UserRole.ADMIN
                and self._admin_count() <= 1
            ):
                raise ValueError("last_admin")
            updated_user = user.model_copy(update={"role": request.role})
            self._save_user(updated_user)
            self._append_audit_log(
                actor_session=actor_session,
                action="admin.user_role_updated",
                target_type="user",
                target_id=updated_user.id,
                summary_zh=f"账号 {updated_user.account_key} 的角色已更新为 {request.role.value}。",
                metadata={
                    "account_key": updated_user.account_key,
                    "previous_role": user.role.value,
                    "new_role": request.role.value,
                    "reason_zh": request.reason_zh,
                },
            )
            self._connection.commit()
            return self._user_summary(updated_user)

    def list_audit_logs(self, limit: int = 50) -> list[AuditLogEntry]:
        with self._lock:
            rows = self._connection.execute(
                """
                SELECT payload FROM audit_logs
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
            return [AuditLogEntry.model_validate_json(row["payload"]) for row in rows]

    def append_audit_log(
        self,
        action: str,
        target_type: str,
        summary_zh: str,
        actor_session: DeviceSession | None = None,
        target_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> AuditLogEntry:
        with self._lock:
            entry = self._append_audit_log(
                actor_session=actor_session,
                action=action,
                target_type=target_type,
                target_id=target_id,
                summary_zh=summary_zh,
                metadata=metadata or {},
            )
            self._connection.commit()
            return entry

    def device_session_by_access_token(self, access_token: str) -> DeviceSession | None:
        token = access_token.strip()
        if not token:
            return None
        with self._lock:
            row = self._connection.execute(
                """
                SELECT payload FROM devices
                WHERE token_hash = ? AND revoked_at IS NULL
                """,
                (hash_access_token(token),),
            ).fetchone()
            if row is None:
                return None
            session = DeviceSession.model_validate_json(row["payload"])
            user = self._user_by_id(session.user_id)
            return session.model_copy(update={"access_token": token, "role": user.role})

    def revoke_device_session(self, session: DeviceSession) -> DeviceRevocation:
        with self._lock:
            revocation = DeviceRevocation(device_id=session.device_id)
            self._connection.execute(
                """
                UPDATE devices
                SET revoked_at = ?
                WHERE id = ? AND revoked_at IS NULL
                """,
                (revocation.revoked_at.isoformat(), session.device_id),
            )
            self._append_audit_log(
                actor_session=session,
                action="auth.device_revoked",
                target_type="device",
                target_id=session.device_id,
                summary_zh="当前设备访问令牌已撤销。",
                metadata={"user_id": session.user_id},
            )
            self._connection.commit()
            return revocation

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
                approval_requests=self.approval_requests,
                paper_orders=self.paper_orders,
                broker_orders=self.broker_orders,
                paper_portfolios=self.paper_portfolios,
                strategy_drafts=self.strategy_drafts,
                backtest_results=self.backtest_results,
                assistant_turns=self.list_assistant_turns(workspace_id),
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
                    token_hash TEXT NOT NULL,
                    revoked_at TEXT,
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

                CREATE TABLE IF NOT EXISTS approval_requests (
                    id TEXT PRIMARY KEY,
                    order_intent_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS kill_switch_state (
                    id TEXT PRIMARY KEY,
                    enabled INTEGER NOT NULL,
                    updated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS paper_orders (
                    id TEXT PRIMARY KEY,
                    submitted_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS broker_orders (
                    id TEXT PRIMARY KEY,
                    submitted_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS paper_portfolios (
                    account_id TEXT PRIMARY KEY,
                    updated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS strategy_drafts (
                    id TEXT PRIMARY KEY,
                    created_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS backtest_results (
                    id TEXT PRIMARY KEY,
                    generated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS assistant_turns (
                    id TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    generated_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS audit_logs (
                    id TEXT PRIMARY KEY,
                    created_at TEXT NOT NULL,
                    actor_user_id TEXT,
                    action TEXT NOT NULL,
                    target_type TEXT NOT NULL,
                    target_id TEXT,
                    payload TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
                CREATE INDEX IF NOT EXISTS idx_workspaces_owner_user_id ON workspaces(owner_user_id);
                CREATE INDEX IF NOT EXISTS idx_watchlist_workspace ON watchlist_items(workspace_id);
                CREATE INDEX IF NOT EXISTS idx_sync_events_workspace_sequence
                    ON sync_events(workspace_id, sequence);
                CREATE INDEX IF NOT EXISTS idx_assistant_turns_workspace_generated_at
                    ON assistant_turns(workspace_id, generated_at);
                CREATE INDEX IF NOT EXISTS idx_paper_portfolios_updated_at ON paper_portfolios(updated_at);
                CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
                CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_user_id ON audit_logs(actor_user_id);
                """
            )
            self._ensure_column("watchlist_items", "added_at", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column("devices", "token_hash", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column("devices", "revoked_at", "TEXT")
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
        table: Literal[
            "news_analyses",
            "risk_decisions",
            "paper_orders",
            "broker_orders",
            "strategy_drafts",
            "backtest_results",
        ],
        model_id: str,
        payload: BaseModel,
        timestamp: str,
    ) -> None:
        timestamp_column = {
            "news_analyses": "generated_at",
            "risk_decisions": "evaluated_at",
            "paper_orders": "submitted_at",
            "broker_orders": "submitted_at",
            "strategy_drafts": "created_at",
            "backtest_results": "generated_at",
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

    def _save_approval_request(self, approval: ApprovalRequest) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO approval_requests
                (id, order_intent_id, status, created_at, payload)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                approval.id,
                approval.order_intent_id,
                approval.status.value,
                approval.created_at.isoformat(),
                approval.model_dump_json(),
            ),
        )

    def _save_kill_switch_state(self, state: KillSwitchState) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO kill_switch_state (id, enabled, updated_at, payload)
            VALUES ('global', ?, ?, ?)
            """,
            (1 if state.enabled else 0, state.updated_at.isoformat(), state.model_dump_json()),
        )

    def _save_paper_portfolio(self, portfolio: PaperPortfolioSnapshot) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO paper_portfolios (account_id, updated_at, payload)
            VALUES (?, ?, ?)
            """,
            (
                portfolio.account_id,
                portfolio.updated_at.isoformat(),
                portfolio.model_dump_json(),
            ),
        )

    def _save_assistant_turn(self, turn: AssistantConversationTurn) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO assistant_turns
                (id, workspace_id, generated_at, payload)
            VALUES (?, ?, ?, ?)
            """,
            (
                turn.id,
                turn.workspace_id,
                turn.generated_at.isoformat(),
                turn.model_dump_json(),
            ),
        )

    def _paper_portfolio_by_account_id(self, account_id: str) -> PaperPortfolioSnapshot | None:
        row = self._connection.execute(
            "SELECT payload FROM paper_portfolios WHERE account_id = ?",
            (account_id,),
        ).fetchone()
        if row is None:
            return None
        return PaperPortfolioSnapshot.model_validate_json(row["payload"])

    def _default_paper_portfolio(self, account_id: str) -> PaperPortfolioSnapshot:
        return PaperPortfolioSnapshot(
            account_id=account_id,
            cash_by_currency=dict(DEFAULT_PAPER_CASH_BY_CURRENCY),
            equity_by_currency=dict(DEFAULT_PAPER_CASH_BY_CURRENCY),
            realized_pnl_by_currency={currency: 0 for currency in DEFAULT_PAPER_CASH_BY_CURRENCY},
        )

    def _apply_broker_order_to_portfolio(self, order: BrokerOrder) -> PaperPortfolioSnapshot:
        account_id = order.broker_account_id.removeprefix("paper:")
        portfolio = self._paper_portfolio_by_account_id(
            account_id
        ) or self._default_paper_portfolio(account_id)
        cash_by_currency = dict(portfolio.cash_by_currency)
        realized_pnl_by_currency = dict(portfolio.realized_pnl_by_currency)
        positions = {
            (position.market.value, position.symbol, position.currency): position
            for position in portfolio.positions
        }

        for fill in order.fills:
            currency = order.currency.upper()
            position_key = (order.market.value, fill.symbol.upper(), currency)
            existing = positions.get(position_key)
            if existing is None:
                existing = PaperPortfolioPosition(
                    market=order.market,
                    symbol=fill.symbol,
                    currency=currency,
                )

            current_cash = cash_by_currency.get(
                currency, DEFAULT_PAPER_CASH_BY_CURRENCY.get(currency, 0.0)
            )
            current_realized = realized_pnl_by_currency.get(currency, 0.0)

            if fill.side.value == "buy":
                next_quantity = existing.quantity + fill.quantity
                next_avg_cost = (
                    ((existing.quantity * existing.avg_cost) + fill.notional) / next_quantity
                    if next_quantity
                    else 0
                )
                current_cash -= fill.notional + fill.commission
            else:
                next_quantity = existing.quantity - fill.quantity
                next_avg_cost = existing.avg_cost if next_quantity > 0 else 0
                current_realized += (
                    (fill.price - existing.avg_cost) * fill.quantity
                ) - fill.commission
                current_cash += fill.notional - fill.commission

            updated_position = existing.model_copy(
                update={
                    "quantity": round(next_quantity, 8),
                    "avg_cost": round(max(next_avg_cost, 0), 8),
                    "last_price": fill.price,
                    "market_value": round(next_quantity * fill.price, 4),
                    "unrealized_pnl": round((fill.price - next_avg_cost) * next_quantity, 4),
                    "updated_at": fill.filled_at,
                },
            )

            cash_by_currency[currency] = round(current_cash, 4)
            realized_pnl_by_currency[currency] = round(current_realized, 4)
            if abs(updated_position.quantity) < 0.00000001:
                positions.pop(position_key, None)
            else:
                positions[position_key] = updated_position

        position_list = sorted(
            positions.values(), key=lambda item: (item.currency, item.market.value, item.symbol)
        )
        equity_by_currency = dict(cash_by_currency)
        for position in position_list:
            equity_by_currency[position.currency] = round(
                equity_by_currency.get(position.currency, 0.0) + position.market_value,
                4,
            )

        updated = PaperPortfolioSnapshot(
            account_id=account_id,
            cash_by_currency=cash_by_currency,
            equity_by_currency=equity_by_currency,
            realized_pnl_by_currency=realized_pnl_by_currency,
            positions=position_list,
        )
        self._save_paper_portfolio(updated)
        return updated

    def _approval_by_id(self, approval_id: str) -> ApprovalRequest:
        row = self._connection.execute(
            "SELECT payload FROM approval_requests WHERE id = ?",
            (approval_id,),
        ).fetchone()
        if row is None:
            raise KeyError(approval_id)
        return ApprovalRequest.model_validate_json(row["payload"])

    def _approval_by_order_intent_id(self, order_intent_id: str) -> ApprovalRequest | None:
        row = self._connection.execute(
            """
            SELECT payload FROM approval_requests
            WHERE order_intent_id = ?
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (order_intent_id,),
        ).fetchone()
        if row is None:
            return None
        return ApprovalRequest.model_validate_json(row["payload"])

    def _save_user(self, user: UserAccount) -> None:
        self._connection.execute(
            """
            INSERT OR REPLACE INTO users (id, account_key, display_name, created_at, payload)
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

    def _user_summary(self, user: UserAccount) -> UserSummary:
        return UserSummary(
            id=user.id,
            account_key=user.account_key,
            display_name=user.display_name,
            role=user.role,
            mfa_enabled=user.mfa_enabled,
            created_at=user.created_at,
        )

    def _append_audit_log(
        self,
        actor_session: DeviceSession | None,
        action: str,
        target_type: str,
        summary_zh: str,
        target_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> AuditLogEntry:
        entry = AuditLogEntry(
            actor_user_id=actor_session.user_id if actor_session else None,
            actor_device_id=actor_session.device_id if actor_session else None,
            actor_role=actor_session.role if actor_session else None,
            action=action,
            target_type=target_type,
            target_id=target_id,
            summary_zh=summary_zh,
            metadata=metadata or {},
        )
        self._connection.execute(
            """
            INSERT INTO audit_logs
                (id, created_at, actor_user_id, action, target_type, target_id, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                entry.id,
                entry.created_at.isoformat(),
                entry.actor_user_id,
                entry.action,
                entry.target_type,
                entry.target_id,
                entry.model_dump_json(),
            ),
        )
        return entry

    def _create_device_session(
        self,
        user: UserAccount,
        workspace_id: str,
        device_name: str,
        platform: DevicePlatform,
    ) -> DeviceSession:
        session = DeviceSession(
            user_id=user.id,
            device_id=f"device_{uuid4().hex}",
            workspace_id=workspace_id,
            access_token=f"dubhe_dev_{secrets.token_urlsafe(32)}",
            role=user.role,
            platform=platform,
            device_name=device_name,
        )
        stored_session = session.model_copy(update={"access_token": ""})
        self._connection.execute(
            """
            INSERT INTO devices
                (id, user_id, workspace_id, platform, token_hash, revoked_at, created_at, payload)
            VALUES (?, ?, ?, ?, ?, NULL, ?, ?)
            """,
            (
                session.device_id,
                session.user_id,
                session.workspace_id,
                session.platform.value,
                hash_access_token(session.access_token),
                session.created_at.isoformat(),
                stored_session.model_dump_json(),
            ),
        )
        return session

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
        action: Literal["created", "updated", "deleted"] = "created",
    ) -> None:
        rows = self._connection.execute("SELECT id FROM workspaces ORDER BY id").fetchall()
        for row in rows:
            self._append_sync_event(
                workspace_id=row["id"],
                entity_type=entity_type,
                entity_id=entity_id,
                action=action,
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

    def _user_by_id(self, user_id: str) -> UserAccount:
        row = self._connection.execute(
            "SELECT payload FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise KeyError(user_id)
        return UserAccount.model_validate_json(row["payload"])

    def _user_count(self) -> int:
        row = self._connection.execute("SELECT COUNT(*) AS count FROM users").fetchone()
        return int(row["count"])

    def _admin_count(self) -> int:
        rows = self._connection.execute("SELECT payload FROM users").fetchall()
        return sum(
            1
            for row in rows
            if UserAccount.model_validate_json(row["payload"]).role == UserRole.ADMIN
        )

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
