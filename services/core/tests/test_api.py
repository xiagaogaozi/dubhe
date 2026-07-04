from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Any
from uuid import uuid4

os.environ["DUBHE_CORE_DB_PATH"] = str(
    Path(tempfile.gettempdir()) / f"dubhe-core-test-{uuid4().hex}.sqlite",
)

from fastapi.testclient import TestClient

from dubhe_core.main import app
from dubhe_core.models import Market
from dubhe_core.models import DeviceRegistrationRequest, WatchlistUpsertRequest
from dubhe_core.news_sources import fetch_news_feed
from dubhe_core.store import SQLiteStore

client = TestClient(app)


def register_test_device(
    account_key: str,
    account_name: str = "测试账户",
    device_name: str = "Windows 测试机",
    platform: str = "windows",
) -> dict[str, Any]:
    response = client.post(
        "/v1/auth/devices/register",
        json={
            "account_key": account_key,
            "account_name": account_name,
            "device_name": device_name,
            "platform": platform,
        },
    )
    assert response.status_code == 200
    return response.json()


def auth_headers(session: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['access_token']}"}


def test_health() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "dubhe-core"}


def test_device_registration_returns_default_workspace_snapshot() -> None:
    session = register_test_device(
        account_key="sync-fixture-default",
        account_name="同步测试账户",
    )

    assert session["access_token"].startswith("dubhe_dev_")
    assert session["platform"] == "windows"

    snapshot_response = client.get(
        f"/v1/workspaces/{session['workspace_id']}/snapshot",
        headers=auth_headers(session),
    )

    assert snapshot_response.status_code == 200
    snapshot = snapshot_response.json()
    assert snapshot["workspace"]["name"] == "同步测试账户的默认工作区"
    assert snapshot["server_sequence"] >= 5
    assert {item["symbol"] for item in snapshot["watchlist"]} >= {
        "NVDA",
        "0700.HK",
        "600519.SH",
        "AAPL",
    }
    assert snapshot["events"][0]["entity_type"] == "workspace"


def test_sync_endpoints_require_device_token_and_workspace_match() -> None:
    first_session = register_test_device(
        account_key="sync-auth-fixture-a",
        account_name="认证测试账户 A",
    )
    second_session = register_test_device(
        account_key="sync-auth-fixture-b",
        account_name="认证测试账户 B",
    )
    workspace_id = first_session["workspace_id"]

    missing_response = client.get(f"/v1/workspaces/{workspace_id}/snapshot")
    assert missing_response.status_code == 401

    invalid_response = client.get(
        f"/v1/workspaces/{workspace_id}/snapshot",
        headers={"Authorization": "Bearer wrong-token"},
    )
    assert invalid_response.status_code == 401

    cross_workspace_response = client.get(
        f"/v1/workspaces/{workspace_id}/snapshot",
        headers=auth_headers(second_session),
    )
    assert cross_workspace_response.status_code == 403

    ok_response = client.get(
        f"/v1/workspaces/{workspace_id}/snapshot",
        headers=auth_headers(first_session),
    )
    assert ok_response.status_code == 200


def test_watchlist_sync_events_are_shared_across_devices() -> None:
    first_session = register_test_device(
        account_key="sync-fixture-shared",
        account_name="多端同步账户",
    )
    workspace_id = first_session["workspace_id"]

    upsert_response = client.put(
        f"/v1/workspaces/{workspace_id}/watchlist/MSFT",
        headers=auth_headers(first_session),
        json={
            "symbol": "MSFT",
            "name": "微软",
            "market": "US",
            "notes_zh": "从桌面端加入的测试自选股",
        },
    )

    assert upsert_response.status_code == 200
    assert upsert_response.json()["symbol"] == "MSFT"

    second_session = register_test_device(
        account_key="sync-fixture-shared",
        account_name="多端同步账户",
        device_name="iPhone 测试机",
        platform="ios",
    )

    assert second_session["workspace_id"] == workspace_id

    snapshot_response = client.get(
        f"/v1/workspaces/{workspace_id}/snapshot",
        headers=auth_headers(second_session),
    )
    snapshot = snapshot_response.json()
    symbols = {item["symbol"] for item in snapshot["watchlist"]}
    assert "MSFT" in symbols

    events_response = client.get(
        f"/v1/workspaces/{workspace_id}/sync-events?since_sequence=5",
        headers=auth_headers(second_session),
    )
    assert events_response.status_code == 200
    events = events_response.json()
    assert any(event["entity_type"] == "watchlist_item" for event in events)


def test_news_feed_returns_fixture_events_and_persists_them() -> None:
    response = client.get("/v1/news/feed?market=US&symbol=NVDA&limit=3&live=false")

    assert response.status_code == 200
    body = response.json()
    assert body["events"][0]["provider"] == "fixture"
    assert body["events"][0]["tickers"] == ["NVDA"]
    assert any(status["provider"] == "fixture" for status in body["provider_status"])

    events_response = client.get("/v1/news/events")
    assert events_response.status_code == 200
    assert any(event["id"] == body["events"][0]["id"] for event in events_response.json())


def test_public_news_adapters_parse_sec_and_gdelt_payloads() -> None:
    def fake_fetcher(url: str, _headers: dict[str, str], _timeout: float) -> dict[str, object]:
        if "data.sec.gov" in url:
            return {
                "filings": {
                    "recent": {
                        "accessionNumber": ["0001045810-26-000123"],
                        "form": ["10-Q"],
                        "filingDate": ["2026-07-01"],
                        "primaryDocument": ["nvda-20260701.htm"],
                    }
                }
            }
        if "api.gdeltproject.org" in url:
            return {
                "articles": [
                    {
                        "url": "https://example.com/nvda-news",
                        "title": "NVIDIA expands AI platform",
                        "domain": "example.com",
                        "language": "English",
                        "seendate": "20260701123000",
                    }
                ]
            }
        raise AssertionError(url)

    feed = fetch_news_feed(
        market=Market.US,
        symbol="NVDA",
        limit=5,
        live=True,
        fetcher=fake_fetcher,
    )

    assert {event.provider for event in feed.events} == {"sec_edgar", "gdelt_doc"}
    assert any(event.event_type == "filing" for event in feed.events)
    assert any(status.status == "ok" for status in feed.provider_status)


def test_sqlite_store_persists_workspace_and_watchlist_across_restarts(tmp_path: Path) -> None:
    db_path = tmp_path / "dubhe-core.sqlite"
    first_store = SQLiteStore(db_path)
    first_session = first_store.register_device(
        DeviceRegistrationRequest(
            account_key="sqlite-restart-fixture",
            account_name="重启持久化账户",
            device_name="Windows 测试机",
            platform="windows",
        ),
    )
    first_store.upsert_watchlist_item(
        first_session.workspace_id,
        WatchlistUpsertRequest(
            symbol="TSLA",
            name="特斯拉",
            market="US",
            notes_zh="重启后必须仍然存在的自选股",
        ),
    )
    first_store.close()

    second_store = SQLiteStore(db_path)
    second_session = second_store.register_device(
        DeviceRegistrationRequest(
            account_key="sqlite-restart-fixture",
            account_name="重启持久化账户",
            device_name="iPhone 测试机",
            platform="ios",
        ),
    )
    snapshot = second_store.get_workspace_snapshot(second_session.workspace_id)
    second_store.close()

    assert second_session.workspace_id == first_session.workspace_id
    assert "TSLA" in {item.symbol for item in snapshot.watchlist}
    assert snapshot.server_sequence >= 6
    assert any(event.entity_id for event in snapshot.events if event.entity_type == "watchlist_item")


def test_news_analysis_returns_chinese_summary_and_sources() -> None:
    response = client.post(
        "/v1/news/analyze",
        json={
            "provider": "fixture",
            "provider_event_id": "fixture-001",
            "source_name": "测试新闻源",
            "market_scope": ["US"],
            "title_original": "英伟达业绩超预期并宣布回购",
            "published_at": "2026-07-05T00:00:00Z",
            "url": "https://example.com/news/fixture-001",
            "tickers": ["nvda"],
            "entities": ["英伟达"],
            "event_type": "earnings",
            "authority_score": 0.9,
            "license_flags": ["fixture"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["summary_zh"].startswith("这条来自测试新闻源的消息显示")
    assert body["sentiment"] == "positive"
    assert body["affected_tickers"] == ["NVDA"]
    assert body["source_refs"] == ["https://example.com/news/fixture-001"]

    list_response = client.get("/v1/news/analyses")
    assert list_response.status_code == 200
    assert any(item["id"] == body["id"] for item in list_response.json())


def test_strategy_draft_and_replay_backtest_from_news_analysis() -> None:
    analysis = {
        "id": "analysis_strategy_fixture",
        "news_event_id": "news_strategy_fixture",
        "summary_zh": "这条来自SEC EDGAR的消息显示：英伟达提交 SEC 8-K 文件",
        "sentiment": "positive",
        "impact_score": 0.72,
        "affected_tickers": ["NVDA"],
        "source_refs": ["https://www.sec.gov/Archives/edgar/data/1045810/example.htm"],
        "confidence": 0.8,
        "generated_at": "2026-07-05T00:00:00Z",
    }
    draft_response = client.post(
        "/v1/strategy/drafts/from-analysis",
        json={
            "analysis": analysis,
            "symbol": "NVDA",
            "market": "US",
            "max_order_notional": 10000,
        },
    )

    assert draft_response.status_code == 200
    draft = draft_response.json()
    assert draft["spec"]["asset_universe"] == ["NVDA"]
    assert draft["spec"]["broker_permissions"] == ["paper"]
    assert "QCAlgorithm" in draft["generated_code"]

    backtest_response = client.post(
        "/v1/backtests/replay",
        json={
            "strategy": draft,
            "initial_cash": 100000,
            "replay_scenario": "golden_news_sentiment_v1",
        },
    )

    assert backtest_response.status_code == 200
    backtest = backtest_response.json()
    assert backtest["symbol"] == "NVDA"
    assert backtest["trade_count"] == 2
    assert backtest["final_equity"] > 100000
    assert len(backtest["equity_curve"]) >= 5

    list_response = client.get("/v1/backtests")
    assert list_response.status_code == 200
    assert any(item["id"] == backtest["id"] for item in list_response.json())


def test_live_ai_order_requires_human_approval() -> None:
    session = register_test_device(
        account_key="approval-fixture",
        account_name="审批测试账户",
    )
    response = client.post(
        "/v1/risk/evaluate",
        json={
            "account_id": "acct_fixture",
            "strategy_version_id": "strategy_v1",
            "market": "US",
            "symbol": "NVDA",
            "side": "buy",
            "order_type": "market",
            "quantity": 1,
            "estimated_price": 1000,
            "currency": "USD",
            "created_by": "ai",
            "destination": "live",
            "rationale_zh": "测试实盘审批门禁。",
            "source_refs": ["analysis_fixture"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "requires_approval"
    assert body["allowed_destination"] == "live_after_approval"
    assert "人工审批" in body["reasons_zh"][0]

    list_response = client.get("/v1/risk/decisions")
    assert list_response.status_code == 200
    assert any(item["id"] == body["id"] for item in list_response.json())

    assert client.get("/v1/approvals?status=pending").status_code == 401

    approvals_response = client.get("/v1/approvals?status=pending", headers=auth_headers(session))
    assert approvals_response.status_code == 200
    approvals = approvals_response.json()
    approval = next(
        item for item in approvals if item["order_intent_id"] == body["order_intent_id"]
    )
    assert approval["status"] == "pending"

    approve_response = client.post(
        f"/v1/approvals/{approval['id']}/approve",
        headers=auth_headers(session),
        json={
            "decided_by": "risk_manager_fixture",
            "decision_comment_zh": "测试通过审批。",
        },
    )
    assert approve_response.status_code == 200
    assert approve_response.json()["status"] == "approved"


def test_kill_switch_blocks_new_paper_orders() -> None:
    session = register_test_device(
        account_key="kill-switch-fixture",
        account_name="急停测试账户",
    )
    assert client.get("/v1/risk/kill-switch").status_code == 401

    enable_response = client.post(
        "/v1/risk/kill-switch",
        headers=auth_headers(session),
        json={
            "enabled": True,
            "reason_zh": "测试 kill switch 拦截新订单。",
            "updated_by": "risk_manager_fixture",
        },
    )
    assert enable_response.status_code == 200
    assert enable_response.json()["enabled"] is True

    response = client.post(
        "/v1/simulation/paper-orders",
        json={
            "account_id": "acct_fixture",
            "strategy_version_id": "strategy_v1",
            "market": "US",
            "symbol": "NVDA",
            "side": "buy",
            "order_type": "market",
            "quantity": 1,
            "estimated_price": 1000,
            "currency": "USD",
            "created_by": "strategy",
            "destination": "paper",
            "rationale_zh": "测试 kill switch。",
            "source_refs": ["analysis_fixture"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "blocked"
    assert "Kill switch" in body["risk_decision"]["reasons_zh"][0]

    disable_response = client.post(
        "/v1/risk/kill-switch",
        headers=auth_headers(session),
        json={
            "enabled": False,
            "reason_zh": "测试结束，恢复下单。",
            "updated_by": "risk_manager_fixture",
        },
    )
    assert disable_response.status_code == 200
    assert disable_response.json()["enabled"] is False


def test_paper_order_blocks_missing_source_refs() -> None:
    response = client.post(
        "/v1/simulation/paper-orders",
        json={
            "account_id": "acct_fixture",
            "strategy_version_id": "strategy_v1",
            "market": "HK",
            "symbol": "0700.HK",
            "side": "buy",
            "order_type": "limit",
            "quantity": 100,
            "estimated_price": 300,
            "limit_price": 300,
            "currency": "HKD",
            "created_by": "strategy",
            "destination": "paper",
            "rationale_zh": "测试缺少来源引用。",
            "source_refs": [],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "blocked"
    assert body["risk_decision"]["status"] == "rejected"

    list_response = client.get("/v1/simulation/paper-orders")
    assert list_response.status_code == 200
    assert any(item["id"] == body["id"] for item in list_response.json())


def test_strategy_spec_validation_requires_risk_and_permissions() -> None:
    response = client.post(
        "/v1/strategy/spec/validate",
        json={
            "strategy_name": "新闻情绪测试策略",
            "market_scope": ["A_SHARE", "HK", "US"],
            "asset_universe": ["NVDA", "0700.HK"],
            "entry_rules": ["新闻情绪为正面且影响分大于 0.7"],
            "exit_rules": ["新闻影响消退或触发止损"],
            "risk_limits": {},
            "timeframe": "1d",
            "rebalance_rule": "daily",
            "data_dependencies": [],
            "broker_permissions": [],
        },
    )

    assert response.status_code == 422


def test_strategy_spec_validation_accepts_minimum_safe_spec() -> None:
    response = client.post(
        "/v1/strategy/spec/validate",
        json={
            "strategy_name": "新闻情绪测试策略",
            "market_scope": ["US"],
            "asset_universe": ["NVDA"],
            "entry_rules": ["新闻情绪为正面且影响分大于 0.7"],
            "exit_rules": ["新闻影响消退或触发止损"],
            "risk_limits": {"max_order_notional": 10000},
            "timeframe": "1d",
            "rebalance_rule": "daily",
            "data_dependencies": ["news", "market_bars"],
            "broker_permissions": ["paper"],
        },
    )

    assert response.status_code == 200
    assert response.json() == {"valid": True, "reasons_zh": []}
