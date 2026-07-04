# Dubhe

Dubhe 是一套面向只会中文的非技术投资用户的 AI 投资研究与量化交易工作台。它将类 IDE 桌面工作区、移动端伴随应用、授权金融新闻 API、AI 分析、策略回测、模拟交易和受控实盘流程组合在一起，让不会编程、不会量化的用户也能通过中文自然语言完成新闻分析、策略制作、回测验证和交易审批。

本仓库从计划书和集成蓝图开始。项目策略是尽量缝合成熟开源系统，将自研代码限制在数据适配、任务编排、用户体验、权限控制和风控边界上，降低从零实现核心量化、AI 和交易系统带来的 bug 风险。

## 产品形态

- 桌面端：Windows 和 macOS，基于 Eclipse Theia Desktop。
- 移动端：iOS 和 Android，基于 Flutter。
- 云端同步：自建后端，使用 PostgreSQL/TimescaleDB、Redis、S3/MinIO、WebSocket、REST/gRPC、APNs 和 FCM。
- 量化引擎：QuantConnect LEAN。
- 金融数据层：OpenBB 加授权市场/新闻数据供应商。
- AI 研究层：Qlib、FinGPT/FinBERT 和 LLM tool-calling。
- 小白策略制作：Blockly 可视化策略积木，高级代码编辑保留在桌面工作区。

## 核心文档

- [完整计划书](docs/PROJECT_PLAN.md)
- [模拟测试兜底链](docs/SIMULATION_TEST_CHAIN.md)
- [总体架构](docs/ARCHITECTURE.md)
- [数据源规划](docs/DATA_SOURCES.md)
- [参考书](docs/REFERENCE_BOOK.md)
- [ADR-0001：产品架构决策](docs/adr/0001-product-architecture.md)

## 安全原则

AI 可以分析、解释、起草和提出建议，但不能直接发起实盘订单。所有实盘订单都必须经过确定性风控检查、审计日志记录和用户可控的审批规则。
