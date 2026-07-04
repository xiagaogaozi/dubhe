from __future__ import annotations

from fastapi.testclient import TestClient

from dubhe_core.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "dubhe-core"}


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
