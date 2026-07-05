from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from .models import SmokeWorkflowReportResponse, SmokeWorkflowStep


def default_smoke_report_path() -> Path:
    return Path(__file__).resolve().parents[4] / ".dubhe-run" / "smoke-core-workflow.json"


def read_smoke_workflow_report(path: Path | None = None) -> SmokeWorkflowReportResponse:
    report_path = path or default_smoke_report_path()
    if not report_path.exists():
        return SmokeWorkflowReportResponse(
            available=False,
            status="missing",
            message_zh="尚未运行主链路烟测；可在运行 Core 后双击 Smoke-Dubhe.cmd 或执行 scripts\\smoke-core-workflow.ps1。",
            report_path=str(report_path),
        )

    try:
        payload = json.loads(report_path.read_text(encoding="utf-8-sig"))
        status = payload.get("status", "failed")
        if status not in {"passed", "failed"}:
            status = "failed"
        failure = _optional_string(payload.get("failure"))
        steps = [
            SmokeWorkflowStep.model_validate(step)
            for step in payload.get("steps", [])
            if isinstance(step, dict)
        ]
        message_zh = (
            "最近一次主链路烟测通过：账号、新闻、AI、策略、回测、纸面交易和同步链路均可用。"
            if status == "passed"
            else f"最近一次主链路烟测失败：{failure or '请查看报告里的失败步骤。'}"
        )
        return SmokeWorkflowReportResponse(
            available=True,
            status=status,
            message_zh=message_zh,
            generated_at=payload.get("generated_at"),
            core_url=str(payload.get("core_url", "")),
            market=str(payload.get("market", "")),
            symbol=str(payload.get("symbol", "")),
            failure=failure,
            report_path=str(payload.get("report_path") or report_path),
            artifacts=_dict(payload.get("artifacts")),
            steps=steps,
        )
    except (OSError, json.JSONDecodeError, TypeError, ValidationError) as exc:
        return SmokeWorkflowReportResponse(
            available=False,
            status="failed",
            message_zh=f"主链路烟测报告无法读取或解析：{exc}",
            failure=str(exc),
            report_path=str(report_path),
        )


def _optional_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value)
    return text if text else None


def _dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}
