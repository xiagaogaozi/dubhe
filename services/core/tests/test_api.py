from __future__ import annotations

from fastapi.testclient import TestClient

from dubhe_core.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "dubhe-core"}


def test_device_registration_returns_default_workspace_snapshot() -> None:
    session_response = client.post(
        "/v1/auth/devices/register",
        json={
            "account_key": "sync-fixture-default",
            "account_name": "同步测试账户",
            "device_name": "Windows 测试机",
            "platform": "windows",
        },
    )

    assert session_response.status_code == 200
    session = session_response.json()
    assert session["access_token"].startswith("local_")
    assert session["platform"] == "windows"

    snapshot_response = client.get(f"/v1/workspaces/{session['workspace_id']}/snapshot")

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


def test_watchlist_sync_events_are_shared_across_devices() -> None:
    first_session_response = client.post(
        "/v1/auth/devices/register",
        json={
            "account_key": "sync-fixture-shared",
            "account_name": "多端同步账户",
            "device_name": "Windows 测试机",
            "platform": "windows",
        },
    )
    first_session = first_session_response.json()
    workspace_id = first_session["workspace_id"]

    upsert_response = client.put(
        f"/v1/workspaces/{workspace_id}/watchlist/MSFT",
        json={
            "symbol": "MSFT",
            "name": "微软",
            "market": "US",
            "notes_zh": "从桌面端加入的测试自选股",
        },
    )

    assert upsert_response.status_code == 200
    assert upsert_response.json()["symbol"] == "MSFT"

    second_session_response = client.post(
        "/v1/auth/devices/register",
        json={
            "account_key": "sync-fixture-shared",
            "account_name": "多端同步账户",
            "device_name": "iPhone 测试机",
            "platform": "ios",
        },
    )
    second_session = second_session_response.json()

    assert second_session["workspace_id"] == workspace_id

    snapshot_response = client.get(f"/v1/workspaces/{workspace_id}/snapshot")
    snapshot = snapshot_response.json()
    symbols = {item["symbol"] for item in snapshot["watchlist"]}
    assert "MSFT" in symbols

    events_response = client.get(f"/v1/workspaces/{workspace_id}/sync-events?since_sequence=5")
    assert events_response.status_code == 200
    events = events_response.json()
    assert any(event["entity_type"] == "watchlist_item" for event in events)


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


def test_live_ai_order_requires_human_approval() -> None:
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
