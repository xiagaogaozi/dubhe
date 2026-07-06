from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from typing import MutableMapping

from .models import (
    LocalRuntimeConfigItem,
    LocalRuntimeConfigResponse,
    LocalRuntimeConfigUpdateRequest,
)


@dataclass(frozen=True)
class LocalConfigDefinition:
    key: str
    label_zh: str
    description_zh: str
    group_zh: str
    placeholder: str = ""
    setup_hint_zh: str = ""
    secret: bool = False
    restart_required: bool = False


LOCAL_CONFIG_DEFINITIONS = [
    LocalConfigDefinition(
        key="DUBHE_LLM_MODEL",
        label_zh="AI 模型名称",
        description_zh="OpenAI-compatible 模型名，填写服务商模型 ID 或本地网关模型名。",
        group_zh="AI 模型",
        placeholder="服务商提供的 model id",
        setup_hint_zh="如果使用 OpenAI 官方或兼容网关，复制控制台里的模型 ID；本地模型则填网关暴露的模型名。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_API_KEY",
        label_zh="AI 模型 API Key",
        description_zh="OpenAI 官方或兼容网关的鉴权 Key；不会在接口响应中回显。",
        group_zh="AI 模型",
        placeholder="sk-... / 兼容网关 key",
        setup_hint_zh="从模型服务商控制台复制；本地无鉴权模型可留空。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_BASE_URL",
        label_zh="AI 模型地址",
        description_zh="OpenAI-compatible /v1 地址；留空时使用 OpenAI 官方地址。",
        group_zh="AI 模型",
        placeholder="https://api.openai.com/v1",
        setup_hint_zh="使用本地模型、代理网关或第三方兼容服务时填写；只用 OpenAI 官方默认地址可留空。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_PROVIDER",
        label_zh="AI 模型供应商",
        description_zh="当前默认 openai_compatible，预留给后续多供应商路由。",
        group_zh="AI 模型",
        placeholder="openai_compatible",
        setup_hint_zh="当前保持 openai_compatible 即可，后续接入多模型路由时再调整。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_TIMEOUT_SECONDS",
        label_zh="AI 超时秒数",
        description_zh="AI 请求超时时间，默认 20 秒。",
        group_zh="AI 模型",
        placeholder="20",
        setup_hint_zh="网络较慢或本地大模型响应慢时可以适当调大。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_MAX_TOKENS",
        label_zh="AI 最大输出",
        description_zh="单次 AI 答复最大 token 数，默认 900。",
        group_zh="AI 模型",
        placeholder="900",
        setup_hint_zh="越大越容易得到长分析，但成本和等待时间也会增加。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_TEMPERATURE",
        label_zh="AI 随机度",
        description_zh="AI 生成随机度，默认 0.2，越低越稳。",
        group_zh="AI 模型",
        placeholder="0.2",
        setup_hint_zh="投资研究建议保持较低随机度，减少同一问题反复回答不一致。",
    ),
    LocalConfigDefinition(
        key="FINNHUB_API_KEY",
        label_zh="Finnhub 授权新闻 Key",
        description_zh="用于 Finnhub company-news 授权新闻源；不会在接口响应中回显。",
        group_zh="授权新闻源",
        placeholder="Finnhub 控制台 API key",
        setup_hint_zh="用于美股公司新闻。接入生产前需要确认套餐、调用频率和二次展示/AI 处理条款。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="ALPHA_VANTAGE_API_KEY",
        label_zh="Alpha Vantage Key",
        description_zh="用于 Alpha Vantage NEWS_SENTIMENT 新闻情绪源；不会在接口响应中回显。",
        group_zh="授权新闻源",
        placeholder="Alpha Vantage API key",
        setup_hint_zh="用于新闻情绪和全球 ticker 语境。生产使用前同样需要确认授权条款。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_SEC_USER_AGENT",
        label_zh="SEC User-Agent",
        description_zh="SEC EDGAR 官方接口建议填写真实产品名和联系人邮箱。",
        group_zh="公开公告源",
        placeholder="Dubhe/0.1 contact@example.com",
        setup_hint_zh="用于礼貌访问 SEC EDGAR；生产环境请替换成真实产品名和可联系邮箱。",
    ),
    LocalConfigDefinition(
        key="DUBHE_PAPER_BROKER",
        label_zh="Paper broker 适配器",
        description_zh="默认 simulated_paper；填写 alpaca 后会把纸面订单提交到 Alpaca paper 沙盒。",
        group_zh="券商沙盒",
        placeholder="simulated_paper / alpaca",
        setup_hint_zh="没有券商沙盒账号时保持 simulated_paper；准备券商 UAT 时填写 alpaca，并补齐 Alpaca paper Key。",
    ),
    LocalConfigDefinition(
        key="ALPACA_PAPER_API_KEY_ID",
        label_zh="Alpaca Paper Key ID",
        description_zh="Alpaca paper trading 的 API Key ID；不会在接口响应中回显。",
        group_zh="券商沙盒",
        placeholder="Alpaca paper key id",
        setup_hint_zh="只使用 paper trading key；不要把真实 live 交易 key 填到本机演示环境。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="ALPACA_PAPER_SECRET_KEY",
        label_zh="Alpaca Paper Secret",
        description_zh="Alpaca paper trading 的 Secret Key；不会在接口响应中回显。",
        group_zh="券商沙盒",
        placeholder="Alpaca paper secret",
        setup_hint_zh="保存后运行 Test-Dubhe-Services.cmd 做 live 检查；失败时检查账号、网络和 key 类型。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="ALPACA_PAPER_BASE_URL",
        label_zh="Alpaca Paper 地址",
        description_zh="Alpaca paper trading API 地址，通常保持默认值。",
        group_zh="券商沙盒",
        placeholder="https://paper-api.alpaca.markets",
        setup_hint_zh="除非使用代理网关，否则保持默认 paper API 地址。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LOCAL_MFA_MODE",
        label_zh="本地 MFA 模式",
        description_zh="本机账号登录的 MFA 模式；默认 placeholder，可设为 totp 启用动态验证码。",
        group_zh="本地登录 MFA",
        placeholder="placeholder / totp",
        setup_hint_zh="普通本地体验可保持 placeholder；需要更接近真实登录时双击 Setup-Dubhe-MFA.cmd 自动配置 totp。",
        restart_required=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_LOCAL_MFA_CODE",
        label_zh="占位 MFA 验证码",
        description_zh="placeholder 模式下使用的固定 6 位验证码；仅用于本地开发体验。",
        group_zh="本地登录 MFA",
        placeholder="000000",
        setup_hint_zh="生产环境不要使用固定验证码；启用 TOTP 后该项会被忽略。",
        secret=True,
        restart_required=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_LOCAL_TOTP_SECRET",
        label_zh="TOTP 密钥",
        description_zh="本机动态验证码密钥；不会在接口响应中明文回显。",
        group_zh="本地登录 MFA",
        placeholder="Base32 secret",
        setup_hint_zh="建议通过 Setup-Dubhe-MFA.cmd 生成，不要手工编写。请像密码一样保存。",
        secret=True,
        restart_required=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_LOCAL_TOTP_ISSUER",
        label_zh="TOTP 发行方名称",
        description_zh="认证器 App 中显示的发行方名称。",
        group_zh="本地登录 MFA",
        placeholder="Dubhe",
        setup_hint_zh="通常保持 Dubhe 即可。",
        restart_required=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_LOCAL_TOTP_ACCOUNT",
        label_zh="TOTP 账号名称",
        description_zh="认证器 App 中显示的账号名称。",
        group_zh="本地登录 MFA",
        placeholder="local-admin",
        setup_hint_zh="可填写本机管理员或测试账号名称，便于区分多台设备。",
        restart_required=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_CORE_DB_PATH",
        label_zh="Core 数据库路径",
        description_zh="SQLite 本地数据库路径；修改后需要重启 Core 才能切换数据库。",
        group_zh="本地存储",
        placeholder=r"D:\dubhe-data\dubhe.sqlite3",
        setup_hint_zh="想把数据放到固定磁盘目录时填写；普通本地体验可先留空。",
        restart_required=True,
    ),
]

LOCAL_CONFIG_KEYS = {definition.key for definition in LOCAL_CONFIG_DEFINITIONS}
_CONFIG_LOCK = Lock()


def local_runtime_config_response(
    env: MutableMapping[str, str] | None = None,
) -> LocalRuntimeConfigResponse:
    source_env = env if env is not None else os.environ
    config_path = local_config_path()
    file_values = read_local_config_values(config_path)
    items = [
        _config_item(definition, file_values, source_env)
        for definition in LOCAL_CONFIG_DEFINITIONS
    ]
    configured_count = sum(1 for item in items if item.configured)
    return LocalRuntimeConfigResponse(
        editable=True,
        exists=config_path.exists(),
        path=str(config_path),
        items=items,
        message_zh=(
            f"本地配置文件可编辑；已读取 {configured_count}/{len(items)} 项。"
            if config_path.exists()
            else "尚未创建本地配置文件；保存任意配置后会自动创建。"
        ),
    )


def update_local_runtime_config(
    request: LocalRuntimeConfigUpdateRequest,
    env: MutableMapping[str, str] | None = None,
) -> LocalRuntimeConfigResponse:
    target_env = env if env is not None else os.environ
    config_path = local_config_path()
    _validate_update_keys(request)

    with _CONFIG_LOCK:
        current_values = read_local_config_values(config_path)
        for key in request.clear_keys:
            current_values.pop(key, None)
        for key, value in request.values.items():
            normalized_value = value.strip()
            if normalized_value:
                current_values[key] = normalized_value
            else:
                current_values.pop(key, None)

        write_local_config_values(config_path, current_values)

        touched_keys = set(request.values) | set(request.clear_keys)
        for key in touched_keys:
            if key in current_values:
                target_env[key] = current_values[key]
            else:
                target_env.pop(key, None)

    return local_runtime_config_response(target_env)


def local_config_path() -> Path:
    return repo_root() / "config" / "dubhe.local.env"


def repo_root() -> Path:
    configured_root = os.environ.get("DUBHE_REPO_ROOT", "").strip()
    if configured_root:
        return Path(configured_root)
    try:
        return Path(__file__).resolve().parents[4]
    except IndexError:
        return Path.cwd()


def read_local_config_values(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}

    values: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        trimmed = line.strip().lstrip("\ufeff")
        if not trimmed or trimmed.startswith("#") or trimmed.startswith(";"):
            continue
        separator_index = trimmed.find("=")
        if separator_index <= 0:
            raise ValueError(f"{path} 第 {line_number} 行不是 KEY=VALUE。")
        key = trimmed[:separator_index].strip()
        value = _unquote_value(trimmed[separator_index + 1 :].strip())
        values[key] = value
    return values


def write_local_config_values(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    known_values = {key: values[key] for key in LOCAL_CONFIG_KEYS if key in values}
    unknown_values = {
        key: value for key, value in values.items() if key not in LOCAL_CONFIG_KEYS
    }
    lines = [
        "# Dubhe local runtime configuration.",
        "# Managed by Dubhe; secrets stay on this computer and are ignored by Git.",
        "# Blank or commented lines are ignored. Save, then restart Core for DB path changes.",
        "",
        "# AI model router.",
    ]
    _append_definition_lines(lines, known_values, "DUBHE_LLM_")
    lines.extend(["", "# Licensed / public financial news sources."])
    _append_named_lines(lines, known_values, ["FINNHUB_API_KEY", "ALPHA_VANTAGE_API_KEY"])
    lines.append(_format_known_line("DUBHE_SEC_USER_AGENT", known_values))
    lines.extend(["", "# Optional paper broker adapter."])
    _append_named_lines(
        lines,
        known_values,
        [
            "DUBHE_PAPER_BROKER",
            "ALPACA_PAPER_API_KEY_ID",
            "ALPACA_PAPER_SECRET_KEY",
            "ALPACA_PAPER_BASE_URL",
        ],
    )
    lines.extend(["", "# Optional local MFA."])
    _append_named_lines(
        lines,
        known_values,
        [
            "DUBHE_LOCAL_MFA_MODE",
            "DUBHE_LOCAL_MFA_CODE",
            "DUBHE_LOCAL_TOTP_SECRET",
            "DUBHE_LOCAL_TOTP_ISSUER",
            "DUBHE_LOCAL_TOTP_ACCOUNT",
        ],
    )
    lines.extend(["", "# Optional persistent Core database override."])
    lines.append(_format_known_line("DUBHE_CORE_DB_PATH", known_values))

    if unknown_values:
        lines.extend(["", "# Other local entries preserved from the existing file."])
        for key in sorted(unknown_values):
            lines.append(f"{key}={_format_env_value(unknown_values[key])}")

    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    tmp_path.replace(path)


def _config_item(
    definition: LocalConfigDefinition,
    file_values: dict[str, str],
    env: MutableMapping[str, str],
) -> LocalRuntimeConfigItem:
    file_value = file_values.get(definition.key, "").strip()
    env_value = env.get(definition.key, "").strip()
    value = file_value or env_value
    source = "missing"
    if file_value:
        source = "local_file"
    elif env_value:
        source = "process_env"

    return LocalRuntimeConfigItem(
        key=definition.key,
        label_zh=definition.label_zh,
        description_zh=definition.description_zh,
        group_zh=definition.group_zh,
        placeholder=definition.placeholder,
        setup_hint_zh=definition.setup_hint_zh,
        configured=bool(value),
        secret=definition.secret,
        source=source,
        masked_value=_mask_value(value, definition.secret) if value else None,
        restart_required=definition.restart_required,
    )


def _validate_update_keys(request: LocalRuntimeConfigUpdateRequest) -> None:
    unknown_keys = (set(request.values) | set(request.clear_keys)) - LOCAL_CONFIG_KEYS
    if unknown_keys:
        joined = "、".join(sorted(unknown_keys))
        raise ValueError(f"不支持的配置项：{joined}。")


def _append_definition_lines(
    lines: list[str],
    values: dict[str, str],
    prefix: str,
) -> None:
    keys = [definition.key for definition in LOCAL_CONFIG_DEFINITIONS]
    for key in keys:
        if key.startswith(prefix):
            lines.append(_format_known_line(key, values))


def _append_named_lines(lines: list[str], values: dict[str, str], keys: list[str]) -> None:
    for key in keys:
        lines.append(_format_known_line(key, values))


def _format_known_line(key: str, values: dict[str, str]) -> str:
    if key in values:
        return f"{key}={_format_env_value(values[key])}"
    return f"# {key}="


def _format_env_value(value: str) -> str:
    if not value:
        return ""
    if "\n" in value or "\r" in value:
        raise ValueError("配置值不能包含换行。")
    if any(character.isspace() for character in value) or "#" in value or ";" in value:
        if "'" not in value:
            return f"'{value}'"
        if '"' not in value:
            return f'"{value}"'
    return value


def _unquote_value(value: str) -> str:
    if len(value) >= 2 and (
        (value.startswith('"') and value.endswith('"'))
        or (value.startswith("'") and value.endswith("'"))
    ):
        return value[1:-1]
    return value


def _mask_value(value: str, secret: bool) -> str:
    if not secret:
        return value
    if len(value) <= 4:
        return "已配置"
    return f"••••{value[-4:]}"
