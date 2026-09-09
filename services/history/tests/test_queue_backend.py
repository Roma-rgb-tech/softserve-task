import pytest

from history_service import messaging
from history_service.config import Settings


def test_pgmq_backend_selects_the_postgres_consumer() -> None:
    consumer = messaging.create_consumer(Settings(queue_backend="pgmq"))

    assert isinstance(consumer, messaging.PGMQConsumer)


def test_amqp_backend_selects_the_broker_consumer() -> None:
    consumer = messaging.create_consumer(
        Settings(
            queue_backend="amqp",
            amqp_url="amqp://guest:guest@localhost:5672/oil_tracker",
        )
    )

    assert isinstance(consumer, messaging.AMQPConsumer)
    assert not consumer.is_ready


def test_unknown_backend_is_refused() -> None:
    with pytest.raises(ValueError):
        messaging.create_consumer(Settings(queue_backend="kafka"))
