from __future__ import annotations

import os

from .local_mfa import local_mfa_runtime_mode
from .models import AuthRuntimeStatus


def auth_runtime_status() -> AuthRuntimeStatus:
    mfa_mode = local_mfa_runtime_mode()
    target_mode = os.environ.get("DUBHE_AUTH_MODE", "local_dev").strip().lower() or "local_dev"
    oidc_configured = all(
        _is_configured(key)
        for key in [
            "DUBHE_OIDC_ISSUER_URL",
            "DUBHE_OIDC_CLIENT_ID",
            "DUBHE_OIDC_CLIENT_SECRET",
            "DUBHE_OIDC_REDIRECT_URI",
        ]
    )
    session_signing_configured = _is_configured("DUBHE_SESSION_SIGNING_KEY")
    refresh_token_policy_configured = _is_configured("DUBHE_REFRESH_TOKEN_TTL_DAYS")
    mfa_policy_configured = _is_configured("DUBHE_OIDC_MFA_POLICY_URL")
    identity_runbook_configured = _is_configured("DUBHE_IDENTITY_RUNBOOK_URL")

    missing_items_zh = []
    if target_mode != "oidc":
        missing_items_zh.append("DUBHE_AUTH_MODE=oidc")
    if not oidc_configured:
        missing_items_zh.append("OIDC issuer、client id、client secret 和 redirect URI")
    if not session_signing_configured:
        missing_items_zh.append("DUBHE_SESSION_SIGNING_KEY")
    if not refresh_token_policy_configured:
        missing_items_zh.append("DUBHE_REFRESH_TOKEN_TTL_DAYS")
    if not mfa_policy_configured:
        missing_items_zh.append("DUBHE_OIDC_MFA_POLICY_URL")
    if not identity_runbook_configured:
        missing_items_zh.append("DUBHE_IDENTITY_RUNBOOK_URL")

    production_ready = False
    if missing_items_zh:
        message = (
            f"当前认证模式为 local_dev，MFA 模式为 {mfa_mode}。生产身份配置仍缺少："
            f"{'、'.join(missing_items_zh)}。"
        )
    else:
        message = (
            "生产身份环境变量已基本填写，但当前运行认证仍为 local_dev；"
            "需要完成 OIDC 登录、刷新令牌、会话撤销和角色审计后才能通过生产门禁。"
        )

    return AuthRuntimeStatus(
        mode="local_dev",
        mfa_mode=mfa_mode,
        target_mode=target_mode,
        oidc_configured=oidc_configured,
        session_signing_configured=session_signing_configured,
        refresh_token_policy_configured=refresh_token_policy_configured,
        mfa_policy_configured=mfa_policy_configured,
        identity_runbook_configured=identity_runbook_configured,
        production_ready=production_ready,
        missing_items_zh=missing_items_zh,
        next_step_zh=(
            "补齐 OIDC 租户、MFA 策略、会话签名密钥、刷新令牌策略和身份 runbook；"
            "随后实现并启用生产 OIDC auth adapter。"
        ),
        message_zh=message,
    )


def _is_configured(key: str) -> bool:
    return bool(os.environ.get(key, "").strip())
