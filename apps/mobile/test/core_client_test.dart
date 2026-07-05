import 'dart:convert';

import 'package:dubhe_companion/src/core_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
            "strategy_drafts": [],
            "backtest_results": [],
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
    expect(snapshot.events.single.entityType, 'watchlist_item');
  });

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
            "trading": {
              "paper_broker_enabled": true,
              "live_trading_enabled": false,
              "message_zh": "纸面交易已启用；实盘交易保持关闭。"
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
    expect(status.missingConfigCount, 1);
    expect(status.enabledAdapterCount, 1);
    expect(status.configItems.first.key, 'FINNHUB_API_KEY');
    expect(status.newsAdapters.last.labelZh, '本地演示新闻源');
  });

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
