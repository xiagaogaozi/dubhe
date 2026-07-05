# Broker Adapters

Dubhe keeps live trading disabled by default. Broker adapters are staged in this order:

1. `simulated_paper`: deterministic local fills for demos, tests, and user training.
2. `alpaca_paper`: optional Alpaca paper trading sandbox for US stock paper-order UAT.
3. Future production adapters: IBKR, Alpaca live, Futu, or other regulated brokers after legal, risk, audit, and release approval.

## Current Runtime

Default behavior:

```text
DUBHE_PAPER_BROKER=simulated_paper
```

When no broker variables are configured, `/v1/simulation/paper-orders` uses the local simulated broker. It never sends a real order.

Optional Alpaca paper sandbox:

```text
DUBHE_PAPER_BROKER=alpaca
ALPACA_PAPER_API_KEY_ID=...
ALPACA_PAPER_SECRET_KEY=...
ALPACA_PAPER_BASE_URL=https://paper-api.alpaca.markets
```

After configuring those values, restart Core and run:

```powershell
.\scripts\test-external-services.ps1 -Live
```

The external service check calls Alpaca paper account status. Paper orders for US symbols are then submitted to `POST /v2/orders` on the configured Alpaca paper base URL.

## Safety Boundary

- `alpaca_paper` is still paper trading. It is not production live trading.
- `live_trading_enabled` remains `false`.
- Orders still pass Dubhe risk checks before reaching the broker adapter.
- The adapter stores sanitized broker response metadata; it does not expose API keys.
- Production release still requires broker UAT: rejection, disconnect, duplicate order, cancellation, market-hours, and audit-retention tests.

## Unsupported Cases

The Alpaca paper adapter currently rejects non-US markets. A-share and Hong Kong trading still require separate licensed brokers and market-specific rules.
