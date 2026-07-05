import 'dart:convert';

import 'package:dubhe_companion/src/core_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('health check verifies Dubhe Core without bearer token', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'device-token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/health');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          '{"status":"ok","service":"dubhe-core"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect(await client.checkHealth(), isTrue);
  });

  test('login stores access token from Dubhe Core', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/auth/login');
        return http.Response(
          '''
          {
            "user_id": "user_1",
            "device_id": "device_1",
            "workspace_id": "workspace_1",
            "access_token": "dubhe_dev_token",
            "role": "admin",
            "platform": "ios",
            "device_name": "Dubhe Companion",
            "created_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final session = await client.login(
      accountKey: 'local-demo',
      password: 'Dubhe@2026',
      mfaCode: '000000',
      deviceName: 'Dubhe Companion',
    );

    expect(session.roleZh, '管理员');
    expect(client.accessToken, 'dubhe_dev_token');
  });

  test('paper portfolio parses cash, equity, and positions', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer dubhe_dev_token');
        expect(request.url.path, '/v1/simulation/paper-portfolio/demo_account');
        return http.Response(
          '''
          {
            "account_id": "demo_account",
            "cash_by_currency": {"USD": 99000, "HKD": 1000000, "CNY": 1000000},
            "equity_by_currency": {"USD": 100000, "HKD": 1000000, "CNY": 1000000},
            "realized_pnl_by_currency": {"USD": 0, "HKD": 0, "CNY": 0},
            "positions": [
              {
                "market": "US",
                "symbol": "NVDA",
                "currency": "USD",
                "quantity": 1,
                "avg_cost": 1000,
                "last_price": 1000,
                "market_value": 1000,
                "unrealized_pnl": 0,
                "updated_at": "2026-07-05T00:00:00Z"
              }
            ],
            "updated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final portfolio = await client.fetchPaperPortfolio(defaultPaperAccountId);

    expect(portfolio.cashByCurrency['USD'], 99000);
    expect(portfolio.equityByCurrency['USD'], 100000);
    expect(portfolio.positions.single.symbol, 'NVDA');
    expect(portfolio.positions.single.quantity, 1);
  });

  test('workspace snapshot parses watchlist and sync events', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/workspaces/workspace_1/snapshot');
        expect(request.url.queryParameters['since_sequence'], '0');
        expect(request.headers['authorization'], 'Bearer dubhe_dev_token');
        return http.Response(
          '''
          {
            "workspace": {
              "id": "workspace_1",
              "owner_user_id": "user_1",
              "name": "同步测试账户的默认工作区",
              "created_at": "2026-07-05T00:00:00Z",
              "updated_at": "2026-07-05T00:00:00Z"
            },
            "watchlist": [
              {
                "id": "watch_1",
                "workspace_id": "workspace_1",
                "symbol": "NVDA",
                "name": "NVIDIA",
                "market": "US",
                "notes_zh": "AI 芯片龙头",
                "added_at": "2026-07-05T00:00:00Z",
                "updated_at": "2026-07-05T00:00:00Z"
              }
            ],
            "news_events": [],
            "analyses": [],
            "risk_decisions": [],
            "approval_requests": [],
            "paper_orders": [],
            "broker_orders": [],
            "paper_portfolios": [],
            "strategy_drafts": [
              {
                "id": "strategy_draft_1",
                "strategy_version_id": "strategy_v_1",
                "name": "Blockly 新闻情绪策略",
                "spec": {
                  "strategy_name": "Blockly 新闻情绪策略",
                  "market_scope": ["US"],
                  "asset_universe": ["NVDA"],
                  "entry_rules": ["新闻情绪为正面且影响分大于 0.7"],
                  "exit_rules": ["新闻影响消退或触发止损"],
                  "risk_limits": {"max_order_notional": 10000},
                  "timeframe": "1d",
                  "rebalance_rule": "daily",
                  "data_dependencies": ["news", "market_bars"],
                  "broker_permissions": ["paper"]
                },
                "explanation_zh": "由 Blockly 策略工坊生成。",
                "generated_code": "strategy blockly",
                "source_analysis_id": "blockly_manual",
                "created_at": "2026-07-05T00:01:00Z"
              }
            ],
            "backtest_results": [
              {
                "id": "backtest_1",
                "strategy_version_id": "strategy_v_1",
                "replay_scenario": "golden_news_sentiment_v1",
                "symbol": "NVDA",
                "market": "US",
                "initial_cash": 100000,
                "final_equity": 112400,
                "total_return": 0.124,
                "benchmark_return": 0.08,
                "max_drawdown": 0.041,
                "win_rate": 0.58,
                "trade_count": 2,
                "risk_notes_zh": ["仅用于纸面验证。"],
                "equity_curve": [],
                "generated_at": "2026-07-05T00:02:00Z"
              }
            ],
            "assistant_turns": [
              {
                "id": "assistant_1",
                "workspace_id": "workspace_1",
                "question_zh": "下一步怎么验证？",
                "answer_zh": "先完成纸面验证。",
                "citations": [{"label_zh": "回测", "ref": "backtest_1"}],
                "suggested_actions_zh": ["提交纸面买入"],
                "safety_notes_zh": ["不会连接真实券商。"],
                "model_provider": "deterministic",
                "model_name": null,
                "fallback_used": true,
                "context_refs": ["analysis_1", "strategy_v_1", "backtest_1"],
                "created_by_user_id": "user_1",
                "created_by_device_id": "device_1",
                "generated_at": "2026-07-05T00:03:00Z"
              }
            ],
            "events": [
              {
                "id": "sync_1",
                "workspace_id": "workspace_1",
                "sequence": 1,
                "entity_type": "watchlist_item",
                "entity_id": "watch_1",
                "action": "created",
                "payload": {"symbol": "NVDA"},
                "created_at": "2026-07-05T00:00:00Z"
              }
            ],
            "server_sequence": 7
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final snapshot = await client.fetchWorkspaceSnapshot(
      workspaceId: 'workspace_1',
    );

    expect(snapshot.workspaceName, '同步测试账户的默认工作区');
    expect(snapshot.serverSequence, 7);
    expect(snapshot.watchlist.single.symbol, 'NVDA');
    expect(snapshot.strategyDrafts.single.name, 'Blockly 新闻情绪策略');
    expect(snapshot.strategyDrafts.single.spec.brokerPermissions, ['paper']);
    expect(snapshot.backtestResults.single.strategyVersionId, 'strategy_v_1');
    expect(snapshot.backtestResults.single.totalReturn, 0.124);
    expect(snapshot.assistantTurns.single.questionZh, '下一步怎么验证？');
    expect(snapshot.assistantTurns.single.citations.single.ref, 'backtest_1');
    expect(snapshot.assistantTurns.single.suggestedActionsZh, ['提交纸面买入']);
    expect(snapshot.events.single.entityType, 'watchlist_item');
  });

  test('workspace sync polling endpoint parses events after cursor', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/workspaces/workspace_1/sync-events');
        expect(request.url.queryParameters['since_sequence'], '7');
        expect(request.headers['authorization'], 'Bearer dubhe_dev_token');
        return http.Response(
          '''
          [
            {
              "id": "sync_8",
              "workspace_id": "workspace_1",
              "sequence": 8,
              "entity_type": "kill_switch",
              "entity_id": "global",
              "action": "updated",
              "payload": {"enabled": true},
              "created_at": "2026-07-05T00:03:00Z"
            }
          ]
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final events = await client.fetchWorkspaceSyncEvents(
      workspaceId: 'workspace_1',
      sinceSequence: 7,
    );

    expect(events, hasLength(1));
    expect(events.single.sequence, 8);
    expect(events.single.entityType, 'kill_switch');
  });

  test('workspace sync websocket uri uses ws scheme and token cursor', () {
    final httpClient = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
    );
    final httpsClient = CoreClient(
      baseUrl: 'https://core.example.com',
      accessToken: 'secure_token',
    );

    final localUri = httpClient.workspaceSyncEventsUri(
      workspaceId: 'workspace_1',
      sinceSequence: 7,
    );
    final secureUri = httpsClient.workspaceSyncEventsUri(
      workspaceId: 'workspace_2',
      sinceSequence: 11,
    );

    expect(localUri.scheme, 'ws');
    expect(localUri.path, '/v1/workspaces/workspace_1/sync-events/ws');
    expect(localUri.queryParameters['access_token'], 'dubhe_dev_token');
    expect(localUri.queryParameters['since_sequence'], '7');
    expect(secureUri.scheme, 'wss');
    expect(secureUri.path, '/v1/workspaces/workspace_2/sync-events/ws');
    expect(secureUri.queryParameters['access_token'], 'secure_token');

    httpClient.close();
    httpsClient.close();
  });

  test('news feed can request global market without a symbol', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'device-token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/news/feed');
        expect(request.url.queryParameters['market'], 'GLOBAL');
        expect(request.url.queryParameters['live'], 'true');
        expect(request.url.queryParameters.containsKey('symbol'), isFalse);
        return http.Response(
          '''
          {
            "events": [],
            "provider_status": [],
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final feed = await client.fetchNewsFeed(
      market: 'GLOBAL',
      symbol: ' ',
      live: true,
    );

    expect(feed.events, isEmpty);
  });

  test(
    'sync event parser accepts websocket messages and ignores malformed data',
    () {
      final event = SyncEvent.tryParseMessage(
        jsonEncode({
          'id': 'sync_2',
          'workspace_id': 'workspace_1',
          'sequence': 8,
          'entity_type': 'paper_portfolio',
          'entity_id': 'demo_account',
          'action': 'updated',
          'payload': {'account_id': 'demo_account'},
          'created_at': '2026-07-05T00:01:00Z',
        }),
      );
      final binaryEvent = SyncEvent.tryParseMessage(
        utf8.encode(
          jsonEncode({
            'sequence': 9,
            'entity_type': 'approval_request',
            'action': 'created',
            'created_at': '2026-07-05T00:02:00Z',
          }),
        ),
      );

      expect(event, isNotNull);
      expect(event!.sequence, 8);
      expect(event.entityType, 'paper_portfolio');
      expect(event.action, 'updated');
      expect(binaryEvent, isNotNull);
      expect(binaryEvent!.entityType, 'approval_request');
      expect(SyncEvent.tryParseMessage('not-json'), isNull);
    },
  );

  test('system status parses configuration readiness', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/system/status');
        return http.Response(
          '''
          {
            "service": "dubhe-core",
            "version": "0.1.0",
            "language": "zh-CN",
            "storage": {
              "backend": "sqlite",
              "path": "D:/dubhe-data/dubhe-core.sqlite",
              "persistent": true,
              "message_zh": "SQLite 持久化存储已启用。"
            },
            "auth": {
              "mode": "local_dev",
              "mfa_mode": "local_placeholder",
              "message_zh": "当前为本地开发认证。"
            },
            "config_items": [
              {
                "key": "FINNHUB_API_KEY",
                "label_zh": "Finnhub 授权新闻源 Key",
                "configured": false,
                "required_for": "Finnhub company-news 美股公司新闻",
                "message_zh": "未配置，Finnhub 授权新闻源会被跳过。"
              },
              {
                "key": "ALPHA_VANTAGE_API_KEY",
                "label_zh": "Alpha Vantage 新闻情绪 Key",
                "configured": true,
                "required_for": "Alpha Vantage NEWS_SENTIMENT 新闻情绪",
                "message_zh": "已配置，刷新实时新闻时会尝试调用 Alpha Vantage。"
              }
            ],
            "news_adapters": [
              {
                "provider": "finnhub_company_news",
                "label_zh": "Finnhub 公司新闻",
                "market_coverage": ["US", "GLOBAL"],
                "configured": false,
                "enabled": false,
                "requires_license": true,
                "message_zh": "待配置：缺少 FINNHUB_API_KEY，实时拉取时会跳过。"
              },
              {
                "provider": "fixture",
                "label_zh": "本地演示新闻源",
                "market_coverage": ["A_SHARE", "HK", "US", "GLOBAL"],
                "configured": true,
                "enabled": true,
                "requires_license": false,
                "message_zh": "可用：真实来源为空或故障时兜底。"
              }
            ],
            "news_coverage": [
              {
                "market": "A_SHARE",
                "label_zh": "A 股",
                "demo_ready": true,
                "licensed_source_ready": false,
                "production_ready": false,
                "available_sources_zh": ["本地演示新闻源"],
                "missing_sources_zh": ["Wind", "同花顺 iFinD"],
                "message_zh": "当前仅适合流程测试。",
                "next_step_zh": "生产部署前需要签约 A 股数据/新闻供应商。"
              },
              {
                "market": "US",
                "label_zh": "美股",
                "demo_ready": true,
                "licensed_source_ready": false,
                "production_ready": false,
                "available_sources_zh": ["本地演示新闻源"],
                "missing_sources_zh": ["FINNHUB_API_KEY"],
                "message_zh": "缺少授权新闻 key。",
                "next_step_zh": "补齐授权新闻 key。"
              }
            ],
            "install_packages": [
              {
                "platform": "windows",
                "label_zh": "Windows 便携版",
                "artifact_type": "portable-exe",
                "available": true,
                "local_path": "D:/github/dubhe-main/apps/theia-desktop/app/dist/Dubhe-0.1.0-win-x64-portable.exe",
                "size_bytes": 115711072,
                "build_channel_zh": "本机 electron-builder",
                "message_zh": "可直接拷贝运行。",
                "next_step_zh": "需要重新生成时执行 electron-builder。"
              },
              {
                "platform": "ios",
                "label_zh": "iOS 应用包",
                "artifact_type": "runner-app",
                "available": false,
                "local_path": "",
                "size_bytes": 0,
                "build_channel_zh": "macOS CI / Xcode",
                "message_zh": "当前 Windows 本机不能生成 iOS 安装包。",
                "next_step_zh": "在 macOS + Xcode 中构建。"
              }
            ],
            "local_launchers": [
              {
                "id": "start-local",
                "label_zh": "启动 Dubhe（本机）",
                "description_zh": "打开本机 Core 与桌面客户端。",
                "local_path": "D:/github/dubhe-main/Start-Dubhe.cmd",
                "available": true,
                "message_zh": "双击即可启动本机 Dubhe。",
                "next_step_zh": "如果无法启动，先运行检查。"
              },
              {
                "id": "build-user-kit",
                "label_zh": "生成小白用户包",
                "description_zh": "整理安装包、指南和检查报告。",
                "local_path": "D:/github/dubhe-main/Build-Dubhe-User-Kit.cmd",
                "available": false,
                "message_zh": "未找到 Build-Dubhe-User-Kit.cmd。",
                "next_step_zh": "请确认仓库根目录。"
              }
            ],
            "trading": {
              "paper_broker_enabled": true,
              "live_trading_enabled": false,
              "message_zh": "纸面交易已启用；实盘交易保持关闭。"
            },
            "llm": {
              "provider": "openai_compatible",
              "model": null,
              "configured": false,
              "enabled": false,
              "fallback_available": true,
              "message_zh": "未配置外部模型，当前使用本地确定性安全兜底。"
            },
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final status = await client.fetchSystemStatus();

    expect(status.service, 'dubhe-core');
    expect(status.storagePath, 'D:/dubhe-data/dubhe-core.sqlite');
    expect(status.paperBrokerEnabled, isTrue);
    expect(status.liveTradingEnabled, isFalse);
    expect(status.llm.enabled, isFalse);
    expect(status.llm.displayName, '本地兜底');
    expect(status.missingConfigCount, 1);
    expect(status.enabledAdapterCount, 1);
    expect(status.enabledLicensedAdapterCount, 0);
    expect(status.configItems.first.key, 'FINNHUB_API_KEY');
    expect(status.newsAdapters.first.requiresLicense, isTrue);
    expect(status.newsAdapters.last.labelZh, '本地演示新闻源');
    expect(status.newsCoverage, hasLength(2));
    expect(status.newsCoverage.first.labelZh, 'A 股');
    expect(status.newsCoverage.first.productionReady, isFalse);
    expect(
      status.newsCoverage.last.missingSourcesZh,
      contains('FINNHUB_API_KEY'),
    );
    expect(status.installPackages, hasLength(2));
    expect(status.installPackages.first.available, isTrue);
    expect(status.installPackages.first.sizeBytes, 115711072);
    expect(status.installPackages.last.platform, 'ios');
    expect(status.installPackages.last.available, isFalse);
    expect(status.localLaunchers, hasLength(2));
    expect(status.localLaunchers.first.id, 'start-local');
    expect(status.localLaunchers.first.available, isTrue);
    expect(
      status.localLaunchers.last.localPath,
      'D:/github/dubhe-main/Build-Dubhe-User-Kit.cmd',
    );
  });

  test('external service checks parse readiness and live query', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/system/external-checks');
        expect(request.url.queryParameters['live'], 'true');
        return http.Response(
          '''
          {
            "service": "dubhe-core",
            "language": "zh-CN",
            "live": true,
            "overall_status": "partial",
            "ready_count": 1,
            "total_count": 2,
            "checks": [
              {
                "service": "llm_openai_compatible",
                "label_zh": "AI 模型 OpenAI-compatible",
                "configured": true,
                "live_checked": true,
                "status": "ok",
                "duration_ms": 42,
                "message_zh": "AI 模型 live 检查通过。",
                "next_step_zh": "失败时检查模型名和 API Key。",
                "checked_at": "2026-07-05T00:00:00Z"
              },
              {
                "service": "finnhub_company_news",
                "label_zh": "Finnhub 公司新闻",
                "configured": false,
                "live_checked": false,
                "status": "skipped",
                "duration_ms": 0,
                "message_zh": "未配置 FINNHUB_API_KEY。",
                "next_step_zh": "生产前确认授权。",
                "checked_at": "2026-07-05T00:00:00Z"
              }
            ],
            "message_zh": "已配置部分外部服务。",
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final checks = await client.fetchExternalServiceChecks(live: true);

    expect(checks.live, isTrue);
    expect(checks.ready, isFalse);
    expect(checks.statusZh, '部分可用');
    expect(checks.readyCount, 1);
    expect(checks.checks.first.ok, isTrue);
    expect(checks.checks.first.statusZh, '42ms');
    expect(checks.checks.last.skipped, isTrue);
    expect(checks.checks.last.statusZh, '未配置');
  });

  test('production readiness parses blocking gate items', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/system/production-readiness');
        return http.Response(
          '''
          {
            "service": "dubhe-core",
            "language": "zh-CN",
            "production_ready": false,
            "overall_status": "not_ready",
            "pass_count": 1,
            "warning_count": 1,
            "blocking_count": 1,
            "total_count": 3,
            "message_zh": "生产门禁未通过：还有 1 个阻断项需要补齐。",
            "items": [
              {
                "id": "local_smoke_chain",
                "category_zh": "本地可用性",
                "requirement_zh": "主链路烟测可运行。",
                "status": "pass",
                "blocking": false,
                "evidence_zh": "已提供 Smoke-Dubhe.cmd。",
                "next_step_zh": "发布前运行 smoke。"
              },
              {
                "id": "package_windows",
                "category_zh": "四端安装包",
                "requirement_zh": "Windows 安装包必须可交付。",
                "status": "warn",
                "blocking": false,
                "evidence_zh": "可用于内测。",
                "next_step_zh": "生产前签名。"
              },
              {
                "id": "production_storage",
                "category_zh": "云同步与存储",
                "requirement_zh": "生产环境必须使用 PostgreSQL。",
                "status": "fail",
                "blocking": true,
                "evidence_zh": "当前存储后端为 sqlite。",
                "next_step_zh": "部署 PostgreSQL/TimescaleDB。"
              }
            ],
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final readiness = await client.fetchProductionReadiness();

    expect(readiness.productionReady, isFalse);
    expect(readiness.statusZh, '1 个阻断');
    expect(readiness.passCount, 1);
    expect(readiness.warningCount, 1);
    expect(readiness.blockingCount, 1);
    expect(readiness.items.first.passed, isTrue);
    expect(readiness.items[1].warning, isTrue);
    expect(readiness.items.last.statusZh, '阻断');
    expect(readiness.items.last.nextStepZh, contains('PostgreSQL'));
  });

  test('smoke workflow report parses status and steps', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/system/smoke-report');
        return http.Response(
          '''
          {
            "service": "dubhe-core",
            "language": "zh-CN",
            "available": true,
            "status": "passed",
            "message_zh": "最近一次主链路烟测通过。",
            "generated_at": "2026-07-05T07:19:07Z",
            "core_url": "http://127.0.0.1:8000",
            "market": "US",
            "symbol": "NVDA",
            "failure": null,
            "report_path": "D:/github/dubhe-main/.dubhe-run/smoke-core-workflow.json",
            "artifacts": {
              "paper_account_id": "smoke-paper",
              "workspace_sequence": 15
            },
            "steps": [
              {
                "name": "Core 健康检查",
                "status": "passed",
                "duration_ms": 12,
                "message": "通过",
                "data": null
              },
              {
                "name": "纸面组合入账",
                "status": "passed",
                "duration_ms": 22,
                "message": "通过",
                "data": null
              }
            ]
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final report = await client.fetchSmokeWorkflowReport();
    expect(report.available, isTrue);
    expect(report.passed, isTrue);
    expect(report.symbol, 'NVDA');
    expect(report.artifacts['paper_account_id'], 'smoke-paper');
    expect(report.steps, hasLength(2));
    expect(report.steps.last.name, '纸面组合入账');
    expect(report.steps.last.durationMs, 22);
  });

  test('local runtime config reads and updates redacted items', () async {
    var requestIndex = 0;
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'device-token',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/runtime/local-config');
        expect(request.headers['authorization'], 'Bearer device-token');
        requestIndex += 1;
        if (requestIndex == 1) {
          expect(request.method, 'GET');
        } else {
          expect(request.method, 'PUT');
          expect(request.body, contains('"DUBHE_LLM_MODEL":"gpt-test"'));
        }
        return http.Response(
          '''
          {
            "editable": true,
            "exists": true,
            "path": "D:/github/dubhe-main/config/dubhe.local.env",
            "items": [
              {
                "key": "DUBHE_LLM_MODEL",
                "label_zh": "AI 模型名称",
                "description_zh": "模型名",
                "group_zh": "AI 模型",
                "placeholder": "服务商提供的 model id",
                "setup_hint_zh": "复制控制台里的模型 ID。",
                "configured": true,
                "secret": false,
                "source": "local_file",
                "masked_value": "gpt-test",
                "restart_required": false
              },
              {
                "key": "FINNHUB_API_KEY",
                "label_zh": "Finnhub 授权新闻 Key",
                "description_zh": "密钥",
                "group_zh": "授权新闻源",
                "placeholder": "Finnhub 控制台 API key",
                "setup_hint_zh": "生产使用前确认授权条款。",
                "configured": true,
                "secret": true,
                "source": "local_file",
                "masked_value": "••••oken",
                "restart_required": false
              }
            ],
            "message_zh": "本地配置文件可编辑；已读取 2/2 项。",
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final config = await client.fetchLocalRuntimeConfig();
    expect(config.exists, isTrue);
    expect(config.items.first.maskedValue, 'gpt-test');
    expect(config.items.first.groupZh, 'AI 模型');
    expect(config.items.first.placeholder, contains('model id'));
    expect(config.items.last.secret, isTrue);
    expect(config.items.last.setupHintZh, contains('授权条款'));
    expect(config.items.last.maskedValue, '••••oken');

    final updated = await client.updateLocalRuntimeConfig(
      values: const {'DUBHE_LLM_MODEL': 'gpt-test'},
    );
    expect(updated.messageZh, contains('本地配置文件可编辑'));
    expect(requestIndex, 2);
  });

  test('onboarding checklist parses next action and steps', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'device-token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/onboarding/checklist');
        expect(request.headers['authorization'], 'Bearer device-token');
        return http.Response(
          '''
          {
            "service": "dubhe-core",
            "language": "zh-CN",
            "complete_count": 2,
            "total_count": 3,
            "next_action_zh": "创建账号或登录工作台。",
            "steps": [
              {
                "id": "core_connected",
                "label_zh": "连接 Core",
                "status": "complete",
                "message_zh": "Dubhe Core 正在响应请求。",
                "action_zh": null
              },
              {
                "id": "account_login",
                "label_zh": "账号登录",
                "status": "action_required",
                "message_zh": "请创建或登录本地账号。",
                "action_zh": "创建账号或登录工作台。"
              },
              {
                "id": "runtime_config",
                "label_zh": "模型与授权新闻源",
                "status": "warning",
                "message_zh": "当前可用本地兜底。",
                "action_zh": "填写模型与新闻源 key。"
              }
            ],
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final checklist = await client.fetchOnboardingChecklist();
    expect(checklist.completeCount, 2);
    expect(checklist.totalCount, 3);
    expect(checklist.nextActionZh, contains('登录'));
    expect(checklist.steps.first.complete, isTrue);
    expect(checklist.steps[1].actionZh, contains('创建账号'));
    expect(checklist.steps.last.warning, isTrue);
  });

  test(
    'assistant chat sends portfolio research context and parses guidance',
    () async {
      final client = CoreClient(
        baseUrl: 'http://127.0.0.1:8019',
        accessToken: 'dubhe_dev_token',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/assistant/chat');
          expect(request.headers['authorization'], 'Bearer dubhe_dev_token');

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final context = body['context'] as Map<String, dynamic>;
          expect(body['question_zh'], '下一步怎么验证？');
          expect(context['news_event']['id'], 'news_1');
          expect(context['analysis']['id'], 'analysis_1');
          expect(context['strategy']['strategy_version_id'], 'strategy_v_1');
          expect(context['backtest']['strategy_version_id'], 'strategy_v_1');
          expect(context['backtest']['total_return'], 0.124);

          return http.Response(
            '''
          {
            "id": "assistant_1",
            "answer_zh": "先完成纸面验证，再进入审批。",
            "citations": [
              {"label_zh": "新闻", "ref": "news_1"},
              {"label_zh": "回测", "ref": "backtest_1"}
            ],
            "suggested_actions_zh": ["复查最大回撤", "提交纸面买入"],
            "safety_notes_zh": ["不会连接真实券商。"],
            "model_provider": "openai_compatible",
            "model_name": "gpt-test",
            "fallback_used": false,
            "generated_at": "2026-07-05T00:00:00Z"
          }
          ''',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final event = NewsEvent.fromJson({
        'id': 'news_1',
        'source_name': 'fixture',
        'title_original': 'NVDA rises on AI demand',
        'title_zh': '英伟达受 AI 需求推动上涨',
        'published_at': '2026-07-05T00:00:00Z',
        'market_scope': ['US'],
        'tickers': ['NVDA'],
        'event_type': 'earnings',
        'authority_score': 0.9,
      });
      final analysis = NewsAnalysis(
        id: 'analysis_1',
        newsEventId: 'news_1',
        summaryZh: 'AI 需求改善，短线偏正面。',
        sentiment: 'positive',
        impactScore: 0.83,
        affectedTickers: const ['NVDA'],
        sourceRefs: const ['news_1'],
        confidence: 0.84,
        generatedAt: '2026-07-05T00:00:00Z',
      );
      final strategy = StrategyDraft(
        id: 'draft_1',
        strategyVersionId: 'strategy_v_1',
        name: '新闻情绪策略',
        spec: StrategySpec(
          strategyName: '新闻情绪策略',
          marketScope: const ['US'],
          assetUniverse: const ['NVDA'],
          entryRules: const ['影响分大于 0.7'],
          exitRules: const ['触发止损'],
          riskLimits: const {'max_order_notional': 10000},
          timeframe: '1d',
          rebalanceRule: 'daily',
          dataDependencies: const ['news', 'market_bars'],
          brokerPermissions: const ['paper'],
        ),
        explanationZh: '只用于纸面验证。',
        generatedCode: 'class Demo {}',
        sourceAnalysisId: 'analysis_1',
        createdAt: '2026-07-05T00:00:00Z',
      );
      final backtest = BacktestResult(
        id: 'backtest_1',
        strategyVersionId: 'strategy_v_1',
        replayScenario: 'golden_news_sentiment_v1',
        symbol: 'NVDA',
        market: 'US',
        initialCash: 100000,
        finalEquity: 112400,
        totalReturn: 0.124,
        benchmarkReturn: 0.08,
        maxDrawdown: 0.041,
        winRate: 0.58,
        tradeCount: 2,
        riskNotesZh: const ['仅用于纸面验证。'],
      );

      final response = await client.askAssistant(
        questionZh: '下一步怎么验证？',
        newsEvent: event,
        analysis: analysis,
        strategyDraft: strategy,
        backtestResult: backtest,
      );

      expect(response.id, 'assistant_1');
      expect(response.answerZh, contains('纸面验证'));
      expect(response.citations, hasLength(2));
      expect(response.citations.last.ref, 'backtest_1');
      expect(response.suggestedActionsZh, ['复查最大回撤', '提交纸面买入']);
      expect(response.safetyNotesZh.single, '不会连接真实券商。');
      expect(response.modelName, 'gpt-test');
      expect(response.fallbackUsed, isFalse);
    },
  );

  test(
    'strategy, backtest, and paper order use Core workflow endpoints',
    () async {
      final requests = <http.Request>[];
      final client = CoreClient(
        baseUrl: 'http://127.0.0.1:8000',
        accessToken: 'dubhe_dev_token',
        client: MockClient((request) async {
          requests.add(request);
          final body = request.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(request.body) as Map<String, dynamic>;

          if (request.url.path == '/v1/strategy/drafts/from-analysis') {
            expect(body['symbol'], 'NVDA');
            expect(body['analysis']['id'], 'analysis_1');
            return http.Response(
              '''
            {
              "id": "draft_1",
              "strategy_version_id": "strategy_v_1",
              "name": "新闻情绪策略",
              "spec": {
                "strategy_name": "新闻情绪策略",
                "market_scope": ["US"],
                "asset_universe": ["NVDA"],
                "entry_rules": ["影响分大于 0.7"],
                "exit_rules": ["止损"],
                "risk_limits": {"max_order_notional": 10000},
                "timeframe": "1d",
                "rebalance_rule": "daily",
                "data_dependencies": ["news"],
                "broker_permissions": ["paper"]
              },
              "explanation_zh": "只用于纸面交易验证。",
              "generated_code": "class Demo {}",
              "source_analysis_id": "analysis_1",
              "created_at": "2026-07-05T00:00:00Z"
            }
            ''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/v1/backtests/replay') {
            expect(body['strategy']['strategy_version_id'], 'strategy_v_1');
            return http.Response(
              '''
            {
              "id": "backtest_1",
              "strategy_version_id": "strategy_v_1",
              "replay_scenario": "golden_news_sentiment_v1",
              "symbol": "NVDA",
              "market": "US",
              "initial_cash": 100000,
              "final_equity": 112400,
              "total_return": 0.124,
              "benchmark_return": 0.08,
              "max_drawdown": 0.041,
              "win_rate": 0.58,
              "trade_count": 2,
              "risk_notes_zh": ["仅用于纸面验证。"],
              "equity_curve": [],
              "generated_at": "2026-07-05T00:00:00Z"
            }
            ''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/v1/simulation/paper-orders') {
            expect(request.headers['authorization'], 'Bearer dubhe_dev_token');
            expect(body['destination'], 'paper');
            expect(body['source_refs'], ['analysis_1']);
            return http.Response(
              '''
            {
              "id": "paper_1",
              "order_intent_id": "intent_1",
              "status": "accepted",
              "risk_decision": {
                "id": "risk_1",
                "order_intent_id": "intent_1",
                "status": "approved",
                "allowed_destination": "paper",
                "notional": 120,
                "reasons_zh": ["通过纸面交易。"],
                "evaluated_at": "2026-07-05T00:00:00Z"
              },
              "broker_order": null,
              "submitted_at": "2026-07-05T00:00:00Z",
              "message_zh": "纸面订单已通过模拟券商成交。"
            }
            ''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('not found', 404);
        }),
      );

      final analysis = NewsAnalysis(
        id: 'analysis_1',
        newsEventId: 'news_1',
        summaryZh: '中文影响分析',
        sentiment: 'positive',
        impactScore: 0.83,
        affectedTickers: const ['NVDA'],
        sourceRefs: const ['fixture'],
        confidence: 0.84,
        generatedAt: '2026-07-05T00:00:00Z',
      );

      final draft = await client.draftStrategyFromAnalysis(
        analysis: analysis,
        symbol: 'NVDA',
        market: 'US',
      );
      final backtest = await client.runReplayBacktest(strategy: draft);
      final order = await client.submitPaperBuy(
        accountId: defaultPaperAccountId,
        strategyVersionId: draft.strategyVersionId,
        market: 'US',
        symbol: 'NVDA',
        quantity: 1,
        estimatedPrice: 120,
        currency: 'USD',
        sourceRefs: const ['analysis_1'],
      );

      expect(draft.strategyVersionId, 'strategy_v_1');
      expect(backtest.totalReturn, 0.124);
      expect(order.status, 'accepted');
      expect(requests.map((request) => request.url.path), [
        '/v1/strategy/drafts/from-analysis',
        '/v1/backtests/replay',
        '/v1/simulation/paper-orders',
      ]);
    },
  );

  test('live approval demo creates a live risk evaluation only', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/risk/evaluate');
        expect(request.headers['authorization'], 'Bearer dubhe_dev_token');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['account_id'], defaultPaperAccountId);
        expect(body['strategy_version_id'], 'strategy_v_1');
        expect(body['market'], 'US');
        expect(body['symbol'], 'NVDA');
        expect(body['created_by'], 'ai');
        expect(body['destination'], 'live');
        expect(body['source_refs'], ['analysis_1']);

        return http.Response(
          '''
          {
            "id": "risk_approval_1",
            "order_intent_id": "intent_live_1",
            "status": "requires_approval",
            "allowed_destination": "live_after_approval",
            "notional": 120,
            "reasons_zh": ["实盘订单需要人工审批。"],
            "evaluated_at": "2026-07-05T00:00:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final decision = await client.createLiveApprovalDemo(
      accountId: defaultPaperAccountId,
      strategyVersionId: 'strategy_v_1',
      market: 'US',
      symbol: 'NVDA',
      quantity: 1,
      estimatedPrice: 120,
      currency: 'USD',
      sourceRefs: const ['analysis_1'],
    );

    expect(decision.requiresApproval, isTrue);
    expect(decision.allowedDestination, 'live_after_approval');
    expect(decision.notional, 120);
  });

  test('kill switch endpoints parse and send risk manager state', () async {
    var callCount = 0;
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
      client: MockClient((request) async {
        callCount += 1;
        expect(request.url.path, '/v1/risk/kill-switch');
        expect(request.headers['authorization'], 'Bearer dubhe_dev_token');

        if (request.method == 'GET') {
          return http.Response(
            '''
            {
              "enabled": false,
              "reason_zh": "未启用 kill switch。",
              "updated_by": "system",
              "updated_at": "2026-07-05T00:00:00Z"
            }
            ''',
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['enabled'], isTrue);
        expect(body['reason_zh'], '移动端手动启用 kill switch。');
        expect(body['updated_by'], 'Dubhe Companion');
        return http.Response(
          '''
          {
            "enabled": true,
            "reason_zh": "移动端手动启用 kill switch。",
            "updated_by": "Dubhe Companion",
            "updated_at": "2026-07-05T00:01:00Z"
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final initial = await client.fetchKillSwitch();
    final enabled = await client.setKillSwitch(
      enabled: true,
      reason: '移动端手动启用 kill switch。',
      updatedBy: 'Dubhe Companion',
    );

    expect(initial.enabled, isFalse);
    expect(enabled.enabled, isTrue);
    expect(enabled.reasonZh, '移动端手动启用 kill switch。');
    expect(callCount, 2);
  });

  test('audit logs endpoint parses recent risk audit records', () async {
    final client = CoreClient(
      baseUrl: 'http://127.0.0.1:8019',
      accessToken: 'dubhe_dev_token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/audit/logs');
        expect(request.url.queryParameters['limit'], '8');
        expect(request.headers['authorization'], 'Bearer dubhe_dev_token');
        return http.Response(
          '''
          [
            {
              "id": "audit_1",
              "actor_user_id": "user_1",
              "actor_device_id": "device_1",
              "actor_role": "risk_manager",
              "action": "risk.kill_switch_updated",
              "target_type": "kill_switch",
              "target_id": "global",
              "summary_zh": "Kill switch 状态已更新。",
              "metadata": {"enabled": true},
              "created_at": "2026-07-05T00:01:00Z"
            }
          ]
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final logs = await client.fetchAuditLogs();

    expect(logs.single.action, 'risk.kill_switch_updated');
    expect(logs.single.actorRole, 'risk_manager');
    expect(logs.single.summaryZh, 'Kill switch 状态已更新。');
  });
}
