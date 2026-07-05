from __future__ import annotations

from .models import (
    InstallPackageStatus,
    NewsMarketCoverageStatus,
    ProductionReadinessItem,
    ProductionReadinessResponse,
)


def production_readiness_response() -> ProductionReadinessResponse:
    from .main import system_status  # Local import avoids a module import cycle.

    status = system_status()
    external_ready = _external_readiness_items()
    package_items = _package_readiness_items(status.install_packages)
    news_items = _news_readiness_items(status.news_coverage)
    items = [
        _item(
            item_id="local_smoke_chain",
            category_zh="本地可用性",
            requirement_zh="主链路烟测可证明账号、新闻、AI、策略、回测、纸面交易和同步闭环可运行。",
            status="pass",
            blocking=False,
            evidence_zh="已提供 Smoke-Dubhe.cmd、/v1/system/smoke-report 和脚本化主链路烟测。",
            next_step_zh="每次发布前运行 Smoke-Dubhe.cmd；生产前还需要把 smoke 接入 CI 和发布门禁。",
        ),
        *external_ready,
        *news_items,
        _item(
            item_id="production_identity",
            category_zh="身份与权限",
            requirement_zh="生产环境必须使用正式 OIDC/MFA、刷新令牌、密码策略和角色管理。",
            status="fail",
            blocking=True,
            evidence_zh=f"当前认证模式为 {status.auth.mode}，MFA 模式为 {status.auth.mfa_mode}，仍是本地开发认证。",
            next_step_zh="接入 OIDC/企业身份、真实 MFA、刷新令牌、会话撤销、密码策略和管理员角色 UI。",
        ),
        _item(
            item_id="production_storage",
            category_zh="云同步与存储",
            requirement_zh="生产环境必须使用 PostgreSQL/TimescaleDB、Redis、对象存储、备份和迁移策略。",
            status="fail",
            blocking=True,
            evidence_zh=f"当前存储后端为 {status.storage.backend}，路径为 {status.storage.path}。",
            next_step_zh="部署 PostgreSQL/TimescaleDB、Redis、S3/MinIO、备份、迁移和环境隔离；保留现有 API 契约。",
        ),
        _item(
            item_id="immutable_audit",
            category_zh="审计与合规",
            requirement_zh="生产审计日志必须不可篡改，并覆盖配置变更、AI 决策、风控、审批和订单。",
            status="fail",
            blocking=True,
            evidence_zh="当前审计日志保存在本地 SQLite，并已提供本地 SHA-256 哈希链校验，可用于开发验证，但不是生产级不可篡改审计存储。",
            next_step_zh="接入追加写审计存储、对象锁或外部审计服务，并为关键动作生成签名摘要和外部留痕。",
        ),
        _item(
            item_id="live_broker_adapter",
            category_zh="券商与交易",
            requirement_zh="生产环境必须有真实 paper/live broker adapter，并通过断线、拒单、重复单和市场规则测试。",
            status="fail",
            blocking=True,
            evidence_zh="当前只有 simulated_paper broker；live_trading_enabled=false。",
            next_step_zh="按目标市场接入 IBKR、Alpaca、Futu 或其他合规券商；所有订单仍必须经过 Risk Service、审批和审计。",
        ),
        _item(
            item_id="live_trading_guard",
            category_zh="券商与交易",
            requirement_zh="实盘开关必须保持关闭，直到真实券商、风控、审批、审计、kill switch 和回滚流程全部通过。",
            status="pass" if not status.trading.live_trading_enabled else "fail",
            blocking=bool(status.trading.live_trading_enabled),
            evidence_zh=status.trading.message_zh,
            next_step_zh="开放实盘前完成真实券商 UAT、MFA 审批、限额、撤单、异常处理和演练记录。",
        ),
        *package_items,
    ]
    pass_count = sum(1 for item in items if item.status == "pass")
    warning_count = sum(1 for item in items if item.status == "warn")
    blocking_count = sum(1 for item in items if item.blocking and item.status == "fail")
    production_ready = blocking_count == 0 and all(item.status != "fail" for item in items)
    return ProductionReadinessResponse(
        production_ready=production_ready,
        overall_status="ready" if production_ready else "not_ready",
        pass_count=pass_count,
        warning_count=warning_count,
        blocking_count=blocking_count,
        total_count=len(items),
        message_zh=(
            "生产门禁通过，可以进入受控发布流程。"
            if production_ready
            else f"生产门禁未通过：还有 {blocking_count} 个阻断项需要补齐。"
        ),
        items=items,
    )


def _external_readiness_items() -> list[ProductionReadinessItem]:
    from .external_checks import external_service_checks

    checks = external_service_checks(live=False).checks
    check_by_service = {check.service: check for check in checks}
    llm = check_by_service.get("llm_openai_compatible")
    gdelt = check_by_service.get("gdelt_doc")
    return [
        _item(
            item_id="llm_configured",
            category_zh="AI 模型",
            requirement_zh="生产环境必须配置可用的 OpenAI-compatible AI 模型，并在发布前完成 live 检查。",
            status="warn" if llm and llm.configured else "fail",
            blocking=not bool(llm and llm.configured),
            evidence_zh=llm.message_zh if llm else "未找到 AI 模型检查结果。",
            next_step_zh="填写 DUBHE_LLM_MODEL、DUBHE_LLM_BASE_URL、DUBHE_LLM_API_KEY 后运行 Test-Dubhe-Services.cmd。",
        ),
        _item(
            item_id="gdelt_available",
            category_zh="公开新闻索引",
            requirement_zh="至少保留一个公开全球新闻索引用作兜底上下文，但不得把索引当作原文转载授权。",
            status="pass" if gdelt and gdelt.configured else "fail",
            blocking=not bool(gdelt and gdelt.configured),
            evidence_zh=gdelt.message_zh if gdelt else "未找到 GDELT 检查结果。",
            next_step_zh="发布前仍需运行 live 外部服务体检，并记录索引和原文授权边界。",
        ),
    ]


def _news_readiness_items(
    coverage: list[NewsMarketCoverageStatus],
) -> list[ProductionReadinessItem]:
    return [
        _item(
            item_id=f"licensed_news_{item.market.value.lower()}",
            category_zh="授权新闻与数据",
            requirement_zh=f"{item.label_zh} 必须接入可生产使用的授权新闻/公告/数据源。",
            status="pass" if item.production_ready else "fail",
            blocking=True,
            evidence_zh=item.message_zh,
            next_step_zh=item.next_step_zh,
        )
        for item in coverage
    ]


def _package_readiness_items(
    packages: list[InstallPackageStatus],
) -> list[ProductionReadinessItem]:
    by_platform: dict[str, list[InstallPackageStatus]] = {}
    for item in packages:
        by_platform.setdefault(item.platform, []).append(item)
    return [
        _package_item(
            platform="windows",
            label_zh="Windows 安装包",
            package=_select_package(
                by_platform.get("windows", []),
                preferred_artifact_types=["nsis-setup", "portable-exe"],
            ),
            blocking=False,
            next_step_zh="当前未签名包可用于内测；生产发布前需要代码签名证书、安装器签名和更新渠道。",
        ),
        _package_item(
            platform="android",
            label_zh="Android 安装包",
            package=_select_package(
                by_platform.get("android", []),
                preferred_artifact_types=["release-aab", "debug-apk"],
            ),
            blocking=False,
            next_step_zh="当前 APK/AAB 可用于测试；生产发布前需要正式签名、包名、隐私政策和商店元数据。",
        ),
        _package_item(
            platform="macos",
            label_zh="macOS 安装包",
            package=_select_package(
                by_platform.get("macos", []),
                preferred_artifact_types=["dmg-or-zip"],
            ),
            blocking=True,
            next_step_zh="需要 macOS runner、Apple Developer 证书、签名、公证、dmg/zip 产物和更新渠道。",
        ),
        _package_item(
            platform="ios",
            label_zh="iOS 应用包",
            package=_select_package(
                by_platform.get("ios", []),
                preferred_artifact_types=["runner-app"],
            ),
            blocking=True,
            next_step_zh="需要 Xcode、Bundle ID、Team ID、证书、描述文件、TestFlight/App Store 发布资料。",
        ),
    ]


def _select_package(
    packages: list[InstallPackageStatus],
    *,
    preferred_artifact_types: list[str],
) -> InstallPackageStatus | None:
    preferred = [
        package
        for artifact_type in preferred_artifact_types
        for package in packages
        if package.artifact_type == artifact_type
    ]
    candidates = preferred or packages
    if not candidates:
        return None
    for package in candidates:
        if package.available and not package.needs_rebuild:
            return package
    for package in candidates:
        if package.available:
            return package
    return candidates[0]


def _package_item(
    *,
    platform: str,
    label_zh: str,
    package: InstallPackageStatus | None,
    blocking: bool,
    next_step_zh: str,
) -> ProductionReadinessItem:
    available = bool(package and package.available)
    stale = bool(package and package.needs_rebuild)
    status = "fail" if stale or not available else "warn"
    evidence = (
        f"{package.message_zh} {package.freshness_message_zh}".strip()
        if package
        else "未找到安装包状态。"
    )
    return _item(
        item_id=f"package_{platform}",
        category_zh="四端安装包",
        requirement_zh=f"{label_zh} 必须能构建、签名并交付给目标用户。",
        status=status,
        blocking=stale or (blocking and not available),
        evidence_zh=evidence,
        next_step_zh=next_step_zh,
    )


def _item(
    *,
    item_id: str,
    category_zh: str,
    requirement_zh: str,
    status: str,
    blocking: bool,
    evidence_zh: str,
    next_step_zh: str,
) -> ProductionReadinessItem:
    return ProductionReadinessItem(
        id=item_id,
        category_zh=category_zh,
        requirement_zh=requirement_zh,
        status=status,
        blocking=blocking,
        evidence_zh=evidence_zh,
        next_step_zh=next_step_zh,
    )
