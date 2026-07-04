from __future__ import annotations

from .models import (
    BacktestPoint,
    BacktestRequest,
    BacktestResult,
    Market,
    StrategyDraft,
    StrategyDraftRequest,
    StrategySpec,
)
from .strategy import validate_strategy_spec


REPLAY_CLOSES: dict[str, list[tuple[str, float]]] = {
    "NVDA": [
        ("2026-06-01", 100.0),
        ("2026-06-02", 103.0),
        ("2026-06-03", 101.0),
        ("2026-06-04", 107.0),
        ("2026-06-05", 111.0),
        ("2026-06-08", 108.0),
        ("2026-06-09", 116.0),
        ("2026-06-10", 119.0),
    ],
    "AAPL": [
        ("2026-06-01", 100.0),
        ("2026-06-02", 100.8),
        ("2026-06-03", 99.6),
        ("2026-06-04", 101.2),
        ("2026-06-05", 102.4),
        ("2026-06-08", 101.5),
        ("2026-06-09", 103.0),
        ("2026-06-10", 104.0),
    ],
    "MSFT": [
        ("2026-06-01", 100.0),
        ("2026-06-02", 101.5),
        ("2026-06-03", 102.0),
        ("2026-06-04", 103.6),
        ("2026-06-05", 102.8),
        ("2026-06-08", 105.0),
        ("2026-06-09", 106.4),
        ("2026-06-10", 107.2),
    ],
    "0700.HK": [
        ("2026-06-01", 100.0),
        ("2026-06-02", 99.4),
        ("2026-06-03", 101.1),
        ("2026-06-04", 100.7),
        ("2026-06-05", 102.2),
        ("2026-06-08", 101.8),
        ("2026-06-09", 103.6),
        ("2026-06-10", 104.1),
    ],
    "600519.SH": [
        ("2026-06-01", 100.0),
        ("2026-06-02", 100.4),
        ("2026-06-03", 99.8),
        ("2026-06-04", 100.2),
        ("2026-06-05", 101.0),
        ("2026-06-08", 100.6),
        ("2026-06-09", 101.4),
        ("2026-06-10", 101.7),
    ],
}


def draft_strategy_from_analysis(request: StrategyDraftRequest) -> StrategyDraft:
    analysis = request.analysis
    threshold = max(0.5, min(0.9, round(analysis.impact_score, 2)))
    symbol = request.symbol
    name = f"{symbol} 新闻情绪 replay 策略"
    spec = StrategySpec(
        strategy_name=name,
        market_scope=[request.market],
        asset_universe=[symbol],
        entry_rules=[
            f"新闻情绪为正面，且影响分不低于 {threshold:.2f}",
            "只使用带来源引用的新闻分析结果",
        ],
        exit_rules=[
            "持有 5 个交易日后退出",
            "回撤达到 6% 时退出",
            "出现负面高影响新闻时退出",
        ],
        risk_limits={
            "max_order_notional": request.max_order_notional,
            "max_drawdown_stop": 0.06,
        },
        timeframe="1d",
        rebalance_rule="event_driven",
        data_dependencies=["news", "market_bars", "filings"],
        broker_permissions=["paper"],
    )
    validation = validate_strategy_spec(spec)
    if not validation.valid:
        explanation = "策略草案未通过静态校验：" + "；".join(validation.reasons_zh)
    else:
        explanation = (
            f"当 {symbol} 出现有来源引用的正面高影响新闻时，策略进入纸面交易候选；"
            "先通过 replay 回测和风控审批，不直接进入实盘。"
        )

    generated_code = "\n".join(
        [
            "class DubheNewsSentimentStrategy(QCAlgorithm):",
            "    def Initialize(self):",
            f"        self.symbol = self.AddEquity(\"{symbol}\", Resolution.Daily).Symbol",
            "        self.max_drawdown_stop = 0.06",
            "",
            "    def OnNewsSignal(self, signal):",
            f"        if signal.sentiment == \"positive\" and signal.impact_score >= {threshold:.2f}:",
            "            self.SetHoldings(self.symbol, 0.1)",
            "",
            "    def OnData(self, data):",
            "        pass  # Production execution is delegated to Dubhe Risk Service.",
        ],
    )

    return StrategyDraft(
        name=name,
        spec=spec,
        explanation_zh=explanation,
        generated_code=generated_code,
        source_analysis_id=analysis.id,
    )


def run_replay_backtest(request: BacktestRequest) -> BacktestResult:
    strategy = request.strategy
    symbol = strategy.spec.asset_universe[0].upper()
    closes = REPLAY_CLOSES.get(symbol, REPLAY_CLOSES["NVDA"])
    analysis_is_positive = "正面" in strategy.explanation_zh or "positive" in strategy.generated_code
    allocation = 0.1 if analysis_is_positive else 0.0

    first_close = closes[0][1]
    cash = request.initial_cash * (1 - allocation)
    shares = (request.initial_cash * allocation) / first_close if allocation > 0 else 0.0
    benchmark_shares = request.initial_cash / first_close

    equity_curve: list[BacktestPoint] = []
    peak_equity = request.initial_cash
    max_drawdown = 0.0
    winning_days = 0
    previous_equity = request.initial_cash

    for date, close in closes:
        equity = round(cash + shares * close, 2)
        benchmark = round(benchmark_shares * close, 2)
        equity_curve.append(BacktestPoint(date=date, equity=equity, benchmark=benchmark))
        if equity > previous_equity:
            winning_days += 1
        previous_equity = equity
        peak_equity = max(peak_equity, equity)
        drawdown = 0 if peak_equity == 0 else (peak_equity - equity) / peak_equity
        max_drawdown = max(max_drawdown, drawdown)

    final_equity = equity_curve[-1].equity
    benchmark_final = equity_curve[-1].benchmark
    trade_count = 2 if allocation > 0 else 0
    day_count = max(len(closes) - 1, 1)
    win_rate = winning_days / day_count
    market = strategy.spec.market_scope[0] if strategy.spec.market_scope else Market.US

    return BacktestResult(
        strategy_version_id=strategy.strategy_version_id,
        replay_scenario=request.replay_scenario,
        symbol=symbol,
        market=market,
        initial_cash=request.initial_cash,
        final_equity=final_equity,
        total_return=round((final_equity - request.initial_cash) / request.initial_cash, 4),
        benchmark_return=round((benchmark_final - request.initial_cash) / request.initial_cash, 4),
        max_drawdown=round(max_drawdown, 4),
        win_rate=round(win_rate, 4),
        trade_count=trade_count,
        risk_notes_zh=[
            "这是 deterministic golden replay，用于兜底测试，不代表真实收益。",
            "真实生产回测必须接入 LEAN worker、正式历史行情和完整交易成本模型。",
            "实盘仍必须经过 Dubhe Risk Service 与人工审批。",
        ],
        equity_curve=equity_curve,
    )
