"""Bounded investigation queue and incident deduplication helpers."""
from __future__ import annotations

import asyncio
import logging
import sqlite3
from pathlib import Path
from typing import Any, Awaitable, Callable

logger = logging.getLogger("sre_agent.queue")


class IncidentDeduper:
    """Persist incident claim state so requests can be deduped across restarts."""

    def __init__(self, db_path: str | Path) -> None:
        self._db_path = Path(db_path)
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _initialize(self) -> None:
        with sqlite3.connect(self._db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS incident_claims (
                    incident_id TEXT PRIMARY KEY,
                    state TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def claim(self, incident_id: str) -> bool:
        with sqlite3.connect(self._db_path) as conn:
            row = conn.execute(
                "SELECT state FROM incident_claims WHERE incident_id = ?",
                (incident_id,),
            ).fetchone()
            if row is not None:
                return False
            conn.execute(
                "INSERT INTO incident_claims (incident_id, state) VALUES (?, ?)",
                (incident_id, "active"),
            )
            conn.commit()
            return True

    def mark_complete(self, incident_id: str) -> None:
        with sqlite3.connect(self._db_path) as conn:
            conn.execute(
                "INSERT INTO incident_claims (incident_id, state) VALUES (?, ?) ON CONFLICT(incident_id) DO UPDATE SET state = excluded.state",
                (incident_id, "complete"),
            )
            conn.commit()

    def release(self, incident_id: str) -> None:
        with sqlite3.connect(self._db_path) as conn:
            conn.execute("DELETE FROM incident_claims WHERE incident_id = ?", (incident_id,))
            conn.commit()


class InvestigationDispatcher:
    """A bounded queue with a fixed number of workers and per-item timeout."""

    def __init__(
        self,
        *,
        max_queue_size: int,
        max_concurrency: int,
        timeout_seconds: float,
        handler: Callable[[Any], Awaitable[None]] | None = None,
    ) -> None:
        self._queue: asyncio.Queue[Any] = asyncio.Queue(maxsize=max_queue_size)
        self._max_queue_size = max_queue_size
        self._max_concurrency = max_concurrency
        self._timeout_seconds = timeout_seconds
        self._handler = handler
        self._started = False
        self._stopped = False
        self._workers: list[asyncio.Task[None]] = []
        # Lightweight in-process metrics for observability (exposed via the webhook /healthz).
        self._processed = 0
        self._failed = 0
        self._timed_out = 0

    async def start(self) -> None:
        if self._started:
            return
        self._started = True
        self._stopped = False
        for _ in range(self._max_concurrency):
            task = asyncio.create_task(self._worker())
            self._workers.append(task)

    async def stop(self) -> None:
        if not self._started:
            return
        self._stopped = True
        for worker in self._workers:
            worker.cancel()
        if self._workers:
            await asyncio.gather(*self._workers, return_exceptions=True)
        self._workers.clear()

    async def enqueue(self, item: Any) -> bool:
        await self.start()
        if self._stopped or self._queue.full():
            return False
        await self._queue.put(item)
        return True

    async def join(self) -> None:
        """Block until every queued item has been processed (used by tests)."""
        await self._queue.join()

    def stats(self) -> dict[str, int]:
        """Snapshot of queue depth and lifetime counters for health/metrics."""
        return {
            "queue_depth": self._queue.qsize(),
            "queue_capacity": self._max_queue_size,
            "workers": len(self._workers),
            "processed": self._processed,
            "failed": self._failed,
            "timed_out": self._timed_out,
        }

    async def _worker(self) -> None:
        while not self._stopped:
            try:
                item = await asyncio.wait_for(self._queue.get(), timeout=0.25)
            except asyncio.TimeoutError:
                continue
            try:
                if self._handler is None:
                    await asyncio.sleep(0)
                else:
                    await asyncio.wait_for(self._handler(item), timeout=self._timeout_seconds)
                self._processed += 1
            except asyncio.TimeoutError:
                self._timed_out += 1
                logger.warning("Investigation timed out after %.2fs", self._timeout_seconds)
            except Exception:  # noqa: BLE001
                self._failed += 1
                logger.exception("Investigation worker failed")
            finally:
                self._queue.task_done()
