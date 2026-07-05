from __future__ import annotations

import os
import json
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
from dubhe_core.news_sources import (
    fetch_alpha_vantage_news_sentiment,
    fetch_finnhub_company_news,
    fetch_news_feed,
)
from dubhe_core import smoke_report
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


def test_system_status_reports_missing_provider_config(monkeypatch) -> None:
    monkeypatch.delenv("FINNHUB_API_KEY", raising=False)
    monkeypatch.delenv("ALPHA_VANTAGE_API_KEY", raising=False)
    monkeypatch.delenv("DUBHE_SEC_USER_AGENT", raising=False)
    monkeypatch.delenv("DUBHE_LLM_MODEL", raising=False)
    monkeypatch.delenv("DUBHE_LLM_BASE_URL", raising=False)
    monkeypatch.delenv("DUBHE_LLM_API_KEY", raising=False)

    response = client.get("/v1/system/status")

    assert response.status_code == 200
    body = response.json()
    assert body["service"] == "dubhe-core"
    assert body["language"] == "zh-CN"
    assert body["storage"]["backend"] == "sqlite"
    assert body["llm"]["enabled"] is False
    assert body["llm"]["fallback_available"] is True
    assert body["trading"]["paper_broker_enabled"] is True
    assert body["trading"]["live_trading_enabled"] is False

    config_by_key = {item["key"]: item for item in body["config_items"]}
    assert config_by_key["FINNHUB_API_KEY"]["configured"] is False
    assert config_by_key["ALPHA_VANTAGE_API_KEY"]["configured"] is False
    assert config_by_key["DUBHE_SEC_USER_AGENT"]["configured"] is False
    assert config_by_key["DUBHE_LLM_MODEL"]["configured"] is False
    assert config_by_key["DUBHE_LLM_API_KEY"]["configured"] is False

    adapters = {item["provider"]: item for item in body["news_adapters"]}
    assert adapters["finnhub_company_news"]["enabled"] is False
    assert adapters["alpha_vantage_news_sentiment"]["enabled"] is False
    assert adapters["sec_edgar"]["enabled"] is True
    assert adapters["fixture"]["enabled"] is True

    coverage = {item["market"]: item for item in body["news_coverage"]}
    assert coverage["A_SHARE"]["demo_ready"] is True
    assert coverage["A_SHARE"]["licensed_source_ready"] is False
    assert coverage["A_SHARE"]["production_ready"] is False
    assert "Wind" in coverage["A_SHARE"]["missing_sources_zh"]
    assert coverage["US"]["licensed_source_ready"] is False
    assert "FINNHUB_API_KEY" in coverage["US"]["missing_sources_zh"]


def test_system_status_reports_configured_keys_without_leaking_values(monkeypatch) -> None:
    monkeypatch.setenv("FINNHUB_API_KEY", "finnhub-super-secret-token")
    monkeypatch.setenv("ALPHA_VANTAGE_API_KEY", "alpha-super-secret-token")
    monkeypatch.setenv("DUBHE_SEC_USER_AGENT", "Dubhe Test status-secret@example.com")
    monkeypatch.setenv("DUBHE_LLM_MODEL", "gpt-test")
    monkeypatch.setenv("DUBHE_LLM_BASE_URL", "https://llm.example.com/v1")
    monkeypatch.setenv("DUBHE_LLM_API_KEY", "llm-super-secret-token")

    response = client.get("/v1/system/status")

    assert response.status_code == 200
    body = response.json()
    config_by_key = {item["key"]: item for item in body["config_items"]}
    assert config_by_key["FINNHUB_API_KEY"]["configured"] is True
    assert config_by_key["ALPHA_VANTAGE_API_KEY"]["configured"] is True
    assert config_by_key["DUBHE_SEC_USER_AGENT"]["configured"] is True
    assert config_by_key["DUBHE_LLM_MODEL"]["configured"] is True
    assert config_by_key["DUBHE_LLM_BASE_URL"]["configured"] is True
    assert config_by_key["DUBHE_LLM_API_KEY"]["configured"] is True
    assert body["llm"]["enabled"] is True
    assert body["llm"]["model"] == "gpt-test"

    adapters = {item["provider"]: item for item in body["news_adapters"]}
    assert adapters["finnhub_company_news"]["enabled"] is True
    assert adapters["alpha_vantage_news_sentiment"]["enabled"] is True
    assert adapters["sec_edgar"]["configured"] is True

    coverage = {item["market"]: item for item in body["news_coverage"]}
    assert coverage["US"]["licensed_source_ready"] is True
    assert coverage["US"]["production_ready"] is False
    assert "Finnhub 公司新闻" in coverage["US"]["available_sources_zh"]
    assert "FINNHUB_API_KEY" not in coverage["US"]["missing_sources_zh"]
    assert coverage["GLOBAL"]["licensed_source_ready"] is True

    payload = response.text
    assert "finnhub-super-secret-token" not in payload
    assert "alpha-super-secret-token" not in payload
    assert "status-secret@example.com" not in payload
    assert "llm-super-secret-token" not in payload


def test_local_runtime_config_editor_writes_file_without_leaking_secrets(
    monkeypatch,
    tmp_path: Path,
) -> None:
    for key in [
        "DUBHE_REPO_ROOT",
        "DUBHE_LLM_MODEL",
        "DUBHE_LLM_BASE_URL",
        "DUBHE_LLM_API_KEY",
        "FINNHUB_API_KEY",
        "ALPHA_VANTAGE_API_KEY",
    ]:
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("DUBHE_REPO_ROOT", str(tmp_path))

    unauthorized = client.get("/v1/runtime/local-config")
    assert unauthorized.status_code == 401

    session = register_test_device(f"local-config-admin-{uuid4().hex[:8]}")
    initial = client.get("/v1/runtime/local-config", headers=auth_headers(session))
    assert initial.status_code == 200
    assert initial.json()["exists"] is False

    response = client.put(
        "/v1/runtime/local-config",
        headers=auth_headers(session),
        json={
            "values": {
                "DUBHE_LLM_MODEL": "gpt-test",
                "DUBHE_LLM_BASE_URL": "http://127.0.0.1:4000/v1",
                "FINNHUB_API_KEY": "finnhub-secret-token",
            },
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["exists"] is True
    assert Path(body["path"]) == tmp_path / "config" / "dubhe.local.env"
    assert "finnhub-secret-token" not in response.text
    items_by_key = {item["key"]: item for item in body["items"]}
    assert items_by_key["DUBHE_LLM_MODEL"]["masked_value"] == "gpt-test"
    assert items_by_key["DUBHE_LLM_MODEL"]["group_zh"] == "AI 模型"
    assert items_by_key["DUBHE_LLM_MODEL"]["placeholder"]
    assert items_by_key["FINNHUB_API_KEY"]["configured"] is True
    assert items_by_key["FINNHUB_API_KEY"]["masked_value"] == "••••oken"
    assert items_by_key["FINNHUB_API_KEY"]["group_zh"] == "授权新闻源"
    assert "生产前" in items_by_key["FINNHUB_API_KEY"]["setup_hint_zh"]
    assert os.environ["FINNHUB_API_KEY"] == "finnhub-secret-token"

    config_text = (tmp_path / "config" / "dubhe.local.env").read_text(encoding="utf-8")
    assert "DUBHE_LLM_MODEL=gpt-test" in config_text
    assert "FINNHUB_API_KEY=finnhub-secret-token" in config_text

    audit_response = client.get("/v1/audit/logs", headers=auth_headers(session))
    assert audit_response.status_code == 200
    assert "runtime.local_config_updated" in audit_response.text
    assert "finnhub-secret-token" not in audit_response.text

    clear_response = client.put(
        "/v1/runtime/local-config",
        headers=auth_headers(session),
        json={
            "clear_keys": [
                "DUBHE_LLM_MODEL",
                "DUBHE_LLM_BASE_URL",
                "FINNHUB_API_KEY",
            ],
        },
    )
    assert clear_response.status_code == 200
    assert "FINNHUB_API_KEY" not in os.environ
    assert "DUBHE_LLM_MODEL" not in os.environ
    assert "DUBHE_LLM_BASE_URL" not in os.environ
    cleared_items = {item["key"]: item for item in clear_response.json()["items"]}
    assert cleared_items["FINNHUB_API_KEY"]["configured"] is False


def test_onboarding_checklist_guides_unauthenticated_and_logged_in_users() -> None:
    anonymous_response = client.get("/v1/onboarding/checklist")
    assert anonymous_response.status_code == 200
    anonymous = anonymous_response.json()
    anonymous_steps = {step["id"]: step for step in anonymous["steps"]}
    assert anonymous["total_count"] >= 8
    assert anonymous_steps["core_connected"]["status"] == "complete"
    assert anonymous_steps["account_login"]["status"] == "action_required"
    assert "登录" in anonymous["next_action_zh"] or "创建" in anonymous["next_action_zh"]

    session = register_test_device(f"onboarding-{uuid4().hex[:8]}")
    logged_in_response = client.get(
        "/v1/onboarding/checklist",
        headers=auth_headers(session),
    )
    assert logged_in_response.status_code == 200
    logged_in = logged_in_response.json()
    logged_in_steps = {step["id"]: step for step in logged_in["steps"]}
    assert logged_in_steps["account_login"]["status"] == "complete"
    assert logged_in_steps["workspace_sync"]["status"] == "complete"
    assert logged_in_steps["paper_trading_ready"]["status"] == "complete"
    assert logged_in_steps["live_trading_guard"]["status"] == "complete"
    assert logged_in["complete_count"] > anonymous["complete_count"]


def test_system_smoke_report_reads_latest_report(monkeypatch, tmp_path: Path) -> None:
    report_path = tmp_path / "smoke-core-workflow.json"
    report_path.write_text(
        json.dumps(
            {
                "generated_at": "2026-07-05T07:19:07Z",
                "status": "passed",
                "core_url": "http://127.0.0.1:8000",
                "market": "US",
                "symbol": "NVDA",
                "failure": None,
                "report_path": str(report_path),
                "artifacts": {
                    "strategy_version_id": "strategy_v_smoke",
                    "paper_account_id": "smoke-paper",
                    "workspace_sequence": 15,
                },
                "steps": [
                    {
                        "name": "Core 健康检查",
                        "status": "passed",
                        "duration_ms": 12,
                        "message": "通过",
                        "data": None,
                    },
                    {
                        "name": "纸面组合入账",
                        "status": "passed",
                        "duration_ms": 22,
                        "message": "通过",
                        "data": None,
                    },
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(smoke_report, "default_smoke_report_path", lambda: report_path)

    response = client.get("/v1/system/smoke-report")

    assert response.status_code == 200
    body = response.json()
    assert body["available"] is True
    assert body["status"] == "passed"
    assert "主链路烟测通过" in body["message_zh"]
    assert body["symbol"] == "NVDA"
    assert body["artifacts"]["paper_account_id"] == "smoke-paper"
    assert [step["name"] for step in body["steps"]] == ["Core 健康检查", "纸面组合入账"]


def test_system_smoke_report_handles_missing_report(monkeypatch, tmp_path: Path) -> None:
    missing_path = tmp_path / "missing-smoke.json"
    monkeypatch.setattr(smoke_report, "default_smoke_report_path", lambda: missing_path)

    response = client.get("/v1/system/smoke-report")

    assert response.status_code == 200
    body = response.json()
    assert body["available"] is False
    assert body["status"] == "missing"
    assert "尚未运行主链路烟测" in body["message_zh"]
    assert body["report_path"] == str(missing_path)


def test_local_desktop_cors_allows_random_theia_port() -> None:
    response = client.options(
        "/health",
        headers={
            "Origin": "http://127.0.0.1:39201",
            "Access-Control-Request-Method": "GET",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://127.0.0.1:39201"


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


def test_device_token_can_be_revoked() -> None:
    session = register_test_device(
        account_key="sync-revoke-fixture",
        account_name="撤销测试账户",
    )
    workspace_id = session["workspace_id"]
    headers = auth_headers(session)

    before_response = client.get(f"/v1/workspaces/{workspace_id}/snapshot", headers=headers)
    assert before_response.status_code == 200

    revoke_response = client.post("/v1/auth/devices/current/revoke", headers=headers)
    assert revoke_response.status_code == 200
    assert revoke_response.json()["device_id"] == session["device_id"]
    assert revoke_response.json()["revoked"] is True

    after_response = client.get(f"/v1/workspaces/{workspace_id}/snapshot", headers=headers)
    assert after_response.status_code == 401


def test_account_login_mfa_and_role_boundaries() -> None:
    legacy_session = register_test_device(
        account_key="auth-claim-fixture",
        account_name="旧演示账号",
    )
    assert legacy_session["role"] == "admin"

    wrong_mfa_response = client.post(
        "/v1/auth/accounts/register",
        json={
            "account_key": "auth-claim-fixture",
            "account_name": "旧演示账号",
            "password": "Dubhe@2026",
            "mfa_code": "111111",
            "device_name": "Windows 测试机",
            "platform": "windows",
        },
    )
    assert wrong_mfa_response.status_code == 401

    claim_response = client.post(
        "/v1/auth/accounts/register",
        json={
            "account_key": "auth-claim-fixture",
            "account_name": "正式登录账号",
            "password": "Dubhe@2026",
            "mfa_code": "000000",
            "device_name": "Windows 测试机",
            "platform": "windows",
        },
    )
    assert claim_response.status_code == 200
    claimed_session = claim_response.json()
    assert claimed_session["workspace_id"] == legacy_session["workspace_id"]
    assert claimed_session["role"] == "admin"

    login_response = client.post(
        "/v1/auth/login",
        json={
            "account_key": "auth-claim-fixture",
            "password": "Dubhe@2026",
            "mfa_code": "000000",
            "device_name": "Mac 测试机",
            "platform": "macos",
        },
    )
    assert login_response.status_code == 200
    assert login_response.json()["role"] == "admin"

    wrong_password_response = client.post(
        "/v1/auth/login",
        json={
            "account_key": "auth-claim-fixture",
            "password": "wrong-password",
            "mfa_code": "000000",
            "device_name": "Mac 测试机",
            "platform": "macos",
        },
    )
    assert wrong_password_response.status_code == 401

    user_response = client.post(
        "/v1/auth/accounts/register",
        json={
            "account_key": "auth-user-fixture",
            "account_name": "普通用户账号",
            "password": "Dubhe@2026",
            "mfa_code": "000000",
            "device_name": "iPhone 测试机",
            "platform": "ios",
        },
    )
    assert user_response.status_code == 200
    user_session = user_response.json()
    assert user_session["role"] == "user"

    denied_response = client.post(
        "/v1/risk/kill-switch",
        headers=auth_headers(user_session),
        json={
            "enabled": True,
            "reason_zh": "普通用户不能启用急停。",
            "updated_by": "user_fixture",
        },
    )
    assert denied_response.status_code == 403

    assert client.get("/v1/admin/users", headers=auth_headers(user_session)).status_code == 403

    users_response = client.get("/v1/admin/users", headers=auth_headers(claimed_session))
    assert users_response.status_code == 200
    users = users_response.json()
    target_user = next(user for user in users if user["account_key"] == "auth-user-fixture")

    promote_response = client.post(
        f"/v1/admin/users/{target_user['id']}/role",
        headers=auth_headers(claimed_session),
        json={
            "role": "risk_manager",
            "reason_zh": "测试将普通用户提升为风控管理员。",
        },
    )
    assert promote_response.status_code == 200
    assert promote_response.json()["role"] == "risk_manager"

    assert client.get("/v1/approvals", headers=auth_headers(user_session)).status_code == 200
    assert client.get("/v1/admin/users", headers=auth_headers(user_session)).status_code == 403

    audit_response = client.get("/v1/audit/logs?limit=20", headers=auth_headers(user_session))
    assert audit_response.status_code == 200
    audit_logs = audit_response.json()
    assert any(log["action"] == "admin.user_role_updated" for log in audit_logs)
    assert any(log["action"] == "auth.login_succeeded" for log in audit_logs)


def test_workspace_sync_websocket_streams_new_events() -> None:
    session = register_test_device(
        account_key="sync-websocket-fixture",
        account_name="实时同步测试账户",
    )
    workspace_id = session["workspace_id"]
    headers = auth_headers(session)
    snapshot = client.get(f"/v1/workspaces/{workspace_id}/snapshot", headers=headers).json()

    with client.websocket_connect(
        f"/v1/workspaces/{workspace_id}/sync-events/ws"
        f"?access_token={session['access_token']}&since_sequence={snapshot['server_sequence']}",
    ) as websocket:
        upsert_response = client.put(
            f"/v1/workspaces/{workspace_id}/watchlist/AMD",
            headers=headers,
            json={
                "symbol": "AMD",
                "name": "超威半导体",
                "market": "US",
                "notes_zh": "通过 WebSocket 验证同步事件。",
            },
        )
        assert upsert_response.status_code == 200

        event = websocket.receive_json()
        assert event["entity_type"] == "watchlist_item"
        assert event["action"] == "created"
        assert event["payload"]["symbol"] == "AMD"
        assert event["sequence"] > snapshot["server_sequence"]


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


def test_licensed_news_adapters_parse_finnhub_and_alpha_vantage_payloads(monkeypatch) -> None:
    monkeypatch.setenv("FINNHUB_API_KEY", "finnhub-test-token")
    monkeypatch.setenv("ALPHA_VANTAGE_API_KEY", "alpha-test-token")

    def fake_fetcher(url: str, _headers: dict[str, str], _timeout: float) -> object:
        if "finnhub.io/api/v1/company-news" in url:
            assert "token=finnhub-test-token" in url
            return [
                {
                    "category": "company",
                    "datetime": 1783209600,
                    "headline": "NVIDIA announces new AI platform",
                    "id": 42,
                    "source": "Finnhub Test",
                    "url": "https://example.com/finnhub-nvda",
                }
            ]
        if "alphavantage.co/query" in url:
            assert "function=NEWS_SENTIMENT" in url
            assert "apikey=alpha-test-token" in url
            return {
                "feed": [
                    {
                        "title": "NVIDIA sentiment improves",
                        "url": "https://example.com/alpha-nvda",
                        "time_published": "20260705T093000",
                        "source": "Alpha Test",
                        "category_within_source": "Technology",
                        "ticker_sentiment": [{"ticker": "NVDA"}],
                    }
                ]
            }
        raise AssertionError(url)

    finnhub_events, finnhub_status = fetch_finnhub_company_news(
        market=Market.US,
        symbol="NVDA",
        limit=5,
        fetcher=fake_fetcher,
    )
    alpha_events, alpha_status = fetch_alpha_vantage_news_sentiment(
        market=Market.US,
        symbol="NVDA",
        limit=5,
        fetcher=fake_fetcher,
    )

    assert finnhub_status.status == "ok"
    assert finnhub_events[0].provider == "finnhub_company_news"
    assert finnhub_events[0].source_name == "Finnhub Test"
    assert finnhub_events[0].tickers == ["NVDA"]
    assert "provider_terms_required" in finnhub_events[0].license_flags

    assert alpha_status.status == "ok"
    assert alpha_events[0].provider == "alpha_vantage_news_sentiment"
    assert alpha_events[0].source_name == "Alpha Test"
    assert alpha_events[0].tickers == ["NVDA"]
    assert "provider_terms_required" in alpha_events[0].license_flags


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
    assert any(
        event.entity_id for event in snapshot.events if event.entity_type == "watchlist_item"
    )


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


def test_assistant_chat_answers_with_context_citations_and_audit_log() -> None:
    account_key = f"assistant-chat-{uuid4().hex[:8]}"
    session = register_test_device(
        account_key=account_key,
        account_name="AI 分析师测试账户",
    )
    analysis = {
        "id": "analysis_assistant_fixture",
        "news_event_id": "news_assistant_fixture",
        "summary_zh": "英伟达相关新闻显示 AI 算力需求仍然强劲。",
        "sentiment": "positive",
        "impact_score": 0.74,
        "affected_tickers": ["NVDA"],
        "source_refs": ["https://example.com/nvda-news"],
        "confidence": 0.82,
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
    backtest_response = client.post(
        "/v1/backtests/replay",
        json={"strategy": draft, "initial_cash": 100000},
    )
    assert backtest_response.status_code == 200
    backtest = backtest_response.json()
    before_snapshot_response = client.get(
        f"/v1/workspaces/{session['workspace_id']}/snapshot",
        headers=auth_headers(session),
    )
    assert before_snapshot_response.status_code == 200
    before_sequence = before_snapshot_response.json()["server_sequence"]

    unauthorized_response = client.post(
        "/v1/assistant/chat",
        json={"question_zh": "可以直接实盘买吗？", "context": {"analysis": analysis}},
    )
    assert unauthorized_response.status_code == 401

    response = client.post(
        "/v1/assistant/chat",
        headers=auth_headers(session),
        json={
            "question_zh": "这条新闻会影响哪些股票？可以直接实盘买吗？策略脚本和回测怎么看？",
            "context": {
                "analysis": analysis,
                "strategy": draft,
                "backtest": backtest,
            },
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert "NVDA" in body["answer_zh"]
    assert "不能" in body["answer_zh"]
    assert "实盘" in body["answer_zh"]
    assert any(item["ref"] == "https://example.com/nvda-news" for item in body["citations"])
    assert any("纸面" in item for item in body["suggested_actions_zh"])
    assert any("风控" in item for item in body["safety_notes_zh"])
    assert body["model_provider"] == "deterministic"
    assert body["fallback_used"] is True

    snapshot_response = client.get(
        f"/v1/workspaces/{session['workspace_id']}/snapshot",
        headers=auth_headers(session),
    )
    assert snapshot_response.status_code == 200
    snapshot = snapshot_response.json()
    assert any(turn["id"] == body["id"] for turn in snapshot["assistant_turns"])
    turn = next(item for item in snapshot["assistant_turns"] if item["id"] == body["id"])
    assert turn["question_zh"] == "这条新闻会影响哪些股票？可以直接实盘买吗？策略脚本和回测怎么看？"
    assert turn["answer_zh"] == body["answer_zh"]
    assert turn["context_refs"] == [
        analysis["id"],
        draft["strategy_version_id"],
        backtest["id"],
    ]
    assert turn["model_provider"] == "deterministic"
    assert turn["fallback_used"] is True
    assert turn["created_by_device_id"] == session["device_id"]

    sync_response = client.get(
        f"/v1/workspaces/{session['workspace_id']}/sync-events?since_sequence={before_sequence}",
        headers=auth_headers(session),
    )
    assert sync_response.status_code == 200
    sync_events = sync_response.json()
    assert any(
        event["entity_type"] == "assistant_turn" and event["entity_id"] == body["id"]
        for event in sync_events
    )

    turns_response = client.get("/v1/assistant/turns", headers=auth_headers(session))
    assert turns_response.status_code == 200
    assert turns_response.json()[-1]["id"] == body["id"]

    second_session = register_test_device(
        account_key=account_key,
        account_name="AI 分析师测试账户",
        device_name="Android 测试机",
        platform="android",
    )
    second_snapshot_response = client.get(
        f"/v1/workspaces/{second_session['workspace_id']}/snapshot",
        headers=auth_headers(second_session),
    )
    assert second_snapshot_response.status_code == 200
    assert second_session["workspace_id"] == session["workspace_id"]
    assert any(
        turn["id"] == body["id"] for turn in second_snapshot_response.json()["assistant_turns"]
    )

    audit_response = client.get("/v1/audit/logs", headers=auth_headers(session))
    assert audit_response.status_code == 200
    assert any(item["action"] == "assistant.chat_requested" for item in audit_response.json())


def test_assistant_chat_uses_configured_openai_compatible_model(monkeypatch) -> None:
    class FakeLLMResponse:
        def __enter__(self) -> "FakeLLMResponse":
            return self

        def __exit__(self, *_args: object) -> None:
            return None

        def read(self) -> bytes:
            return json.dumps(
                {
                    "choices": [
                        {
                            "message": {
                                "content": json.dumps(
                                    {
                                        "answer_zh": "模型认为应继续纸面验证，不应直接实盘。",
                                        "suggested_actions_zh": ["复查来源", "运行回测"],
                                        "safety_notes_zh": ["模型不会发送真实订单。"],
                                    },
                                    ensure_ascii=False,
                                )
                            }
                        }
                    ]
                },
                ensure_ascii=False,
            ).encode("utf-8")

    calls: list[dict[str, Any]] = []

    def fake_urlopen(request: Any, timeout: float) -> FakeLLMResponse:
        calls.append(
            {
                "url": request.full_url,
                "timeout": timeout,
                "headers": dict(request.header_items()),
                "body": json.loads(request.data.decode("utf-8")),
            }
        )
        return FakeLLMResponse()

    monkeypatch.setenv("DUBHE_LLM_MODEL", "gpt-test")
    monkeypatch.setenv("DUBHE_LLM_BASE_URL", "https://llm.example.com/v1")
    monkeypatch.setenv("DUBHE_LLM_API_KEY", "llm-test-token")
    monkeypatch.setattr("dubhe_core.llm.urllib.request.urlopen", fake_urlopen)

    session = register_test_device(
        account_key=f"assistant-llm-{uuid4().hex[:8]}",
        account_name="AI 模型路由测试账户",
    )
    response = client.post(
        "/v1/assistant/chat",
        headers=auth_headers(session),
        json={
            "question_zh": "请用真实模型分析这条新闻下一步怎么验证？",
            "context": {},
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["answer_zh"] == "模型认为应继续纸面验证，不应直接实盘。"
    assert body["model_provider"] == "openai_compatible"
    assert body["model_name"] == "gpt-test"
    assert body["fallback_used"] is False
    assert any("真实订单" in item for item in body["safety_notes_zh"])
    assert calls[0]["url"] == "https://llm.example.com/v1/chat/completions"
    assert calls[0]["headers"]["Authorization"] == "Bearer llm-test-token"
    assert calls[0]["body"]["model"] == "gpt-test"
    assert "llm-test-token" not in response.text

    turns_response = client.get("/v1/assistant/turns", headers=auth_headers(session))
    assert turns_response.status_code == 200
    turn = turns_response.json()[-1]
    assert turn["id"] == body["id"]
    assert turn["model_provider"] == "openai_compatible"
    assert turn["model_name"] == "gpt-test"
    assert turn["fallback_used"] is False


def test_theia_workbench_user_flow_reaches_paper_portfolio() -> None:
    register_response = client.post(
        "/v1/auth/accounts/register",
        json={
            "account_key": f"theia-flow-{uuid4().hex[:8]}",
            "account_name": "Theia 工作台测试账户",
            "password": "Dubhe@2026",
            "mfa_code": "000000",
            "device_name": "Dubhe Theia Desktop",
            "platform": "windows",
        },
    )
    assert register_response.status_code == 200
    session = register_response.json()

    feed_response = client.get("/v1/news/feed?market=US&symbol=NVDA&limit=3&live=false")
    assert feed_response.status_code == 200
    event = feed_response.json()["events"][0]

    analysis_response = client.post("/v1/news/analyze", json=event)
    assert analysis_response.status_code == 200
    analysis = analysis_response.json()

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

    backtest_response = client.post(
        "/v1/backtests/replay",
        json={
            "strategy": draft,
            "initial_cash": 100000,
            "replay_scenario": "golden_news_sentiment_v1",
        },
    )
    assert backtest_response.status_code == 200
    assert backtest_response.json()["final_equity"] > 100000

    paper_response = client.post(
        "/v1/simulation/paper-orders",
        headers=auth_headers(session),
        json={
            "account_id": "demo_account",
            "strategy_version_id": draft["strategy_version_id"],
            "market": "US",
            "symbol": "NVDA",
            "side": "buy",
            "order_type": "market",
            "quantity": 1,
            "estimated_price": 120,
            "currency": "USD",
            "created_by": "user",
            "destination": "paper",
            "rationale_zh": "Theia 工作台端到端烟测。",
            "source_refs": [analysis["id"]],
        },
    )
    assert paper_response.status_code == 200
    assert paper_response.json()["status"] == "accepted"

    portfolio_response = client.get(
        "/v1/simulation/paper-portfolio/demo_account",
        headers=auth_headers(session),
    )
    assert portfolio_response.status_code == 200
    portfolio = portfolio_response.json()
    assert portfolio["cash_by_currency"]["USD"] == 99880
    assert portfolio["positions"][0]["symbol"] == "NVDA"
    assert portfolio["positions"][0]["quantity"] == 1


def test_live_ai_order_requires_human_approval() -> None:
    session = register_test_device(
        account_key="approval-fixture",
        account_name="审批测试账户",
    )
    response = client.post(
        "/v1/risk/evaluate",
        headers=auth_headers(session),
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

    assert client.get("/v1/risk/decisions").status_code == 401

    list_response = client.get("/v1/risk/decisions", headers=auth_headers(session))
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
        headers=auth_headers(session),
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
    assert body["broker_order"] is None
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


def test_paper_order_submits_to_simulated_broker() -> None:
    session = register_test_device(
        account_key="paper-broker-fixture",
        account_name="纸面券商测试账户",
    )

    assert client.get("/v1/simulation/paper-orders").status_code == 401

    response = client.post(
        "/v1/simulation/paper-orders",
        headers=auth_headers(session),
        json={
            "account_id": "acct_fixture",
            "strategy_version_id": "strategy_v1",
            "market": "US",
            "symbol": "NVDA",
            "side": "buy",
            "order_type": "market",
            "quantity": 2,
            "estimated_price": 1000,
            "currency": "USD",
            "created_by": "strategy",
            "destination": "paper",
            "rationale_zh": "测试模拟券商成交。",
            "source_refs": ["analysis_fixture"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    broker_order = body["broker_order"]
    assert body["status"] == "accepted"
    assert body["message_zh"] == "纸面订单已通过模拟券商成交。当前版本不会连接真实券商。"
    assert broker_order["adapter"] == "simulated_paper"
    assert broker_order["status"] == "filled"
    assert broker_order["filled_quantity"] == 2
    assert broker_order["avg_fill_price"] == 1000
    assert broker_order["fills"][0]["notional"] == 2000
    assert broker_order["raw_response"]["real_broker"] is False

    broker_orders_response = client.get(
        "/v1/simulation/broker-orders",
        headers=auth_headers(session),
    )
    assert broker_orders_response.status_code == 200
    assert any(item["id"] == broker_order["id"] for item in broker_orders_response.json())

    portfolio_response = client.get(
        "/v1/simulation/paper-portfolio/acct_fixture",
        headers=auth_headers(session),
    )
    assert portfolio_response.status_code == 200
    portfolio = portfolio_response.json()
    assert portfolio["cash_by_currency"]["USD"] == 98000
    assert portfolio["equity_by_currency"]["USD"] == 100000
    assert portfolio["positions"][0]["symbol"] == "NVDA"
    assert portfolio["positions"][0]["quantity"] == 2
    assert portfolio["positions"][0]["avg_cost"] == 1000

    snapshot = client.get(
        f"/v1/workspaces/{session['workspace_id']}/snapshot",
        headers=auth_headers(session),
    ).json()
    assert any(item["account_id"] == "acct_fixture" for item in snapshot["paper_portfolios"])


def test_paper_sell_blocks_when_position_is_insufficient() -> None:
    session = register_test_device(
        account_key="paper-short-block-fixture",
        account_name="纸面空仓卖出测试账户",
    )

    response = client.post(
        "/v1/simulation/paper-orders",
        headers=auth_headers(session),
        json={
            "account_id": "short_block_fixture",
            "strategy_version_id": "strategy_v1",
            "market": "US",
            "symbol": "NVDA",
            "side": "sell",
            "order_type": "market",
            "quantity": 1,
            "estimated_price": 1000,
            "currency": "USD",
            "created_by": "strategy",
            "destination": "paper",
            "rationale_zh": "测试空仓卖出拦截。",
            "source_refs": ["analysis_fixture"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "blocked"
    assert body["broker_order"] is None
    assert "可卖数量 0" in body["risk_decision"]["reasons_zh"][-1]

    portfolio_response = client.get(
        "/v1/simulation/paper-portfolio/short_block_fixture",
        headers=auth_headers(session),
    )
    assert portfolio_response.status_code == 200
    portfolio = portfolio_response.json()
    assert portfolio["cash_by_currency"]["USD"] == 100000
    assert portfolio["positions"] == []


def test_paper_order_blocks_missing_source_refs() -> None:
    session = register_test_device(
        account_key="paper-block-fixture",
        account_name="纸面拦截测试账户",
    )
    response = client.post(
        "/v1/simulation/paper-orders",
        headers=auth_headers(session),
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
    assert body["broker_order"] is None

    list_response = client.get("/v1/simulation/paper-orders", headers=auth_headers(session))
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


def test_strategy_draft_save_emits_workspace_sync_event() -> None:
    session_response = client.post(
        "/v1/auth/accounts/register",
        json={
            "account_key": "strategy-workshop-sync-fixture",
            "account_name": "策略工坊同步测试账户",
            "password": "Dubhe@2026",
            "mfa_code": "000000",
            "device_name": "Dubhe Theia Desktop",
            "platform": "windows",
        },
    )
    assert session_response.status_code == 200
    session = session_response.json()

    response = client.post(
        "/v1/strategy/drafts",
        json={
            "name": "Blockly 新闻情绪策略",
            "spec": {
                "strategy_name": "Blockly 新闻情绪策略",
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
            "explanation_zh": "由 Blockly 策略工坊生成。",
            "generated_code": "strategy blockly",
            "source_analysis_id": "blockly_manual",
        },
    )

    assert response.status_code == 200
    draft = response.json()
    assert draft["id"].startswith("strategy_draft_")
    assert draft["strategy_version_id"].startswith("strategy_v_")

    list_response = client.get("/v1/strategy/drafts")
    assert list_response.status_code == 200
    assert any(item["id"] == draft["id"] for item in list_response.json())

    snapshot_response = client.get(
        f"/v1/workspaces/{session['workspace_id']}/snapshot",
        headers=auth_headers(session),
    )
    assert snapshot_response.status_code == 200
    snapshot = snapshot_response.json()
    assert any(item["id"] == draft["id"] for item in snapshot["strategy_drafts"])
    assert any(
        event["entity_type"] == "strategy_draft" and event["entity_id"] == draft["id"]
        for event in snapshot["events"]
    )
