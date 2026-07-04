from __future__ import annotations

from .models import StrategySpec, StrategyValidationResult


def validate_strategy_spec(spec: StrategySpec) -> StrategyValidationResult:
    reasons: list[str] = []

    if "max_order_notional" not in spec.risk_limits:
        reasons.append("缺少 `max_order_notional` 风控限制。")

    if not spec.data_dependencies:
        reasons.append("缺少数据依赖声明，例如 news、market_bars 或 filings。")

    if not spec.broker_permissions:
        reasons.append("缺少券商权限声明，至少应声明 paper。")

    return StrategyValidationResult(valid=not reasons, reasons_zh=reasons)

