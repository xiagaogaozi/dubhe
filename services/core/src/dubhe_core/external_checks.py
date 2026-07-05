from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from typing import Callable

from .llm import DEFAULT_OPENAI_COMPATIBLE_BASE_URL, load_llm_config
from .models import (
    ExternalServiceCheck,
    ExternalServiceCheckResponse,
    Market,
    NewsProviderStatus,
    ProviderStatus,
)
from .news_sources import (
    JsonFetcher,
    fetch_alpha_vantage_news_sentiment,
    fetch_finnhub_company_news,
    fetch_gdelt_articles,
    fetch_json,
    fetch_sec_edgar_filings,
)

LLMConnectivityChecker = Callable[[], tuple[ProviderStatus, str]]


def external_service_checks(
    *,
    live: bool,
    fetcher: JsonFetcher | None = None,
    llm_checker: LLMConnectivityChecker | None = None,
) -> ExternalServiceCheckResponse:
    http_fetcher = fetcher or fetch_json
    checks = [
        _check_llm(live=live, checker=llm_checker),
        _check_finnhub(live=live, fetcher=http_fetcher),
        _check_alpha_vantage(live=live, fetcher=http_fetcher),
        _check_sec(live=live, fetcher=http_fetcher),
        _check_gdelt(live=live, fetcher=http_fetcher),
    ]
    ready_count = sum(1 for item in checks if item.status == ProviderStatus.OK)
    unavailable_count = sum(
        1 for item in checks if item.status == ProviderStatus.UNAVAILABLE
    )
    configured_count = sum(1 for item in checks if item.configured)
    if ready_count == len(checks):
        overall_status = "ready"
        message = "所有外部服务检查通过。"
    elif unavailable_count > 0:
        overall_status = "partial"
        message = "部分外部服务连接失败；Dubhe 仍会使用可用源和本地兜底。"
    elif configured_count == 0:
        overall_status = "action_required"
        message = "尚未配置真实 AI 或授权新闻源；当前只能使用公开/演示兜底。"
    else:
        overall_status = "partial"
        message = "已配置部分外部服务；未配置项会在实时流程中跳过。"

    return ExternalServiceCheckResponse(
        live=live,
        overall_status=overall_status,
        ready_count=ready_count,
        total_count=len(checks),
        checks=checks,
        message_zh=message,
    )


def _check_llm(
    *,
    live: bool,
    checker: LLMConnectivityChecker | None,
) -> ExternalServiceCheck:
    config = load_llm_config()
    configured = config.enabled
    if not configured:
        if config.model and config.base_url == DEFAULT_OPENAI_COMPATIBLE_BASE_URL and not config.api_key:
            message = "已填写模型名，但 OpenAI 官方地址需要 DUBHE_LLM_API_KEY。"
        elif config.model:
            message = "AI 模型配置不完整，当前会使用本地确定性兜底。"
        else:
            message = "未配置外部 AI 模型，当前会使用本地确定性兜底。"
        return _result(
            service="llm_openai_compatible",
            label_zh="AI 模型 OpenAI-compatible",
            configured=False,
            live_checked=False,
            status=ProviderStatus.SKIPPED,
            message_zh=message,
            next_step_zh="在 Configure-Dubhe.cmd 或客户端配置页填写模型名、地址和 API Key；本地无鉴权模型可不填 Key。",
        )

    if not live:
        return _result(
            service="llm_openai_compatible",
            label_zh="AI 模型 OpenAI-compatible",
            configured=True,
            live_checked=False,
            status=ProviderStatus.SKIPPED,
            message_zh="已配置 AI 模型；本次未发起 live 检查。",
            next_step_zh="需要验证连接时运行 live 外部服务体检；这可能消耗极少量模型调用额度。",
        )

    started = time.perf_counter()
    try:
        status, message = (checker or _live_check_llm)()
    except Exception as exc:  # noqa: BLE001 - user-facing diagnostics must not crash.
        status = ProviderStatus.UNAVAILABLE
        message = f"AI 模型连接失败：{exc}"
    return _result(
        service="llm_openai_compatible",
        label_zh="AI 模型 OpenAI-compatible",
        configured=True,
        live_checked=True,
        status=status,
        duration_ms=_elapsed_ms(started),
        message_zh=message,
        next_step_zh="失败时检查模型名、base URL、API Key、代理和本地模型网关是否正在运行。",
    )


def _live_check_llm() -> tuple[ProviderStatus, str]:
    config = load_llm_config()
    payload = {
        "model": config.model,
        "messages": [
            {"role": "system", "content": "只回复 OK。"},
            {"role": "user", "content": "OK"},
        ],
        "temperature": 0,
        "max_tokens": 8,
    }
    headers = {"Content-Type": "application/json"}
    if config.api_key:
        headers["Authorization"] = f"Bearer {config.api_key}"
    request = urllib.request.Request(
        config.endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=min(config.timeout_seconds, 12)) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return ProviderStatus.UNAVAILABLE, f"模型服务返回 HTTP {exc.code}。"
    except (urllib.error.URLError, TimeoutError) as exc:
        return ProviderStatus.UNAVAILABLE, f"模型服务连接失败或超时：{exc}。"

    try:
        body = json.loads(raw)
        content = body["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        return ProviderStatus.UNAVAILABLE, "模型服务响应格式不符合 OpenAI-compatible chat/completions。"
    if not isinstance(content, str) or not content.strip():
        return ProviderStatus.UNAVAILABLE, "模型服务返回空内容。"
    return ProviderStatus.OK, "AI 模型 live 检查通过。"


def _check_finnhub(*, live: bool, fetcher: JsonFetcher) -> ExternalServiceCheck:
    configured = _env_configured("FINNHUB_API_KEY")
    if not configured:
        return _result(
            service="finnhub_company_news",
            label_zh="Finnhub 公司新闻",
            configured=False,
            live_checked=False,
            status=ProviderStatus.SKIPPED,
            message_zh="未配置 FINNHUB_API_KEY。",
            next_step_zh="用于美股公司新闻；生产前确认套餐、缓存、展示和 AI 处理授权。",
        )
    if not live:
        return _configured_but_not_live(
            service="finnhub_company_news",
            label_zh="Finnhub 公司新闻",
            next_step_zh="运行 live 外部服务体检，验证 key 是否能拉取 NVDA company-news。",
        )
    started = time.perf_counter()
    _events, status = fetch_finnhub_company_news(
        market=Market.US,
        symbol="NVDA",
        limit=1,
        fetcher=fetcher,
    )
    return _from_provider_status(
        status,
        label_zh="Finnhub 公司新闻",
        configured=True,
        duration_ms=_elapsed_ms(started),
        next_step_zh="失败时检查 FINNHUB_API_KEY、套餐权限和网络；没有新闻返回也可能是供应商当期无数据。",
    )


def _check_alpha_vantage(*, live: bool, fetcher: JsonFetcher) -> ExternalServiceCheck:
    configured = _env_configured("ALPHA_VANTAGE_API_KEY")
    if not configured:
        return _result(
            service="alpha_vantage_news_sentiment",
            label_zh="Alpha Vantage 新闻情绪",
            configured=False,
            live_checked=False,
            status=ProviderStatus.SKIPPED,
            message_zh="未配置 ALPHA_VANTAGE_API_KEY。",
            next_step_zh="用于新闻情绪和 ticker 语境；生产前确认授权、频率限制和 AI 使用条款。",
        )
    if not live:
        return _configured_but_not_live(
            service="alpha_vantage_news_sentiment",
            label_zh="Alpha Vantage 新闻情绪",
            next_step_zh="运行 live 外部服务体检，验证 NEWS_SENTIMENT 是否可用。",
        )
    started = time.perf_counter()
    _events, status = fetch_alpha_vantage_news_sentiment(
        market=Market.US,
        symbol="NVDA",
        limit=1,
        fetcher=fetcher,
    )
    return _from_provider_status(
        status,
        label_zh="Alpha Vantage 新闻情绪",
        configured=True,
        duration_ms=_elapsed_ms(started),
        next_step_zh="失败时检查 ALPHA_VANTAGE_API_KEY、频率限制、套餐权限和网络。",
    )


def _check_sec(*, live: bool, fetcher: JsonFetcher) -> ExternalServiceCheck:
    configured = _env_configured("DUBHE_SEC_USER_AGENT")
    if not live:
        return _result(
            service="sec_edgar",
            label_zh="SEC EDGAR 公告",
            configured=configured,
            live_checked=False,
            status=ProviderStatus.SKIPPED,
            message_zh=(
                "已配置 SEC User-Agent；本次未发起 live 检查。"
                if configured
                else "未配置 SEC User-Agent；开发默认值可用，生产必须换成真实联系人。"
            ),
            next_step_zh="运行 live 外部服务体检，验证 SEC submissions 接口是否可访问。",
        )
    started = time.perf_counter()
    _events, status = fetch_sec_edgar_filings(
        market=Market.US,
        symbol="NVDA",
        limit=1,
        fetcher=fetcher,
    )
    return _from_provider_status(
        status,
        label_zh="SEC EDGAR 公告",
        configured=configured,
        duration_ms=_elapsed_ms(started),
        next_step_zh="生产版请配置真实产品名和联系人邮箱；失败时检查网络、频率和 SEC 访问策略。",
    )


def _check_gdelt(*, live: bool, fetcher: JsonFetcher) -> ExternalServiceCheck:
    if not live:
        return _result(
            service="gdelt_doc",
            label_zh="GDELT 全球新闻索引",
            configured=True,
            live_checked=False,
            status=ProviderStatus.SKIPPED,
            message_zh="GDELT 公开新闻索引无需本地 key；本次未发起 live 检查。",
            next_step_zh="运行 live 外部服务体检，验证全球新闻索引是否可访问。",
        )
    started = time.perf_counter()
    _events, status = fetch_gdelt_articles(
        market=Market.GLOBAL,
        symbol=None,
        limit=1,
        fetcher=fetcher,
    )
    return _from_provider_status(
        status,
        label_zh="GDELT 全球新闻索引",
        configured=True,
        duration_ms=_elapsed_ms(started),
        next_step_zh="GDELT 只提供索引和链接，不代表原文转载、缓存或 AI 处理授权。",
    )


def _configured_but_not_live(
    *,
    service: str,
    label_zh: str,
    next_step_zh: str,
) -> ExternalServiceCheck:
    return _result(
        service=service,
        label_zh=label_zh,
        configured=True,
        live_checked=False,
        status=ProviderStatus.SKIPPED,
        message_zh="已配置；本次未发起 live 检查。",
        next_step_zh=next_step_zh,
    )


def _from_provider_status(
    status: NewsProviderStatus,
    *,
    label_zh: str,
    configured: bool,
    duration_ms: int,
    next_step_zh: str,
) -> ExternalServiceCheck:
    return _result(
        service=status.provider,
        label_zh=label_zh,
        configured=configured,
        live_checked=True,
        status=status.status,
        duration_ms=duration_ms,
        message_zh=status.message_zh,
        next_step_zh=next_step_zh,
    )


def _result(
    *,
    service: str,
    label_zh: str,
    configured: bool,
    live_checked: bool,
    status: ProviderStatus,
    message_zh: str,
    next_step_zh: str,
    duration_ms: int = 0,
) -> ExternalServiceCheck:
    return ExternalServiceCheck(
        service=service,
        label_zh=label_zh,
        configured=configured,
        live_checked=live_checked,
        status=status,
        duration_ms=duration_ms,
        message_zh=message_zh,
        next_step_zh=next_step_zh,
    )


def _env_configured(key: str) -> bool:
    return bool(os.environ.get(key, "").strip())


def _elapsed_ms(started: float) -> int:
    return max(0, int((time.perf_counter() - started) * 1000))
