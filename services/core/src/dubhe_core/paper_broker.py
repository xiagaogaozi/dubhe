from __future__ import annotations

from .models import BrokerFill, BrokerOrder, BrokerOrderStatus, OrderIntent


class SimulatedPaperBroker:
    adapter_name = "simulated_paper"

    def submit_order(self, intent: OrderIntent, paper_order_id: str) -> BrokerOrder:
        fill_price = intent.limit_price or intent.estimated_price

        broker_order = BrokerOrder(
            paper_order_id=paper_order_id,
            order_intent_id=intent.id,
            adapter=self.adapter_name,
            broker_account_id=f"paper:{intent.account_id}",
            market=intent.market,
            symbol=intent.symbol,
            side=intent.side,
            quantity=intent.quantity,
            currency=intent.currency,
            status=BrokerOrderStatus.ACCEPTED,
            message_zh="模拟券商已接受纸面订单。",
            raw_response={
                "adapter": self.adapter_name,
                "mode": "deterministic_fill",
                "real_broker": False,
            },
        )
        fill = BrokerFill(
            broker_order_id=broker_order.id,
            symbol=intent.symbol,
            side=intent.side,
            quantity=intent.quantity,
            price=fill_price,
            notional=round(intent.quantity * fill_price, 4),
            commission=0,
        )
        return broker_order.model_copy(
            update={
                "status": BrokerOrderStatus.FILLED,
                "filled_quantity": intent.quantity,
                "avg_fill_price": fill_price,
                "updated_at": fill.filled_at,
                "fills": [fill],
                "message_zh": "模拟券商已成交纸面订单。",
                "raw_response": {
                    "adapter": self.adapter_name,
                    "mode": "deterministic_fill",
                    "real_broker": False,
                    "fill_id": fill.id,
                },
            },
        )


simulated_paper_broker = SimulatedPaperBroker()
