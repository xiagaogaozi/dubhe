from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import struct
import time
from typing import Literal
from urllib.parse import quote, urlencode

LOCAL_MFA_PLACEHOLDER_CODE = "000000"
TOTP_DIGITS = 6
TOTP_PERIOD_SECONDS = 30


def local_mfa_runtime_mode() -> Literal["local_placeholder", "totp"]:
    if _local_totp_configured():
        return "totp"
    return "local_placeholder"


def local_mfa_runtime_message_zh() -> str:
    if _local_totp_configured():
        return (
            "当前为本地开发认证：账号密码、设备令牌、角色权限和本机 TOTP 动态验证码。"
            "生产版仍需替换为 OIDC、正式 MFA、刷新令牌和集中身份审计。"
        )
    return (
        "当前为本地开发认证：账号密码、设备令牌、角色权限和占位 MFA。"
        "生产版需替换为 OIDC/MFA；本机可双击 Setup-Dubhe-MFA.cmd 启用动态验证码。"
    )


def verify_local_mfa_code(mfa_code: str, at_time: float | None = None) -> bool:
    code = mfa_code.strip()
    if _local_totp_configured():
        return verify_totp_code(
            code,
            os.environ["DUBHE_LOCAL_TOTP_SECRET"],
            at_time=at_time,
        )
    expected = os.environ.get("DUBHE_LOCAL_MFA_CODE", LOCAL_MFA_PLACEHOLDER_CODE).strip()
    return hmac.compare_digest(code, expected)


def generate_totp_secret(byte_count: int = 20) -> str:
    return base64.b32encode(secrets.token_bytes(byte_count)).decode("ascii").rstrip("=")


def build_otpauth_uri(
    secret: str,
    issuer: str = "Dubhe",
    account: str = "local-admin",
) -> str:
    label = quote(f"{issuer}:{account}")
    query = urlencode(
        {
            "secret": secret,
            "issuer": issuer,
            "algorithm": "SHA1",
            "digits": str(TOTP_DIGITS),
            "period": str(TOTP_PERIOD_SECONDS),
        }
    )
    return f"otpauth://totp/{label}?{query}"


def totp_code(
    secret: str,
    at_time: float | None = None,
    period: int = TOTP_PERIOD_SECONDS,
    digits: int = TOTP_DIGITS,
) -> str:
    timestamp = time.time() if at_time is None else at_time
    counter = int(timestamp // period)
    return hotp_code(secret, counter=counter, digits=digits)


def verify_totp_code(
    code: str,
    secret: str,
    at_time: float | None = None,
    window: int = 1,
    period: int = TOTP_PERIOD_SECONDS,
    digits: int = TOTP_DIGITS,
) -> bool:
    candidate = code.strip()
    if not (candidate.isdigit() and len(candidate) == digits):
        return False

    timestamp = time.time() if at_time is None else at_time
    current_counter = int(timestamp // period)
    for offset in range(-window, window + 1):
        expected = hotp_code(secret, counter=current_counter + offset, digits=digits)
        if hmac.compare_digest(candidate, expected):
            return True
    return False


def hotp_code(secret: str, counter: int, digits: int = TOTP_DIGITS) -> str:
    key = _decode_base32_secret(secret)
    message = struct.pack(">Q", counter)
    digest = hmac.new(key, message, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code_int = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{code_int % (10**digits):0{digits}d}"


def _local_totp_configured() -> bool:
    mode = os.environ.get("DUBHE_LOCAL_MFA_MODE", "").strip().lower()
    secret = os.environ.get("DUBHE_LOCAL_TOTP_SECRET", "").strip()
    if mode != "totp" or not secret:
        return False
    try:
        _decode_base32_secret(secret)
    except ValueError:
        return False
    return True


def _decode_base32_secret(secret: str) -> bytes:
    normalized = secret.strip().replace(" ", "").replace("-", "").upper()
    if not normalized:
        raise ValueError("TOTP secret is empty.")
    padding = "=" * ((8 - len(normalized) % 8) % 8)
    try:
        return base64.b32decode(normalized + padding, casefold=True)
    except Exception as exc:
        raise ValueError("TOTP secret is not valid Base32.") from exc
