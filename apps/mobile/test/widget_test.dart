import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dubhe_companion/src/app.dart';
import 'package:dubhe_companion/src/core_client.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows Chinese login screen', (tester) async {
    await tester.pumpWidget(const DubheCompanionApp());

    expect(find.text('创建账号'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('Core 地址'), findsOneWidget);
  });

  testWidgets('restores saved Core URL on login screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      coreUrlPreferenceKey: 'http://10.0.2.2:8000',
    });

    await tester.pumpWidget(const DubheCompanionApp());
    await tester.pump();

    expect(find.text('http://10.0.2.2:8000'), findsOneWidget);
  });

  test('paper trade fallback accepts synced strategy drafts', () {
    final draft = StrategyDraft(
      id: 'draft_synced',
      strategyVersionId: 'strategy_synced',
      name: '同步策略',
      spec: StrategySpec(
        strategyName: '同步策略',
        marketScope: const ['GLOBAL'],
        assetUniverse: const ['0700.HK'],
        entryRules: const ['同步策略信号'],
        exitRules: const ['风险退出'],
        riskLimits: const {'max_order_notional': 10000},
        timeframe: '1d',
        rebalanceRule: 'daily',
        dataDependencies: const ['news'],
        brokerPermissions: const ['paper'],
      ),
      explanationZh: '同步来的策略草稿。',
      generatedCode: 'class Synced {}',
      sourceAnalysisId: 'analysis_synced',
      createdAt: '2026-07-05T00:00:00Z',
    );

    expect(canSubmitPaperTrade(analysis: null, strategyDraft: draft), isTrue);
    expect(
      paperTradeSourceRef(analysis: null, strategyDraft: draft, event: null),
      'analysis_synced',
    );
    expect(paperTradeSymbol(strategyDraft: draft, event: null), '0700.HK');
    expect(
      paperTradeMarket(strategyDraft: draft, event: null, symbol: '0700.HK'),
      'HK',
    );

    final olderBacktest = BacktestResult(
      id: 'backtest_old',
      strategyVersionId: 'strategy_other',
      replayScenario: 'golden_news_sentiment_v1',
      symbol: 'NVDA',
      market: 'US',
      initialCash: 100000,
      finalEquity: 103000,
      totalReturn: 0.03,
      benchmarkReturn: 0.01,
      maxDrawdown: 0.02,
      winRate: 0.51,
      tradeCount: 1,
      riskNotesZh: const ['旧策略回测'],
    );
    final matchingBacktest = BacktestResult(
      id: 'backtest_match',
      strategyVersionId: 'strategy_synced',
      replayScenario: 'golden_news_sentiment_v1',
      symbol: '0700.HK',
      market: 'HK',
      initialCash: 100000,
      finalEquity: 118000,
      totalReturn: 0.18,
      benchmarkReturn: 0.05,
      maxDrawdown: 0.04,
      winRate: 0.62,
      tradeCount: 2,
      riskNotesZh: const ['匹配同步策略'],
    );

    expect(
      latestSyncedBacktest(
        strategyDraft: draft,
        backtestResults: [olderBacktest, matchingBacktest],
      )?.id,
      'backtest_match',
    );
    expect(
      latestSyncedBacktest(
        strategyDraft: draft,
        backtestResults: [olderBacktest],
      ),
      isNull,
    );
  });
}
