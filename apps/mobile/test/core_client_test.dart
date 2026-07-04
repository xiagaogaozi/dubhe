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
}
