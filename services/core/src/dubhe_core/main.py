from __future__ import annotations

import asyncio
import os
from datetime import datetime, timezone
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .analysis import analyze_news
from .assistant import answer_research_question
from .backtest import draft_strategy_from_analysis, run_replay_backtest
from .external_checks import external_service_checks
from .models import (
    AccountLoginRequest,
    AccountRegistrationRequest,
    AssistantChatRequest,
    AssistantChatResponse,
    AssistantContext,
    AssistantConversationTurn,
    AuditLogEntry,
    ApprovalActionRequest,
    ApprovalRequest,
    ApprovalStatus,
    BacktestRequest,
    BacktestResult,
    BrokerOrder,
    DeviceRevocation,
    ExternalServiceCheckResponse,
    InstallPackageStatus,
    KillSwitchState,
    KillSwitchUpdateRequest,
    LocalLauncherStatus,
    LocalRuntimeConfigResponse,
    LocalRuntimeConfigUpdateRequest,
    NewsAnalysis,
    NewsAdapterRuntimeStatus,
    NewsEvent,
    NewsFeedResponse,
    NewsMarketCoverageStatus,
    OnboardingChecklistResponse,
    OnboardingStep,
    OnboardingStepStatus,
    OrderIntent,
    OrderSide,
    PaperOrder,
    PaperOrderStatus,
    PaperPortfolioSnapshot,
    ProductionReadinessResponse,
    RiskDecision,
    RiskStatus,
    RuntimeConfigStatus,
    SmokeWorkflowReportResponse,
    DeviceRegistrationRequest,
    DeviceSession,
    Market,
    AuthRuntimeStatus,
    StrategySpec,
    StrategyDraft,
    StrategyDraftRequest,
    StrategyTemplate,
    StrategyTemplateDraftRequest,
    StrategyValidationResult,
    StorageRuntimeStatus,
    SyncEvent,
    SystemStatusResponse,
    TradingRuntimeStatus,
    UserRole,
    UserRoleUpdateRequest,
    UserSummary,
    WatchlistItem,
    WatchlistUpsertRequest,
    WorkspaceSnapshot,
)
from .llm import llm_runtime_status
from .news_sources import fetch_news_feed
from .production_readiness import production_readiness_response
from .risk import evaluate_order_intent
from .runtime_config import local_runtime_config_response, repo_root, update_local_runtime_config
from .simulation import submit_paper_order
from .smoke_report import read_smoke_workflow_report
from .store import store
from .strategy import (
    draft_strategy_from_template,
    list_strategy_templates,
    validate_strategy_spec,
)

SYNC_WEBSOCKET_POLL_SECONDS = 0.25
CORE_VERSION = "0.1.0"

app = FastAPI(
    title="Dubhe Core",
    version=CORE_VERSION,
    description="中文优先的 AI 投资研究与受控量化交易后端 API。",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://127.0.0.1:3000",
        "http://localhost:3000",
        "http://127.0.0.1:5173",
        "http://localhost:5173",
    ],
    allow_origin_regex=r"https?://(127\.0\.0\.1|localhost)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "dubhe-core"}


@app.get("/v1/system/status", response_model=SystemStatusResponse)
def system_status() -> SystemStatusResponse:
    finnhub_configured = env_is_configured("FINNHUB_API_KEY")
    alpha_configured = env_is_configured("ALPHA_VANTAGE_API_KEY")
    sec_user_agent_configured = env_is_configured("DUBHE_SEC_USER_AGENT")
    llm_model_configured = env_is_configured("DUBHE_LLM_MODEL")
    llm_base_url_configured = env_is_configured("DUBHE_LLM_BASE_URL")
    llm_api_key_configured = env_is_configured("DUBHE_LLM_API_KEY")
    llm_status = llm_runtime_status()
    persistent_storage = store.db_path != ":memory:"
    news_adapters = [
        NewsAdapterRuntimeStatus(
            provider="finnhub_company_news",
            label_zh="Finnhub 公司新闻",
            market_coverage=[Market.US, Market.GLOBAL],
            configured=finnhub_configured,
            enabled=finnhub_configured,
            requires_license=True,
            message_zh=(
                "已就绪：需要遵守 Finnhub 套餐和合同条款。"
                if finnhub_configured
                else "待配置：缺少 FINNHUB_API_KEY，实时拉取时会跳过。"
            ),
        ),
        NewsAdapterRuntimeStatus(
            provider="alpha_vantage_news_sentiment",
            label_zh="Alpha Vantage 新闻情绪",
            market_coverage=[Market.US, Market.GLOBAL],
            configured=alpha_configured,
            enabled=alpha_configured,
            requires_license=True,
            message_zh=(
                "已就绪：需要遵守 Alpha Vantage 套餐和合同条款。"
                if alpha_configured
                else "待配置：缺少 ALPHA_VANTAGE_API_KEY，实时拉取时会跳过。"
            ),
        ),
        NewsAdapterRuntimeStatus(
            provider="sec_edgar",
            label_zh="SEC EDGAR 公告",
            market_coverage=[Market.US, Market.GLOBAL],
            configured=sec_user_agent_configured,
            enabled=True,
            requires_license=False,
            message_zh=(
                "可用：已配置专用 User-Agent。"
                if sec_user_agent_configured
                else "可用：当前使用开发默认 User-Agent，生产版应补充联系人。"
            ),
        ),
        NewsAdapterRuntimeStatus(
            provider="gdelt_doc",
            label_zh="GDELT 全球新闻索引",
            market_coverage=[Market.A_SHARE, Market.HK, Market.US, Market.GLOBAL],
            configured=True,
            enabled=True,
            requires_license=False,
            message_zh="可用：作为公开全球新闻索引和兜底上下文，不代表原文转载授权。",
        ),
        NewsAdapterRuntimeStatus(
            provider="fixture",
            label_zh="本地演示新闻源",
            market_coverage=[Market.A_SHARE, Market.HK, Market.US, Market.GLOBAL],
            configured=True,
            enabled=True,
            requires_license=False,
            message_zh="可用：真实来源为空或故障时兜底，保证分析、回测和纸面交易链路可测试。",
        ),
    ]

    return SystemStatusResponse(
        service="dubhe-core",
        version=CORE_VERSION,
        storage=StorageRuntimeStatus(
            backend="sqlite",
            path=store.db_path,
            persistent=persistent_storage,
            message_zh=(
                "SQLite 持久化存储已启用。"
                if persistent_storage
                else "当前使用内存数据库，服务重启后数据会丢失。"
            ),
        ),
        auth=AuthRuntimeStatus(
            mode="local_dev",
            mfa_mode="local_placeholder",
            message_zh="当前为本地开发认证：账号密码、设备令牌、角色权限和占位 MFA。生产版需替换为 OIDC/MFA。",
        ),
        config_items=[
            RuntimeConfigStatus(
                key="FINNHUB_API_KEY",
                label_zh="Finnhub 授权新闻源 Key",
                configured=finnhub_configured,
                required_for="Finnhub company-news 美股公司新闻",
                message_zh=(
                    "已配置，刷新实时美股新闻时会尝试调用 Finnhub。"
                    if finnhub_configured
                    else "未配置，Finnhub 授权新闻源会被跳过。"
                ),
            ),
            RuntimeConfigStatus(
                key="ALPHA_VANTAGE_API_KEY",
                label_zh="Alpha Vantage 新闻情绪 Key",
                configured=alpha_configured,
                required_for="Alpha Vantage NEWS_SENTIMENT 新闻情绪",
                message_zh=(
                    "已配置，刷新实时新闻时会尝试调用 Alpha Vantage。"
                    if alpha_configured
                    else "未配置，Alpha Vantage 新闻情绪源会被跳过。"
                ),
            ),
            RuntimeConfigStatus(
                key="DUBHE_SEC_USER_AGENT",
                label_zh="SEC EDGAR User-Agent",
                configured=sec_user_agent_configured,
                required_for="SEC EDGAR 官方接口礼貌访问",
                message_zh=(
                    "已配置 SEC EDGAR User-Agent。"
                    if sec_user_agent_configured
                    else "未配置，将使用开发默认 User-Agent；生产版应配置真实联系人。"
                ),
            ),
            RuntimeConfigStatus(
                key="DUBHE_LLM_MODEL",
                label_zh="AI 模型名称",
                configured=llm_model_configured,
                required_for="OpenAI-compatible AI 分析师模型路由",
                message_zh=(
                    f"已配置模型：{llm_status.model}。"
                    if llm_model_configured
                    else "未配置，将使用本地确定性安全兜底。"
                ),
            ),
            RuntimeConfigStatus(
                key="DUBHE_LLM_BASE_URL",
                label_zh="AI 模型 OpenAI-compatible 地址",
                configured=llm_base_url_configured,
                required_for="本地模型、代理网关或非 OpenAI 官方端点",
                message_zh=(
                    "已配置自定义模型地址。"
                    if llm_base_url_configured
                    else "未配置；填写模型名时默认使用 OpenAI 官方 /v1 地址。"
                ),
            ),
            RuntimeConfigStatus(
                key="DUBHE_LLM_API_KEY",
                label_zh="AI 模型 API Key",
                configured=llm_api_key_configured,
                required_for="OpenAI 官方或需要鉴权的兼容模型服务",
                message_zh=(
                    "已配置；体检不会泄露 Key 内容。"
                    if llm_api_key_configured
                    else "未配置；本地无鉴权模型可不填，OpenAI 官方端点必须填写。"
                ),
            ),
        ],
        news_adapters=news_adapters,
        news_coverage=build_news_coverage(news_adapters),
        install_packages=build_install_package_status(repo_root()),
        local_launchers=build_local_launcher_status(repo_root()),
        llm=llm_status,
        trading=TradingRuntimeStatus(
            paper_broker_enabled=True,
            live_trading_enabled=False,
            message_zh="纸面交易和模拟 broker 已启用；实盘交易保持关闭，需完成券商适配、签名、审批、审计和风控后才能开放。",
        ),
    )


def build_news_coverage(
    adapters: list[NewsAdapterRuntimeStatus],
) -> list[NewsMarketCoverageStatus]:
    markets = [Market.A_SHARE, Market.HK, Market.US, Market.GLOBAL]
    enabled_by_market = {
        market: [
            adapter
            for adapter in adapters
            if adapter.enabled and market in adapter.market_coverage
        ]
        for market in markets
    }
    licensed_by_market = {
        market: [
            adapter
            for adapter in enabled_by_market[market]
            if adapter.requires_license
        ]
        for market in markets
    }

    def available_names(market: Market) -> list[str]:
        return [adapter.label_zh for adapter in enabled_by_market[market]]

    return [
        NewsMarketCoverageStatus(
            market=Market.A_SHARE,
            label_zh="A 股",
            demo_ready=bool(enabled_by_market[Market.A_SHARE]),
            licensed_source_ready=False,
            production_ready=False,
            available_sources_zh=available_names(Market.A_SHARE),
            missing_sources_zh=["Wind", "同花顺 iFinD", "Choice", "财联社授权快讯"],
            message_zh="当前可用公开全球索引和本地演示源，适合流程测试；尚未接入可生产使用的 A 股授权快讯、公告和研报源。",
            next_step_zh="生产部署前需要签约 A 股数据/新闻供应商，并补充对应 adapter、授权范围和审计记录。",
        ),
        NewsMarketCoverageStatus(
            market=Market.HK,
            label_zh="港股",
            demo_ready=bool(enabled_by_market[Market.HK]),
            licensed_source_ready=False,
            production_ready=False,
            available_sources_zh=available_names(Market.HK),
            missing_sources_zh=["HKEXnews / HKEX IIS", "AASTOCKS 授权新闻", "ET Net 授权新闻"],
            message_zh="当前可用公开全球索引和本地演示源，适合流程测试；尚未接入港交所公告和港股授权新闻源。",
            next_step_zh="生产部署前需要确认 HKEX 与港股新闻供应商条款，接入公告、快讯和延迟/实时权限。",
        ),
        NewsMarketCoverageStatus(
            market=Market.US,
            label_zh="美股",
            demo_ready=bool(enabled_by_market[Market.US]),
            licensed_source_ready=bool(licensed_by_market[Market.US]),
            production_ready=False,
            available_sources_zh=available_names(Market.US),
            missing_sources_zh=[
                "Benzinga / Dow Jones / Polygon 等商业新闻合同",
                *(
                    []
                    if licensed_by_market[Market.US]
                    else ["FINNHUB_API_KEY", "ALPHA_VANTAGE_API_KEY"]
                ),
            ],
            message_zh=(
                "已接入美股公开公告/全球索引，并检测到至少一个授权新闻 API key；仍需按合同确认正文展示、缓存和 AI 处理范围。"
                if licensed_by_market[Market.US]
                else "已接入 SEC EDGAR、GDELT 和本地演示源；缺少 Finnhub/Alpha Vantage 等授权新闻 key。"
            ),
            next_step_zh="补齐授权新闻 key 后，生产前仍需保存供应商合同、调用频率、缓存和 AI 使用许可结论。",
        ),
        NewsMarketCoverageStatus(
            market=Market.GLOBAL,
            label_zh="全球宏观",
            demo_ready=bool(enabled_by_market[Market.GLOBAL]),
            licensed_source_ready=bool(licensed_by_market[Market.GLOBAL]),
            production_ready=False,
            available_sources_zh=available_names(Market.GLOBAL),
            missing_sources_zh=["机构级全球新闻线", "宏观日历与央行公告授权源"],
            message_zh="当前可用 GDELT 全球新闻索引和演示源；若配置美股授权源，也可补充部分全球 ticker 语境。",
            next_step_zh="生产部署前需要接入机构级全球新闻、宏观日历和公告源，并逐项记录授权边界。",
        ),
    ]


def build_install_package_status(root: Path) -> list[InstallPackageStatus]:
    desktop_dist = root / "apps" / "theia-desktop" / "app" / "dist"
    mobile_build = root / "apps" / "mobile" / "build"
    desktop_source_updated_at = _newest_source_timestamp(
        [
            root / "apps" / "theia-desktop" / "package.json",
            root / "apps" / "theia-desktop" / "yarn.lock",
            root / "apps" / "theia-desktop" / "app" / "package.json",
            root / "apps" / "theia-desktop" / "app" / "electron-builder.yml",
            root / "apps" / "theia-desktop" / "app" / "resources",
            root / "apps" / "theia-desktop" / "packages" / "dubhe-theia-extension" / "package.json",
            root / "apps" / "theia-desktop" / "packages" / "dubhe-theia-extension" / "src",
        ]
    )
    mobile_source_updated_at = _newest_source_timestamp(
        [
            root / "apps" / "mobile" / "pubspec.yaml",
            root / "apps" / "mobile" / "analysis_options.yaml",
            root / "apps" / "mobile" / "lib",
            root / "apps" / "mobile" / "android",
            root / "apps" / "mobile" / "ios",
        ]
    )
    windows_setup = _newest_file(desktop_dist, "Dubhe-*-win-x64-setup.exe")
    windows_portable = _newest_file(desktop_dist, "Dubhe-*-win-x64-portable.exe")
    android_debug_apk = (
        mobile_build / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
    )
    android_release_aab = (
        mobile_build / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
    )
    macos_package = _newest_file(desktop_dist, "Dubhe-*-mac-*.dmg") or _newest_file(
        desktop_dist, "Dubhe-*-mac-*.zip"
    )
    ios_app = mobile_build / "ios" / "iphoneos" / "Runner.app"

    return [
        _install_package(
            platform="windows",
            label_zh="Windows 安装包",
            artifact_type="nsis-setup",
            path=windows_setup,
            build_channel_zh="本机 electron-builder",
            ready_zh="可直接在 Windows 上安装；当前未签名，首次运行可能出现系统提示。",
            missing_zh="尚未生成 Windows setup 安装包。",
            next_step_zh="需要重新生成时，在 apps/theia-desktop 执行 yarn --cwd app electron-builder --win nsis。",
            source_updated_at=desktop_source_updated_at,
        ),
        _install_package(
            platform="windows",
            label_zh="Windows 便携版",
            artifact_type="portable-exe",
            path=windows_portable,
            build_channel_zh="本机 electron-builder",
            ready_zh="可直接拷贝运行；适合当前阶段给测试用户体验。",
            missing_zh="尚未生成 Windows portable 便携版。",
            next_step_zh="需要重新生成时，在 apps/theia-desktop 执行 yarn --cwd app electron-builder --win portable。",
            source_updated_at=desktop_source_updated_at,
        ),
        _install_package(
            platform="android",
            label_zh="Android 调试 APK",
            artifact_type="debug-apk",
            path=android_debug_apk,
            build_channel_zh="本机 Flutter",
            ready_zh="可安装到 Android 真机或模拟器，用于本地体验和烟测。",
            missing_zh="尚未生成 Android debug APK。",
            next_step_zh="在 apps/mobile 执行 flutter build apk --debug --dart-define=DUBHE_CORE_URL=http://10.0.2.2:8000。",
            source_updated_at=mobile_source_updated_at,
        ),
        _install_package(
            platform="android",
            label_zh="Android 发布 AAB",
            artifact_type="release-aab",
            path=android_release_aab,
            build_channel_zh="本机 Flutter / CI",
            ready_zh="已生成 Android app bundle；正式上架前仍需正式签名、图标和商店元数据。",
            missing_zh="尚未生成 Android release appbundle。",
            next_step_zh="配置正式签名后，在 apps/mobile 执行 flutter build appbundle --release。",
            source_updated_at=mobile_source_updated_at,
        ),
        _install_package(
            platform="macos",
            label_zh="macOS 桌面包",
            artifact_type="dmg-or-zip",
            path=macos_package,
            build_channel_zh="macOS CI / macOS 本机",
            ready_zh="已找到 macOS 未签名桌面包；正式分发仍需 Apple 签名和公证。",
            missing_zh="当前 Windows 本机不能生成 macOS 安装包。",
            next_step_zh="在 macOS runner 启用 docs/ci/theia-desktop.yml，生成 dmg/zip 后再做签名和公证。",
            source_updated_at=desktop_source_updated_at,
        ),
        _install_package(
            platform="ios",
            label_zh="iOS 应用包",
            artifact_type="runner-app",
            path=ios_app,
            build_channel_zh="macOS CI / Xcode",
            ready_zh="已找到 iOS no-codesign app bundle；真机/TestFlight 仍需 Apple Developer 签名。",
            missing_zh="当前 Windows 本机不能生成 iOS 安装包。",
            next_step_zh="在 macOS + Xcode 或 docs/ci/mobile.yml 的 iOS job 中构建，并补齐 Bundle ID、证书和描述文件。",
            source_updated_at=mobile_source_updated_at,
        ),
    ]


def build_local_launcher_status(root: Path) -> list[LocalLauncherStatus]:
    launchers = [
        (
            "start-local",
            "启动 Dubhe（本机）",
            "打开本机 Core 与桌面客户端，适合只在当前 Windows 电脑上体验。",
            "Start-Dubhe.cmd",
            "双击即可启动本机 Dubhe。",
            "如果无法启动，先双击 Check-Dubhe.cmd 检查本机环境。",
        ),
        (
            "start-lan",
            "启动 Dubhe（局域网）",
            "让手机或同一局域网设备连接这台电脑上的 Core。",
            "Start-Dubhe-LAN.cmd",
            "双击后按窗口里的局域网地址连接手机端。",
            "如果手机无法连接，请确认手机和电脑在同一 Wi-Fi，并检查防火墙提示。",
        ),
        (
            "configure",
            "配置 AI 与新闻源",
            "打开本机配置文件，填写 AI 模型、新闻 API Key 等必要配置。",
            "Configure-Dubhe.cmd",
            "双击即可打开本机配置文件。",
            "填写后重新启动 Dubhe，再点击系统体检。",
        ),
        (
            "check-local",
            "检查本机环境",
            "检查 Node、Python、Flutter、依赖和基础目录是否可用。",
            "Check-Dubhe.cmd",
            "双击即可执行本机环境检查。",
            "按检查报告补齐缺失工具后再重新运行。",
        ),
        (
            "smoke",
            "运行主链路烟测",
            "自动跑新闻、AI 兜底、策略草稿、回测、纸面交易等核心链路。",
            "Smoke-Dubhe.cmd",
            "双击即可运行主链路烟测。",
            "烟测失败时先查看窗口最后几行错误，再运行 Test-Dubhe-Services.cmd。",
        ),
        (
            "test-services",
            "运行服务端测试",
            "执行 Core 服务测试，确认 API、数据和交易兜底链路没有被改坏。",
            "Test-Dubhe-Services.cmd",
            "双击即可运行服务端测试。",
            "测试失败时暂时不要交给普通用户试用，先修复失败项。",
        ),
        (
            "production-check",
            "检查生产门禁",
            "检查外部服务、四端安装包、授权数据、审计和实盘前置条件。",
            "Check-Dubhe-Production.cmd",
            "双击即可查看生产门禁报告。",
            "所有阻塞项处理完之前，只能作为演示或内测版本使用。",
        ),
        (
            "build-user-kit",
            "生成小白用户包",
            "把安装包、检查报告、指南和本机启动入口整理成一个可分发压缩包。",
            "Build-Dubhe-User-Kit.cmd",
            "双击即可生成用户包。",
            "生成前先确认安装包状态和生产门禁结果。",
        ),
        (
            "install-guide",
            "打开安装指南",
            "打开 Windows/macOS/Android/iOS 的安装和分发说明。",
            "Open-Dubhe-Install-Guide.cmd",
            "双击即可打开安装指南。",
            "给测试用户发包前，先按指南确认对应平台限制。",
        ),
        (
            "mobile-guide",
            "打开移动端指南",
            "打开 Android/iOS 连接 Core、局域网地址和常见问题说明。",
            "Open-Dubhe-Mobile-Guide.cmd",
            "双击即可打开移动端指南。",
            "手机连接失败时优先按指南检查 Core 地址和网络。",
        ),
        (
            "stop-core",
            "停止 Dubhe Core",
            "关闭本机后台 Core 服务，适合重启配置或释放端口。",
            "Stop-Dubhe-Core.cmd",
            "双击即可停止本机 Core 服务。",
            "停止后需要重新双击 Start-Dubhe.cmd 或 Start-Dubhe-LAN.cmd 启动。",
        ),
    ]

    return [
        _local_launcher(
            root=root,
            launcher_id=launcher_id,
            label_zh=label_zh,
            description_zh=description_zh,
            filename=filename,
            ready_zh=ready_zh,
            next_step_zh=next_step_zh,
        )
        for (
            launcher_id,
            label_zh,
            description_zh,
            filename,
            ready_zh,
            next_step_zh,
        ) in launchers
    ]


def _local_launcher(
    *,
    root: Path,
    launcher_id: str,
    label_zh: str,
    description_zh: str,
    filename: str,
    ready_zh: str,
    next_step_zh: str,
) -> LocalLauncherStatus:
    path = root / filename
    available = path.is_file()
    return LocalLauncherStatus(
        id=launcher_id,
        label_zh=label_zh,
        description_zh=description_zh,
        local_path=str(path),
        available=available,
        message_zh=ready_zh if available else f"未找到 {filename}。",
        next_step_zh=next_step_zh if available else "请确认当前 Core 指向正确的 Dubhe 仓库根目录。",
    )


def _install_package(
    *,
    platform: str,
    label_zh: str,
    artifact_type: str,
    path: Path | None,
    build_channel_zh: str,
    ready_zh: str,
    missing_zh: str,
    next_step_zh: str,
    source_updated_at: datetime | None,
) -> InstallPackageStatus:
    available = bool(path and path.exists())
    size_bytes = path.stat().st_size if available and path else 0
    artifact_updated_at = (
        datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
        if available and path
        else None
    )
    needs_rebuild = bool(
        available
        and artifact_updated_at
        and source_updated_at
        and source_updated_at.timestamp() > artifact_updated_at.timestamp() + 1
    )
    freshness_message_zh = _package_freshness_message(
        available=available,
        needs_rebuild=needs_rebuild,
        artifact_updated_at=artifact_updated_at,
        source_updated_at=source_updated_at,
    )
    return InstallPackageStatus(
        platform=platform,
        label_zh=label_zh,
        artifact_type=artifact_type,
        available=available,
        local_path=str(path) if path else None,
        size_bytes=size_bytes,
        artifact_updated_at=artifact_updated_at,
        source_updated_at=source_updated_at,
        needs_rebuild=needs_rebuild,
        freshness_message_zh=freshness_message_zh,
        build_channel_zh=build_channel_zh,
        message_zh=(
            f"{ready_zh} 但源码已更新，建议重新构建后再分发。"
            if needs_rebuild
            else ready_zh if available else missing_zh
        ),
        next_step_zh=next_step_zh,
    )


def _package_freshness_message(
    *,
    available: bool,
    needs_rebuild: bool,
    artifact_updated_at: datetime | None,
    source_updated_at: datetime | None,
) -> str:
    if not available:
        return "尚未生成安装产物。"
    if not artifact_updated_at:
        return "未读取到安装产物时间。"
    if not source_updated_at:
        return "未读取到对应源码时间。"
    artifact_time = artifact_updated_at.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    source_time = source_updated_at.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    if needs_rebuild:
        return f"需要重建：源码更新时间 {source_time} 晚于产物时间 {artifact_time}。"
    return f"产物较新：产物时间 {artifact_time}，源码时间 {source_time}。"


def _newest_source_timestamp(paths: list[Path]) -> datetime | None:
    mtimes: list[float] = []
    for path in paths:
        if path.is_file():
            mtimes.append(path.stat().st_mtime)
        elif path.is_dir():
            mtimes.extend(_source_file_mtimes(path))
    if not mtimes:
        return None
    return datetime.fromtimestamp(max(mtimes), tz=timezone.utc)


def _source_file_mtimes(root: Path) -> list[float]:
    excluded_dirs = {
        ".dart_tool",
        ".gradle",
        ".kotlin",
        ".theia-cache",
        "build",
        "dist",
        "ephemeral",
        "node_modules",
    }
    excluded_files = {
        "Generated.xcconfig",
        "GeneratedPluginRegistrant.h",
        "GeneratedPluginRegistrant.java",
        "GeneratedPluginRegistrant.m",
        "flutter_export_environment.sh",
        "local.properties",
    }
    mtimes: list[float] = []
    for path in root.rglob("*"):
        if any(part in excluded_dirs for part in path.parts):
            continue
        if path.name in excluded_files:
            continue
        if path.is_file():
            mtimes.append(path.stat().st_mtime)
    return mtimes


def _newest_file(directory: Path, pattern: str) -> Path | None:
    if not directory.exists():
        return None
    files = [path for path in directory.glob(pattern) if path.is_file()]
    if not files:
        return None
    return max(files, key=lambda path: path.stat().st_mtime)


@app.get("/v1/system/smoke-report", response_model=SmokeWorkflowReportResponse)
def system_smoke_report() -> SmokeWorkflowReportResponse:
    return read_smoke_workflow_report()


@app.get("/v1/system/external-checks", response_model=ExternalServiceCheckResponse)
def system_external_checks(
    live: bool = Query(default=False),
) -> ExternalServiceCheckResponse:
    return external_service_checks(live=live)


@app.get("/v1/system/production-readiness", response_model=ProductionReadinessResponse)
def system_production_readiness() -> ProductionReadinessResponse:
    return production_readiness_response()


@app.get("/v1/capabilities")
def capabilities() -> dict[str, object]:
    return {
        "language": "zh-CN",
        "markets": ["A_SHARE", "HK", "US", "GLOBAL"],
        "features": [
            "news_analysis_mock",
            "strategy_spec_validation",
            "risk_gate",
            "paper_order_mock",
            "simulated_paper_broker_adapter",
            "paper_portfolio_ledger",
            "device_registration",
            "workspace_sync_snapshot",
            "watchlist_sync",
            "local_sqlite_persistence",
            "public_news_feed_adapters",
            "licensed_news_api_adapters",
            "strategy_draft_from_news_analysis",
            "deterministic_replay_backtest",
            "approval_requests",
            "kill_switch",
            "device_bearer_token_auth",
            "device_token_revocation",
            "account_password_login",
            "local_mfa_placeholder",
            "role_based_risk_controls",
            "admin_user_role_management",
            "audit_log",
            "workspace_sync_websocket",
            "openai_compatible_llm_router",
            "local_runtime_config_editor",
        ],
        "live_trading": "disabled_until_risk_approval_flow_exists",
    }


def env_is_configured(key: str) -> bool:
    return bool(os.environ.get(key, "").strip())


def authenticate_device_token(access_token: str) -> DeviceSession | None:
    session = store.device_session_by_access_token(access_token)
    if session is None:
        return None
    return session


def require_device_session(authorization: str | None = Header(default=None)) -> DeviceSession:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="需要设备访问令牌。")

    session = authenticate_device_token(token)
    if session is None:
        raise HTTPException(status_code=401, detail="设备访问令牌无效或已失效。")
    return session


def optional_device_session(authorization: str | None = Header(default=None)) -> DeviceSession | None:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None
    return authenticate_device_token(token)


def require_workspace_access(workspace_id: str, session: DeviceSession) -> None:
    if session.workspace_id != workspace_id:
        raise HTTPException(status_code=403, detail="当前设备无权访问该工作区。")


def require_roles(session: DeviceSession, allowed_roles: set[UserRole]) -> None:
    if session.role not in allowed_roles:
        raise HTTPException(status_code=403, detail="当前账号权限不足。")


def require_risk_manager_session(
    session: DeviceSession = Depends(require_device_session),
) -> DeviceSession:
    require_roles(session, {UserRole.RISK_MANAGER, UserRole.ADMIN})
    return session


def require_admin_session(
    session: DeviceSession = Depends(require_device_session),
) -> DeviceSession:
    require_roles(session, {UserRole.ADMIN})
    return session


@app.get("/v1/onboarding/checklist", response_model=OnboardingChecklistResponse)
def onboarding_checklist_endpoint(
    session: DeviceSession | None = Depends(optional_device_session),
) -> OnboardingChecklistResponse:
    status = system_status()
    llm_ready = status.llm.enabled
    licensed_news_ready = any(
        adapter.requires_license and adapter.enabled for adapter in status.news_adapters
    )
    public_news_ready = any(
        (not adapter.requires_license) and adapter.enabled for adapter in status.news_adapters
    )

    steps = [
        OnboardingStep(
            id="core_connected",
            label_zh="连接 Core",
            status=OnboardingStepStatus.COMPLETE,
            message_zh="Dubhe Core 正在响应请求。",
        ),
        OnboardingStep(
            id="account_login",
            label_zh="账号登录",
            status=OnboardingStepStatus.COMPLETE
            if session
            else OnboardingStepStatus.ACTION_REQUIRED,
            message_zh=(
                f"已登录：{session.device_name}，角色 {session.role.value}。"
                if session
                else "请创建或登录本地账号，才能同步工作区和保存研究记录。"
            ),
            action_zh=None if session else "创建账号或登录工作台。",
        ),
        OnboardingStep(
            id="runtime_config",
            label_zh="模型与授权新闻源",
            status=OnboardingStepStatus.COMPLETE
            if llm_ready and licensed_news_ready
            else OnboardingStepStatus.WARNING,
            message_zh=(
                "真实 AI 模型和至少一个授权新闻源已接入。"
                if llm_ready and licensed_news_ready
                else "当前可用本地 AI 兜底和公开/演示新闻源；填写模型与授权新闻 key 后体验更接近真实投研。"
            ),
            action_zh=None
            if llm_ready and licensed_news_ready
            else "管理员可在系统状态里保存 AI 模型和新闻源 key。",
        ),
        OnboardingStep(
            id="news_ready",
            label_zh="新闻雷达",
            status=OnboardingStepStatus.COMPLETE
            if public_news_ready
            else OnboardingStepStatus.ACTION_REQUIRED,
            message_zh=(
                "新闻源聚合链路可用，授权源缺失时会自动降级到公开/演示来源。"
                if public_news_ready
                else "新闻源当前不可用。"
            ),
            action_zh=None if public_news_ready else "检查网络和新闻源配置。",
        ),
        OnboardingStep(
            id="ai_assistant_ready",
            label_zh="AI 分析师",
            status=OnboardingStepStatus.COMPLETE
            if status.llm.fallback_available or status.llm.enabled
            else OnboardingStepStatus.ACTION_REQUIRED,
            message_zh=(
                status.llm.message_zh
                if status.llm.message_zh
                else "AI 分析师可使用本地兜底或真实模型生成中文研究答复。"
            ),
            action_zh=None
            if status.llm.fallback_available or status.llm.enabled
            else "配置可用模型或启用本地兜底。",
        ),
        OnboardingStep(
            id="workspace_sync",
            label_zh="跨端同步",
            status=OnboardingStepStatus.COMPLETE
            if session
            else OnboardingStepStatus.ACTION_REQUIRED,
            message_zh=(
                f"当前工作区 {session.workspace_id} 可同步自选股、策略、回测和 AI 问答。"
                if session
                else "登录后会启用工作区快照、同步事件和跨端问答恢复。"
            ),
            action_zh=None if session else "登录账号后刷新同步状态。",
        ),
        OnboardingStep(
            id="paper_trading_ready",
            label_zh="纸面交易",
            status=OnboardingStepStatus.COMPLETE
            if session and status.trading.paper_broker_enabled
            else OnboardingStepStatus.ACTION_REQUIRED,
            message_zh=(
                "纸面交易、模拟券商和组合账本可用。"
                if session and status.trading.paper_broker_enabled
                else "登录并完成分析/策略/回测后，可以提交 1 股纸面买入验证账本链路。"
            ),
            action_zh=None
            if session and status.trading.paper_broker_enabled
            else "先登录，再完成新闻分析、策略草案和回测。",
        ),
        OnboardingStep(
            id="live_trading_guard",
            label_zh="实盘风控边界",
            status=OnboardingStepStatus.COMPLETE
            if not status.trading.live_trading_enabled
            else OnboardingStepStatus.WARNING,
            message_zh=status.trading.message_zh,
            action_zh=None
            if not status.trading.live_trading_enabled
            else "确认券商签名、审批、审计和 kill switch 均已上线。",
        ),
    ]
    complete_count = sum(1 for step in steps if step.status == OnboardingStepStatus.COMPLETE)
    next_step = next(
        (step for step in steps if step.status == OnboardingStepStatus.ACTION_REQUIRED),
        next((step for step in steps if step.status == OnboardingStepStatus.WARNING), None),
    )
    return OnboardingChecklistResponse(
        complete_count=complete_count,
        total_count=len(steps),
        next_action_zh=next_step.action_zh if next_step and next_step.action_zh else "可以开始刷新新闻并进行 AI 分析。",
        steps=steps,
    )


@app.get("/v1/runtime/local-config", response_model=LocalRuntimeConfigResponse)
def get_local_runtime_config_endpoint(
    _session: DeviceSession = Depends(require_admin_session),
) -> LocalRuntimeConfigResponse:
    try:
        return local_runtime_config_response()
    except ValueError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.put("/v1/runtime/local-config", response_model=LocalRuntimeConfigResponse)
def update_local_runtime_config_endpoint(
    request: LocalRuntimeConfigUpdateRequest,
    session: DeviceSession = Depends(require_admin_session),
) -> LocalRuntimeConfigResponse:
    try:
        response = update_local_runtime_config(request)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(status_code=500, detail="本地配置文件写入失败。") from exc

    updated_keys = sorted(key for key, value in request.values.items() if value.strip())
    cleared_keys = sorted(
        set(request.clear_keys) | {key for key, value in request.values.items() if not value.strip()}
    )
    store.append_audit_log(
        actor_session=session,
        action="runtime.local_config_updated",
        target_type="runtime_config",
        target_id=response.path,
        summary_zh="本地运行配置已更新；敏感值已脱敏处理。",
        metadata={
            "updated_keys": updated_keys,
            "cleared_keys": cleared_keys,
            "config_path": response.path,
            "secrets_redacted": True,
        },
    )
    return response


@app.post("/v1/auth/devices/register", response_model=DeviceSession)
def register_device_endpoint(request: DeviceRegistrationRequest) -> DeviceSession:
    return store.register_device(request)


@app.post("/v1/auth/accounts/register", response_model=DeviceSession)
def register_account_endpoint(request: AccountRegistrationRequest) -> DeviceSession:
    try:
        return store.register_account(request)
    except ValueError as exc:
        store.append_audit_log(
            action="auth.account_registration_failed",
            target_type="user",
            summary_zh="账号注册失败：账号已存在。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=409, detail="账号已存在，请直接登录。") from exc
    except PermissionError as exc:
        store.append_audit_log(
            action="auth.account_registration_failed",
            target_type="user",
            summary_zh="账号注册失败：MFA 验证码不正确。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=401, detail="MFA 验证码不正确。") from exc


@app.post("/v1/auth/login", response_model=DeviceSession)
def login_account_endpoint(request: AccountLoginRequest) -> DeviceSession:
    try:
        return store.login_account(request)
    except PermissionError as exc:
        store.append_audit_log(
            action="auth.login_failed",
            target_type="user",
            summary_zh="账号登录失败：账号、密码或 MFA 验证码不正确。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=401, detail="账号、密码或 MFA 验证码不正确。") from exc
    except KeyError as exc:
        store.append_audit_log(
            action="auth.login_failed",
            target_type="user",
            summary_zh="账号登录失败：账号工作区不存在。",
            metadata={"account_key": request.account_key},
        )
        raise HTTPException(status_code=404, detail="账号工作区不存在。") from exc


@app.post("/v1/auth/devices/current/revoke", response_model=DeviceRevocation)
def revoke_current_device_endpoint(
    session: DeviceSession = Depends(require_device_session),
) -> DeviceRevocation:
    return store.revoke_device_session(session)


@app.get("/v1/admin/users", response_model=list[UserSummary])
def list_users_endpoint(
    _session: DeviceSession = Depends(require_admin_session),
) -> list[UserSummary]:
    return store.list_users()


@app.post("/v1/admin/users/{user_id}/role", response_model=UserSummary)
def update_user_role_endpoint(
    user_id: str,
    request: UserRoleUpdateRequest,
    session: DeviceSession = Depends(require_admin_session),
) -> UserSummary:
    try:
        return store.update_user_role(user_id, request, session)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="账号不存在。") from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail="不能移除最后一个管理员。") from exc


@app.get("/v1/audit/logs", response_model=list[AuditLogEntry])
def list_audit_logs_endpoint(
    limit: int = Query(default=50, ge=1, le=200),
    _session: DeviceSession = Depends(require_risk_manager_session),
) -> list[AuditLogEntry]:
    return store.list_audit_logs(limit=limit)


@app.get("/v1/workspaces/{workspace_id}/snapshot", response_model=WorkspaceSnapshot)
def workspace_snapshot_endpoint(
    workspace_id: str,
    since_sequence: int = Query(default=0, ge=0),
    session: DeviceSession = Depends(require_device_session),
) -> WorkspaceSnapshot:
    require_workspace_access(workspace_id, session)
    try:
        return store.get_workspace_snapshot(workspace_id, since_sequence=since_sequence)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.put("/v1/workspaces/{workspace_id}/watchlist/{symbol}", response_model=WatchlistItem)
def upsert_watchlist_item_endpoint(
    workspace_id: str,
    symbol: str,
    request: WatchlistUpsertRequest,
    session: DeviceSession = Depends(require_device_session),
) -> WatchlistItem:
    require_workspace_access(workspace_id, session)
    if request.symbol != symbol.strip().upper():
        raise HTTPException(status_code=400, detail="路径中的股票代码必须与请求体一致。")
    try:
        return store.upsert_watchlist_item(workspace_id, request)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.get("/v1/workspaces/{workspace_id}/sync-events", response_model=list[SyncEvent])
def list_sync_events_endpoint(
    workspace_id: str,
    since_sequence: int = Query(default=0, ge=0),
    session: DeviceSession = Depends(require_device_session),
) -> list[SyncEvent]:
    require_workspace_access(workspace_id, session)
    try:
        return store.list_sync_events(workspace_id, since_sequence=since_sequence)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="工作区不存在。") from exc


@app.websocket("/v1/workspaces/{workspace_id}/sync-events/ws")
async def workspace_sync_events_websocket(
    websocket: WebSocket,
    workspace_id: str,
    access_token: str = Query(min_length=1),
    since_sequence: int = Query(default=0, ge=0),
) -> None:
    session = authenticate_device_token(access_token)
    if session is None or session.workspace_id != workspace_id:
        await websocket.close(code=1008)
        return

    try:
        store.get_workspace_snapshot(workspace_id, since_sequence=since_sequence)
    except KeyError:
        await websocket.close(code=1008)
        return

    await websocket.accept()
    cursor = since_sequence
    try:
        while True:
            events = store.list_sync_events(workspace_id, since_sequence=cursor)
            for event in events:
                await websocket.send_json(event.model_dump(mode="json"))
                cursor = max(cursor, event.sequence)
            await asyncio.sleep(SYNC_WEBSOCKET_POLL_SECONDS)
    except WebSocketDisconnect:
        return


@app.post("/v1/news/analyze", response_model=NewsAnalysis)
def analyze_news_endpoint(event: NewsEvent) -> NewsAnalysis:
    store.add_news_event(event)
    return store.add_analysis(analyze_news(event))


@app.get("/v1/news/feed", response_model=NewsFeedResponse)
def news_feed_endpoint(
    market: Market = Query(default=Market.US),
    symbol: str | None = Query(default=None, min_length=1),
    limit: int = Query(default=8, ge=1, le=20),
    live: bool = Query(default=True),
) -> NewsFeedResponse:
    feed = fetch_news_feed(market=market, symbol=symbol, limit=limit, live=live)
    store.add_news_events(feed.events)
    return feed


@app.get("/v1/news/events", response_model=list[NewsEvent])
def list_news_events_endpoint() -> list[NewsEvent]:
    return store.news_events


@app.get("/v1/news/analyses", response_model=list[NewsAnalysis])
def list_news_analyses_endpoint() -> list[NewsAnalysis]:
    return store.analyses


@app.post("/v1/strategy/spec/validate", response_model=StrategyValidationResult)
def validate_strategy_endpoint(spec: StrategySpec) -> StrategyValidationResult:
    return validate_strategy_spec(spec)


@app.get("/v1/strategy/templates", response_model=list[StrategyTemplate])
def list_strategy_templates_endpoint() -> list[StrategyTemplate]:
    return list_strategy_templates()


@app.post("/v1/strategy/drafts/from-analysis", response_model=StrategyDraft)
def draft_strategy_from_analysis_endpoint(request: StrategyDraftRequest) -> StrategyDraft:
    return store.add_strategy_draft(draft_strategy_from_analysis(request))


@app.post("/v1/strategy/drafts/from-template", response_model=StrategyDraft)
def draft_strategy_from_template_endpoint(
    request: StrategyTemplateDraftRequest,
) -> StrategyDraft:
    try:
        draft = draft_strategy_from_template(request)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    return store.add_strategy_draft(draft)


@app.post("/v1/strategy/drafts", response_model=StrategyDraft)
def save_strategy_draft_endpoint(draft: StrategyDraft) -> StrategyDraft:
    validation = validate_strategy_spec(draft.spec)
    if not validation.valid:
        raise HTTPException(status_code=422, detail=validation.reasons_zh)
    return store.add_strategy_draft(draft)


@app.get("/v1/strategy/drafts", response_model=list[StrategyDraft])
def list_strategy_drafts_endpoint() -> list[StrategyDraft]:
    return store.strategy_drafts


@app.post("/v1/backtests/replay", response_model=BacktestResult)
def run_replay_backtest_endpoint(request: BacktestRequest) -> BacktestResult:
    return store.add_backtest_result(run_replay_backtest(request))


@app.get("/v1/backtests", response_model=list[BacktestResult])
def list_backtests_endpoint() -> list[BacktestResult]:
    return store.backtest_results


def assistant_context_refs(context: AssistantContext) -> list[str]:
    refs = []
    if context.news_event is not None:
        refs.append(context.news_event.id)
    if context.analysis is not None:
        refs.append(context.analysis.id)
    if context.strategy is not None:
        refs.append(context.strategy.strategy_version_id)
    if context.backtest is not None:
        refs.append(context.backtest.id)
    return refs


@app.post("/v1/assistant/chat", response_model=AssistantChatResponse)
def assistant_chat_endpoint(
    request: AssistantChatRequest,
    session: DeviceSession = Depends(require_device_session),
) -> AssistantChatResponse:
    response = answer_research_question(request)
    turn = store.add_assistant_turn(
        AssistantConversationTurn(
            id=response.id,
            workspace_id=session.workspace_id,
            question_zh=request.question_zh,
            answer_zh=response.answer_zh,
            citations=response.citations,
            suggested_actions_zh=response.suggested_actions_zh,
            safety_notes_zh=response.safety_notes_zh,
            model_provider=response.model_provider,
            model_name=response.model_name,
            fallback_used=response.fallback_used,
            context_refs=assistant_context_refs(request.context),
            created_by_user_id=session.user_id,
            created_by_device_id=session.device_id,
            generated_at=response.generated_at,
        ),
    )
    store.append_audit_log(
        actor_session=session,
        action="assistant.chat_requested",
        target_type="assistant_turn",
        target_id=turn.id,
        summary_zh="AI 分析师生成了一条中文研究答复。",
        metadata={
            "question_length": len(request.question_zh),
            "citation_count": len(response.citations),
            "has_analysis": request.context.analysis is not None,
            "has_strategy": request.context.strategy is not None,
            "has_backtest": request.context.backtest is not None,
            "model_provider": response.model_provider,
            "model_name": response.model_name,
            "fallback_used": response.fallback_used,
        },
    )
    return response


@app.get("/v1/assistant/turns", response_model=list[AssistantConversationTurn])
def list_assistant_turns_endpoint(
    limit: int = Query(default=20, ge=1, le=50),
    session: DeviceSession = Depends(require_device_session),
) -> list[AssistantConversationTurn]:
    return store.list_assistant_turns(session.workspace_id, limit=limit)


@app.post("/v1/risk/evaluate", response_model=RiskDecision)
def evaluate_risk_endpoint(
    intent: OrderIntent,
    session: DeviceSession = Depends(require_device_session),
) -> RiskDecision:
    decision = store.add_risk_decision(evaluate_order_intent(intent, store.current_risk_policy()))
    if decision.status == RiskStatus.REQUIRES_APPROVAL:
        store.create_approval_request(decision, intent.created_by)
    store.append_audit_log(
        actor_session=session,
        action="risk.order_evaluated",
        target_type="risk_decision",
        target_id=decision.id,
        summary_zh=f"订单意图已完成风控评估：{decision.status.value}。",
        metadata={
            "order_intent_id": decision.order_intent_id,
            "symbol": intent.symbol,
            "destination": intent.destination.value,
            "notional": decision.notional,
        },
    )
    return decision


@app.get("/v1/risk/decisions", response_model=list[RiskDecision])
def list_risk_decisions_endpoint(
    _session: DeviceSession = Depends(require_device_session),
) -> list[RiskDecision]:
    return store.risk_decisions


@app.get("/v1/approvals", response_model=list[ApprovalRequest])
def list_approval_requests_endpoint(
    status: ApprovalStatus | None = Query(default=None),
    _session: DeviceSession = Depends(require_risk_manager_session),
) -> list[ApprovalRequest]:
    return store.list_approval_requests(status=status)


@app.post("/v1/approvals/{approval_id}/approve", response_model=ApprovalRequest)
def approve_request_endpoint(
    approval_id: str,
    request: ApprovalActionRequest,
    session: DeviceSession = Depends(require_risk_manager_session),
) -> ApprovalRequest:
    try:
        return store.decide_approval(approval_id, ApprovalStatus.APPROVED, request, session)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="审批请求不存在。") from exc


@app.post("/v1/approvals/{approval_id}/reject", response_model=ApprovalRequest)
def reject_request_endpoint(
    approval_id: str,
    request: ApprovalActionRequest,
    session: DeviceSession = Depends(require_risk_manager_session),
) -> ApprovalRequest:
    try:
        return store.decide_approval(approval_id, ApprovalStatus.REJECTED, request, session)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="审批请求不存在。") from exc


@app.get("/v1/risk/kill-switch", response_model=KillSwitchState)
def get_kill_switch_endpoint(
    _session: DeviceSession = Depends(require_risk_manager_session),
) -> KillSwitchState:
    return store.get_kill_switch_state()


@app.post("/v1/risk/kill-switch", response_model=KillSwitchState)
def set_kill_switch_endpoint(
    request: KillSwitchUpdateRequest,
    session: DeviceSession = Depends(require_risk_manager_session),
) -> KillSwitchState:
    return store.set_kill_switch_state(request, session)


@app.post("/v1/simulation/paper-orders", response_model=PaperOrder)
def submit_paper_order_endpoint(
    intent: OrderIntent,
    session: DeviceSession = Depends(require_device_session),
) -> PaperOrder:
    if intent.side == OrderSide.SELL:
        portfolio = store.get_paper_portfolio(intent.account_id)
        held_quantity = 0.0
        for position in portfolio.positions:
            if (
                position.market == intent.market
                and position.symbol == intent.symbol
                and position.currency == intent.currency
            ):
                held_quantity = position.quantity
                break

        if held_quantity + 0.00000001 < intent.quantity:
            decision = evaluate_order_intent(intent, store.current_risk_policy())
            reasons = list(decision.reasons_zh)
            reasons.append(
                f"纸面组合中 {intent.symbol} 可卖数量 {held_quantity:g}，不足以卖出 {intent.quantity:g}。"
            )
            blocked_order = PaperOrder(
                order_intent_id=intent.id,
                status=PaperOrderStatus.BLOCKED,
                risk_decision=decision.model_copy(
                    update={
                        "status": RiskStatus.REJECTED,
                        "allowed_destination": "none",
                        "reasons_zh": reasons,
                    },
                ),
                message_zh="纸面订单已被纸面组合持仓校验拦截。",
            )
            return store.add_paper_order(blocked_order, session)

    return store.add_paper_order(submit_paper_order(intent, store.current_risk_policy()), session)


@app.get("/v1/simulation/paper-orders", response_model=list[PaperOrder])
def list_paper_orders_endpoint(
    _session: DeviceSession = Depends(require_device_session),
) -> list[PaperOrder]:
    return store.paper_orders


@app.get("/v1/simulation/broker-orders", response_model=list[BrokerOrder])
def list_broker_orders_endpoint(
    _session: DeviceSession = Depends(require_device_session),
) -> list[BrokerOrder]:
    return store.broker_orders


@app.get("/v1/simulation/paper-portfolio/{account_id}", response_model=PaperPortfolioSnapshot)
def get_paper_portfolio_endpoint(
    account_id: str,
    _session: DeviceSession = Depends(require_device_session),
) -> PaperPortfolioSnapshot:
    return store.get_paper_portfolio(account_id)
