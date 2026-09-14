from __future__ import annotations

import hashlib
import json

from pydantic import ValidationError
from redis.asyncio import Redis
from redis.exceptions import RedisError

from .sessions import SessionPreferences

KEY_PREFIX = "ui_sessions:"


class RedisSessionStore:
    backend = "redis"
    errors = (RedisError,)

    def __init__(self, redis_url: str, ttl_seconds: int) -> None:
        self.redis_url = redis_url
        self.ttl_seconds = ttl_seconds
        self._client: Redis | None = None

    def _connect(self) -> Redis:
        if self._client is None:
            self._client = Redis.from_url(
                self.redis_url,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5,
            )
        return self._client

    @staticmethod
    def _key(session_id: str) -> str:
        return KEY_PREFIX + hashlib.sha256(session_id.encode("utf-8")).hexdigest()

    async def is_ready(self) -> bool:
        return bool(await self._connect().ping())

    async def get(self, session_id: str) -> SessionPreferences:
        client = self._connect()
        key = self._key(session_id)
        stored = await client.get(key)

        if stored is None:
            return await self.update(session_id, SessionPreferences())

        try:
            preferences = SessionPreferences.model_validate(json.loads(stored))
        except (TypeError, ValueError, ValidationError):
            return await self.update(session_id, SessionPreferences())

        await client.expire(key, self.ttl_seconds)
        return preferences

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        await self._connect().set(
            self._key(session_id),
            preferences.model_dump_json(),
            ex=self.ttl_seconds,
        )
        return preferences
