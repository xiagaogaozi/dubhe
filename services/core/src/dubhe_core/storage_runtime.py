from __future__ import annotations

import os

from .models import StorageRuntimeStatus


def storage_runtime_status(db_path: str) -> StorageRuntimeStatus:
    persistent = db_path != ":memory:"
    target_backend = os.environ.get("DUBHE_STORAGE_BACKEND", "sqlite").strip().lower() or "sqlite"
    production_database_configured = _is_configured("DUBHE_DATABASE_URL") or _is_configured(
        "DATABASE_URL"
    )
    redis_configured = _is_configured("DUBHE_REDIS_URL") or _is_configured("REDIS_URL")
    object_storage_configured = all(
        _is_configured(key)
        for key in [
            "DUBHE_OBJECT_STORAGE_ENDPOINT",
            "DUBHE_OBJECT_STORAGE_BUCKET",
            "DUBHE_OBJECT_STORAGE_ACCESS_KEY_ID",
            "DUBHE_OBJECT_STORAGE_SECRET_ACCESS_KEY",
        ]
    )
    backup_runbook_configured = _is_configured("DUBHE_BACKUP_RUNBOOK_URL")
    migration_runbook_configured = _is_configured("DUBHE_MIGRATION_RUNBOOK_URL")

    missing_items_zh = []
    if target_backend != "postgresql":
        missing_items_zh.append("DUBHE_STORAGE_BACKEND=postgresql")
    if not production_database_configured:
        missing_items_zh.append("DUBHE_DATABASE_URL 或 DATABASE_URL")
    if not redis_configured:
        missing_items_zh.append("DUBHE_REDIS_URL 或 REDIS_URL")
    if not object_storage_configured:
        missing_items_zh.append("S3/MinIO endpoint、bucket、access key 和 secret")
    if not backup_runbook_configured:
        missing_items_zh.append("DUBHE_BACKUP_RUNBOOK_URL")
    if not migration_runbook_configured:
        missing_items_zh.append("DUBHE_MIGRATION_RUNBOOK_URL")

    # The active adapter is still SQLite. Keep production_ready false until the
    # PostgreSQL/TimescaleDB store is implemented and the process actually runs it.
    production_ready = False
    if missing_items_zh:
        message = (
            f"当前运行后端为 SQLite（{db_path}）。生产存储配置仍缺少："
            f"{'、'.join(missing_items_zh)}。"
        )
    else:
        message = (
            "生产存储环境变量已基本填写，但当前运行后端仍为 SQLite；"
            "需要完成 PostgreSQL/TimescaleDB store、迁移和切换演练后才能通过生产门禁。"
        )

    return StorageRuntimeStatus(
        backend="sqlite",
        path=db_path,
        persistent=persistent,
        target_backend=target_backend,
        production_database_configured=production_database_configured,
        redis_configured=redis_configured,
        object_storage_configured=object_storage_configured,
        backup_runbook_configured=backup_runbook_configured,
        migration_runbook_configured=migration_runbook_configured,
        production_ready=production_ready,
        missing_items_zh=missing_items_zh,
        next_step_zh=(
            "补齐 PostgreSQL/TimescaleDB、Redis、S3/MinIO、备份和迁移配置；"
            "随后实现并启用 PostgreSQL store，再做备份恢复演练。"
        ),
        message_zh=message,
    )


def _is_configured(key: str) -> bool:
    return bool(os.environ.get(key, "").strip())
