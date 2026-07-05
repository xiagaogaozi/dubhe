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
    secret: bool = False
    restart_required: bool = False


LOCAL_CONFIG_DEFINITIONS = [
    LocalConfigDefinition(
        key="DUBHE_LLM_MODEL",
        label_zh="AI 模型名称",
        description_zh="OpenAI-compatible 模型名，例如 gpt-4.1-mini 或本地网关模型名。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_API_KEY",
        label_zh="AI 模型 API Key",
        description_zh="OpenAI 官方或兼容网关的鉴权 Key；不会在接口响应中回显。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_BASE_URL",
        label_zh="AI 模型地址",
        description_zh="OpenAI-compatible /v1 地址；留空时使用 OpenAI 官方地址。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_PROVIDER",
        label_zh="AI 模型供应商",
        description_zh="当前默认 openai_compatible，预留给后续多供应商路由。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_TIMEOUT_SECONDS",
        label_zh="AI 超时秒数",
        description_zh="AI 请求超时时间，默认 20 秒。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_MAX_TOKENS",
        label_zh="AI 最大输出",
        description_zh="单次 AI 答复最大 token 数，默认 900。",
    ),
    LocalConfigDefinition(
        key="DUBHE_LLM_TEMPERATURE",
        label_zh="AI 随机度",
        description_zh="AI 生成随机度，默认 0.2，越低越稳。",
    ),
    LocalConfigDefinition(
        key="FINNHUB_API_KEY",
        label_zh="Finnhub 授权新闻 Key",
        description_zh="用于 Finnhub company-news 授权新闻源；不会在接口响应中回显。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="ALPHA_VANTAGE_API_KEY",
        label_zh="Alpha Vantage Key",
        description_zh="用于 Alpha Vantage NEWS_SENTIMENT 新闻情绪源；不会在接口响应中回显。",
        secret=True,
    ),
    LocalConfigDefinition(
        key="DUBHE_SEC_USER_AGENT",
        label_zh="SEC User-Agent",
        description_zh="SEC EDGAR 官方接口建议填写真实产品名和联系人邮箱。",
    ),
    LocalConfigDefinition(
        key="DUBHE_CORE_DB_PATH",
        label_zh="Core 数据库路径",
        description_zh="SQLite 本地数据库路径；修改后需要重启 Core 才能切换数据库。",
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
        trimmed = line.strip()
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
