from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Mapping

from .models import (
    AssistantChatRequest,
    AssistantChatResponse,
    BacktestResult,
    LLMRuntimeStatus,
    NewsAnalysis,
    NewsEvent,
    StrategyDraft,
)

DEFAULT_OPENAI_COMPATIBLE_BASE_URL = "https://api.openai.com/v1"
MANDATORY_SAFETY_NOTES = [
    "AI 模型输出仅供研究讨论，不能作为实盘下单指令。",
    "真实订单必须经过确定性风控、审计记录和人工审批。",
]


class LLMUnavailable(RuntimeError):
    def __init__(self, reason_zh: str) -> None:
        super().__init__(reason_zh)
        self.reason_zh = reason_zh


@dataclass(frozen=True)
class LLMConfig:
    provider: str
    base_url: str
    model: str
    api_key: str
    timeout_seconds: float
    max_tokens: int
    temperature: float

    @property
    def enabled(self) -> bool:
        if not self.model or not self.base_url:
            return False
        if self.base_url == DEFAULT_OPENAI_COMPATIBLE_BASE_URL and not self.api_key:
            return False
        return True

    @property
    def endpoint(self) -> str:
        base_url = self.base_url.rstrip("/")
        if base_url.endswith("/chat/completions"):
            return base_url
        return f"{base_url}/chat/completions"


def load_llm_config(env: Mapping[str, str] | None = None) -> LLMConfig:
    source = env or os.environ
    model = source.get("DUBHE_LLM_MODEL", "").strip()
    api_key = source.get("DUBHE_LLM_API_KEY", "").strip()
    configured_base_url = source.get("DUBHE_LLM_BASE_URL", "").strip()
    base_url = configured_base_url or (DEFAULT_OPENAI_COMPATIBLE_BASE_URL if model else "")
    provider = source.get("DUBHE_LLM_PROVIDER", "").strip() or "openai_compatible"
    timeout_seconds = _float_env(source, "DUBHE_LLM_TIMEOUT_SECONDS", default=20.0)
    max_tokens = _int_env(source, "DUBHE_LLM_MAX_TOKENS", default=900)
    temperature = _float_env(source, "DUBHE_LLM_TEMPERATURE", default=0.2)
    return LLMConfig(
        provider=provider,
        base_url=base_url,
        model=model,
        api_key=api_key,
        timeout_seconds=max(1.0, timeout_seconds),
        max_tokens=max(128, min(max_tokens, 4096)),
        temperature=max(0.0, min(temperature, 1.0)),
    )


def llm_runtime_status(env: Mapping[str, str] | None = None) -> LLMRuntimeStatus:
    config = load_llm_config(env)
    if config.enabled:
        message = "已启用 OpenAI-compatible 模型路由；失败时会自动回退到本地安全兜底。"
    elif (
        config.model
        and config.base_url == DEFAULT_OPENAI_COMPATIBLE_BASE_URL
        and not config.api_key
    ):
        message = "已填写模型名但缺少 DUBHE_LLM_API_KEY，当前使用本地安全兜底。"
    elif config.model and config.base_url:
        message = "模型路由配置不完整，当前使用本地安全兜底。"
    else:
        message = "未配置外部模型，当前使用本地确定性安全兜底。"
    return LLMRuntimeStatus(
        provider=config.provider,
        model=config.model or None,
        configured=bool(config.model and config.base_url),
        enabled=config.enabled,
        fallback_available=True,
        message_zh=message,
    )


def answer_with_configured_llm(
    request: AssistantChatRequest,
    fallback: AssistantChatResponse,
) -> AssistantChatResponse:
    config = load_llm_config()
    if not config.enabled:
        return fallback

    try:
        content = _call_chat_completions(config, request)
        parsed = _parse_model_content(content)
    except LLMUnavailable as exc:
        return fallback.model_copy(
            update={
                "answer_zh": f"外部模型暂时不可用（{exc.reason_zh}），已使用本地安全兜底。\n\n{fallback.answer_zh}",
                "safety_notes_zh": _unique_strings(
                    [*fallback.safety_notes_zh, *MANDATORY_SAFETY_NOTES]
                ),
                "model_provider": config.provider,
                "model_name": config.model,
                "fallback_used": True,
            }
        )

    answer = _string_value(parsed.get("answer_zh")) or content.strip()
    suggested_actions = _string_list(parsed.get("suggested_actions_zh"))
    safety_notes = _unique_strings(
        [
            *_string_list(parsed.get("safety_notes_zh")),
            *fallback.safety_notes_zh,
            *MANDATORY_SAFETY_NOTES,
        ]
    )
    return fallback.model_copy(
        update={
            "answer_zh": answer,
            "suggested_actions_zh": suggested_actions or fallback.suggested_actions_zh,
            "safety_notes_zh": safety_notes,
            "model_provider": config.provider,
            "model_name": config.model,
            "fallback_used": False,
        }
    )


def _call_chat_completions(config: LLMConfig, request: AssistantChatRequest) -> str:
    payload = {
        "model": config.model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是 Dubhe 的中文金融研究助手。你只能做研究解释、风险提示、"
                    "策略验证建议和纸面验证建议，不能给出绕过风控的实盘下单指令。"
                    "请返回一个纯 JSON 对象，字段为 answer_zh、suggested_actions_zh、safety_notes_zh。"
                ),
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "question_zh": request.question_zh,
                        "context": _context_for_model(request),
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
            },
        ],
        "temperature": config.temperature,
        "max_tokens": config.max_tokens,
    }
    headers = {"Content-Type": "application/json"}
    if config.api_key:
        headers["Authorization"] = f"Bearer {config.api_key}"
    api_request = urllib.request.Request(
        config.endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(api_request, timeout=config.timeout_seconds) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise LLMUnavailable(f"模型服务返回 HTTP {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise LLMUnavailable("模型服务连接失败或超时") from exc

    try:
        body = json.loads(raw)
        content = body["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as exc:
        raise LLMUnavailable("模型服务响应格式不符合 OpenAI-compatible 约定") from exc
    if not isinstance(content, str) or not content.strip():
        raise LLMUnavailable("模型服务返回空内容")
    return content


def _context_for_model(request: AssistantChatRequest) -> dict[str, Any]:
    context = request.context
    return {
        "news_event": _news_event_context(context.news_event),
        "analysis": _analysis_context(context.analysis),
        "strategy": _strategy_context(context.strategy),
        "backtest": _backtest_context(context.backtest),
    }


def _news_event_context(event: NewsEvent | None) -> dict[str, Any] | None:
    if event is None:
        return None
    return {
        "id": event.id,
        "source_name": event.source_name,
        "market_scope": [market.value for market in event.market_scope],
        "title_original": event.title_original,
        "title_zh": event.title_zh,
        "published_at": event.published_at.isoformat(),
        "url": event.url,
        "tickers": event.tickers,
        "event_type": event.event_type,
        "authority_score": event.authority_score,
    }


def _analysis_context(analysis: NewsAnalysis | None) -> dict[str, Any] | None:
    if analysis is None:
        return None
    return {
        "id": analysis.id,
        "news_event_id": analysis.news_event_id,
        "summary_zh": analysis.summary_zh,
        "sentiment": analysis.sentiment.value,
        "impact_score": analysis.impact_score,
        "affected_tickers": analysis.affected_tickers,
        "source_refs": analysis.source_refs,
        "confidence": analysis.confidence,
    }


def _strategy_context(strategy: StrategyDraft | None) -> dict[str, Any] | None:
    if strategy is None:
        return None
    return {
        "id": strategy.id,
        "strategy_version_id": strategy.strategy_version_id,
        "name": strategy.name,
        "spec": strategy.spec.model_dump(mode="json"),
        "explanation_zh": strategy.explanation_zh,
        "generated_code_excerpt": strategy.generated_code[:2000],
        "source_analysis_id": strategy.source_analysis_id,
    }


def _backtest_context(backtest: BacktestResult | None) -> dict[str, Any] | None:
    if backtest is None:
        return None
    return {
        "id": backtest.id,
        "strategy_version_id": backtest.strategy_version_id,
        "replay_scenario": backtest.replay_scenario,
        "symbol": backtest.symbol,
        "market": backtest.market.value,
        "initial_cash": backtest.initial_cash,
        "final_equity": backtest.final_equity,
        "total_return": backtest.total_return,
        "benchmark_return": backtest.benchmark_return,
        "max_drawdown": backtest.max_drawdown,
        "win_rate": backtest.win_rate,
        "trade_count": backtest.trade_count,
        "risk_notes_zh": backtest.risk_notes_zh,
    }


def _parse_model_content(content: str) -> dict[str, Any]:
    stripped = content.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].startswith("```"):
            lines = lines[:-1]
        stripped = "\n".join(lines).strip()
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _string_value(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip()


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item.strip() for item in value if isinstance(item, str) and item.strip()][:5]


def _unique_strings(values: list[str]) -> list[str]:
    seen = set()
    result = []
    for value in values:
        normalized = value.strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        result.append(normalized)
    return result


def _float_env(source: Mapping[str, str], key: str, default: float) -> float:
    try:
        return float(source.get(key, "") or default)
    except ValueError:
        return default


def _int_env(source: Mapping[str, str], key: str, default: int) -> int:
    try:
        return int(source.get(key, "") or default)
    except ValueError:
        return default
