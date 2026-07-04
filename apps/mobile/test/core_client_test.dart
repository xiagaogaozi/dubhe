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
}
