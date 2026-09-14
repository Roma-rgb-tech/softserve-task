import asyncio
import os

import pytest

from ui_service.main import SESSION_TTL_SECONDS
from ui_service.redis_session_store import RedisSessionStore
from ui_service.sessions import SessionPreferences

TEST_REDIS_URL = os.getenv("TEST_REDIS_URL")

pytestmark = pytest.mark.skipif(
    not TEST_REDIS_URL,
    reason="TEST_REDIS_URL must point to a Redis the tests may write to",
)


def store() -> RedisSessionStore:
    assert TEST_REDIS_URL
    return RedisSessionStore(TEST_REDIS_URL, SESSION_TTL_SECONDS)


def test_an_unknown_session_starts_from_the_defaults() -> None:
    preferences = asyncio.run(store().get("a" * 43))
    assert preferences == SessionPreferences()


def test_preferences_survive_a_round_trip() -> None:
    session_id = "b" * 43
    saved = SessionPreferences(range="7", metric="change", smooth=False)
    asyncio.run(store().update(session_id, saved))
    assert asyncio.run(store().get(session_id)) == saved


def test_the_session_id_is_never_stored() -> None:
    session_id = "c" * 43
    assert session_id not in RedisSessionStore._key(session_id)


def test_a_corrupt_value_falls_back_to_the_defaults() -> None:
    session_id = "d" * 43
    subject = store()

    async def corrupt() -> None:
        await subject._connect().set(subject._key(session_id), "not json")

    asyncio.run(corrupt())
    assert asyncio.run(subject.get(session_id)) == SessionPreferences()
