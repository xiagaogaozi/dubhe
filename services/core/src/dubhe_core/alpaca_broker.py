from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from .models import (
    BrokerFill,
    BrokerOrder,
    BrokerOrderStatus,
    Market,
    NewsProviderStatus,
    OrderIntent,
    OrderType,
    ProviderStatus,
)


DEFAULT_ALPACA_PAPER_BASE_URL = "https://paper-api.alpaca.markets"


@dataclass(frozen=True)
class AlpacaPaperBrokerConfig:
    enabled: bool
    key_id: str
    secret_key: str
    base_url: str = DEFAULT_ALPACA_PAPER_BASE_URL
    timeout_seconds: float = 20.0

    @property
    def configured(self) -> bool:
        return bool(self.key_id and self.secret_key)


def load_alpaca_paper_config(source: dict[str, str] | None = None) -> AlpacaPaperBrokerConfig:
    env = source if source is not None else os.environ
    adapter = env.get("DUBHE_PAPER_BROKER", "").strip().lower()
    return AlpacaPaperBrokerConfig(
        enabled=adapter == "alpaca",
        key_id=env.get("ALPACA_PAPER_API_KEY_ID", "").strip(),
        secret_key=env.get("ALPACA_PAPER_SECRET_KEY", "").strip(),
        base_url=(
            env.get("ALPACA_PAPER_BASE_URL", "").strip().rstrip("/")
            or DEFAULT_ALPACA_PAPER_BASE_URL
        ),
        timeout_seconds=_float_env(env, "ALPACA_PAPER_TIMEOUT_SECONDS", 20.0),
    )


def active_paper_broker_adapter(source: dict[str, str] | None = None) -> str:
    config = load_alpaca_paper_config(source)
    if config.enabled and config.configured:
        return "alpaca_paper"
    return "simulated_paper"


def live_check_alpaca_paper_account() -> tuple[ProviderStatus, str]:
    config = load_alpaca_paper_config()
    if not config.configured:
        return ProviderStatus.SKIPPED, "未配置 Alpaca paper API Key。"
    try:
        body = _request_json(config, "GET", "/v2/account")
    except urllib.error.HTTPError as exc:
        return ProviderStatus.UNAVAILABLE, f"Alpaca paper 返回 HTTP {exc.code}。"
    except (urllib.error.URLError, TimeoutError) as exc:
        return ProviderStatus.UNAVAILABLE, f"Alpaca paper 连接失败或超时：{exc}。"
    except json.JSONDecodeError:
        return ProviderStatus.UNAVAILABLE, "Alpaca paper 返回了无法解析的 JSON。"

    status = str(body.get("status", "")).lower()
    account_id = str(body.get("id", "")).strip()
    if status in {"active", "account_updated"} or account_id:
        return ProviderStatus.OK, "Alpaca paper 账号 live 检查通过。"
    return ProviderStatus.UNAVAILABLE, "Alpaca paper 账号响应缺少可用状态。"


class AlpacaPaperBroker:
    adapter_name = "alpaca_paper"

    def __init__(self, config: AlpacaPaperBrokerConfig | None = None) -> None:
        self.config = config or load_alpaca_paper_config()

    def submit_order(self, intent: OrderIntent, paper_order_id: str) -> BrokerOrder:
        if intent.market != Market.US:
            return self._rejected_order(
                intent,
                paper_order_id,
                "Alpaca paper 适配器当前只支持美股标的。",
                {"reason": "unsupported_market"},
            )
        if not self.config.enabled or not self.config.configured:
            return self._rejected_order(
                intent,
                paper_order_id,
                "Alpaca paper 未配置完整 Key，无法提交券商沙盒订单。",
                {"reason": "missing_credentials"},
            )

        payload: dict[str, Any] = {
            "symbol": intent.symbol,
            "qty": _number_as_string(intent.quantity),
            "side": intent.side.value,
            "type": intent.order_type.value,
            "time_in_force": "day",
            "client_order_id": _client_order_id(paper_order_id),
        }
        if intent.order_type == OrderType.LIMIT and intent.limit_price is not None:
            payload["limit_price"] = _number_as_string(intent.limit_price)

        try:
            response = _request_json(self.config, "POST", "/v2/orders", payload)
        except urllib.error.HTTPError as exc:
            message = _read_http_error(exc)
            return self._rejected_order(
                intent,
                paper_order_id,
                f"Alpaca paper 拒绝订单：HTTP {exc.code}。",
                {"http_status": exc.code, "error": message},
            )
        except (urllib.error.URLError, TimeoutError) as exc:
            return self._rejected_order(
                intent,
                paper_order_id,
                f"Alpaca paper 连接失败或超时：{exc}。",
                {"error": str(exc)},
            )
        except json.JSONDecodeError:
            return self._rejected_order(
                intent,
                paper_order_id,
                "Alpaca paper 返回了无法解析的 JSON。",
                {"reason": "invalid_json"},
            )

        return self._order_from_response(intent, paper_order_id, response)

    def _order_from_response(
        self,
        intent: OrderIntent,
        paper_order_id: str,
        response: dict[str, Any],
    ) -> BrokerOrder:
        broker_status = _broker_status(str(response.get("status", "")))
        broker_order_id = str(response.get("id") or f"alpaca_{paper_order_id}")
        filled_quantity = _float_value(response.get("filled_qty"))
        avg_fill_price = _float_value(response.get("filled_avg_price"))
        submitted_at = _parse_datetime(response.get("submitted_at"))
        updated_at = _parse_datetime(response.get("updated_at")) or submitted_at
        fills: list[BrokerFill] = []
        if filled_quantity > 0 and avg_fill_price > 0:
            fills.append(
                BrokerFill(
                    broker_order_id=broker_order_id,
                    symbol=intent.symbol,
                    side=intent.side,
                    quantity=filled_quantity,
                    price=avg_fill_price,
                    notional=round(filled_quantity * avg_fill_price, 4),
                    commission=0,
                    filled_at=updated_at or submitted_at or datetime.now().astimezone(),
                )
            )
        return BrokerOrder(
            id=broker_order_id,
            paper_order_id=paper_order_id,
            order_intent_id=intent.id,
            adapter=self.adapter_name,
            broker_account_id=f"paper:{intent.account_id}",
            market=intent.market,
            symbol=intent.symbol,
            side=intent.side,
            quantity=intent.quantity,
            currency=intent.currency,
            status=broker_status,
            filled_quantity=filled_quantity,
            avg_fill_price=avg_fill_price if avg_fill_price > 0 else None,
            submitted_at=submitted_at or datetime.now().astimezone(),
            updated_at=updated_at or datetime.now().astimezone(),
            fills=fills,
            message_zh=_broker_message_zh(broker_status),
            raw_response={
                "adapter": self.adapter_name,
                "mode": "alpaca_paper",
                "real_broker": True,
                "paper_trading": True,
                "alpaca_order": _redact_alpaca_response(response),
            },
        )

    def _rejected_order(
        self,
        intent: OrderIntent,
        paper_order_id: str,
        message_zh: str,
        raw_response: dict[str, Any],
    ) -> BrokerOrder:
        return BrokerOrder(
            paper_order_id=paper_order_id,
            order_intent_id=intent.id,
            adapter=self.adapter_name,
            broker_account_id=f"paper:{intent.account_id}",
            market=intent.market,
            symbol=intent.symbol,
            side=intent.side,
            quantity=intent.quantity,
            currency=intent.currency,
            status=BrokerOrderStatus.REJECTED,
            message_zh=message_zh,
            raw_response={
                "adapter": self.adapter_name,
                "mode": "alpaca_paper",
                "real_broker": True,
                "paper_trading": True,
                **raw_response,
            },
        )


def alpaca_paper_provider_status() -> NewsProviderStatus:
    status, message = live_check_alpaca_paper_account()
    return NewsProviderStatus(
        provider="alpaca_paper_broker",
        status=status,
        message_zh=message,
    )


def _request_json(
    config: AlpacaPaperBrokerConfig,
    method: str,
    path: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = None
    headers = {
        "Accept": "application/json",
        "APCA-API-KEY-ID": config.key_id,
        "APCA-API-SECRET-KEY": config.secret_key,
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{config.base_url}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    with urllib.request.urlopen(request, timeout=config.timeout_seconds) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw)


def _broker_status(status: str) -> BrokerOrderStatus:
    normalized = status.lower()
    if normalized in {"filled"}:
        return BrokerOrderStatus.FILLED
    if normalized in {"rejected", "expired", "stopped", "suspended", "calculated"}:
        return BrokerOrderStatus.REJECTED
    if normalized in {"canceled"}:
        return BrokerOrderStatus.CANCELED
    return BrokerOrderStatus.ACCEPTED


def _broker_message_zh(status: BrokerOrderStatus) -> str:
    if status == BrokerOrderStatus.FILLED:
        return "Alpaca paper 已回报订单成交。"
    if status == BrokerOrderStatus.REJECTED:
        return "Alpaca paper 未接受该订单，请检查标的、数量、账户和市场状态。"
    if status == BrokerOrderStatus.CANCELED:
        return "Alpaca paper 订单已取消。"
    return "Alpaca paper 已接收沙盒订单，成交回报需在券商侧继续跟踪。"


def _redact_alpaca_response(response: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "id",
        "client_order_id",
        "created_at",
        "updated_at",
        "submitted_at",
        "filled_at",
        "expired_at",
        "canceled_at",
        "failed_at",
        "asset_id",
        "symbol",
        "asset_class",
        "qty",
        "filled_qty",
        "type",
        "side",
        "time_in_force",
        "limit_price",
        "stop_price",
        "filled_avg_price",
        "status",
        "extended_hours",
    }
    return {key: response[key] for key in allowed if key in response}


def _parse_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _float_value(value: Any) -> float:
    try:
        if value is None or value == "":
            return 0.0
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _number_as_string(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.8f}".rstrip("0").rstrip(".")


def _client_order_id(paper_order_id: str) -> str:
    return f"dubhe_{paper_order_id}"[:48]


def _read_http_error(exc: urllib.error.HTTPError) -> str:
    try:
        return exc.read().decode("utf-8")[:500]
    except Exception:  # noqa: BLE001 - best-effort diagnostics only.
        return ""


def _float_env(source: dict[str, str], key: str, default: float) -> float:
    try:
        return float(source.get(key, "").strip() or default)
    except ValueError:
        return default
