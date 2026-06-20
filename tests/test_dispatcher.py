import asyncio

import pytest

from src.investigation_queue import IncidentDeduper, InvestigationDispatcher


@pytest.mark.asyncio
async def test_dispatcher_rejects_when_queue_is_full():
    dispatcher = InvestigationDispatcher(max_queue_size=1, max_concurrency=1, timeout_seconds=1)
    await dispatcher.start()

    try:
        assert await dispatcher.enqueue("job-1") is True
        assert await dispatcher.enqueue("job-2") is False
    finally:
        await dispatcher.stop()


@pytest.mark.asyncio
async def test_dispatcher_runs_handler_and_counts_processed():
    seen: list[str] = []

    async def handler(item):
        seen.append(item)

    dispatcher = InvestigationDispatcher(
        max_queue_size=8, max_concurrency=2, timeout_seconds=1, handler=handler,
    )
    try:
        assert await dispatcher.enqueue("a") is True
        await dispatcher.join()
    finally:
        await dispatcher.stop()

    assert seen == ["a"]
    assert dispatcher.stats()["processed"] == 1


@pytest.mark.asyncio
async def test_dispatcher_times_out_slow_handler():
    released: list[str] = []

    async def slow(item):
        try:
            await asyncio.sleep(5)
        finally:
            # finally runs on cancellation — mirrors how the webhook releases a dedupe claim.
            released.append(item)

    dispatcher = InvestigationDispatcher(
        max_queue_size=8, max_concurrency=1, timeout_seconds=0.05, handler=slow,
    )
    try:
        await dispatcher.enqueue("slow-job")
        await dispatcher.join()
    finally:
        await dispatcher.stop()

    assert released == ["slow-job"]              # cleanup ran under cancellation
    assert dispatcher.stats()["timed_out"] == 1


@pytest.mark.asyncio
async def test_dispatcher_counts_handler_failure():
    async def boom(item):
        raise RuntimeError("agent blew up")

    dispatcher = InvestigationDispatcher(
        max_queue_size=8, max_concurrency=1, timeout_seconds=1, handler=boom,
    )
    try:
        await dispatcher.enqueue("x")
        await dispatcher.join()  # a failing handler must not wedge the queue
    finally:
        await dispatcher.stop()

    assert dispatcher.stats()["failed"] == 1


def test_deduper_claims_once(tmp_path):
    store = IncidentDeduper(tmp_path / "dedupe.sqlite3")
    assert store.claim("incident-1") is True
    assert store.claim("incident-1") is False
    store.mark_complete("incident-1")
    assert store.claim("incident-1") is False  # completed incidents are not re-investigated


def test_deduper_release_allows_retry(tmp_path):
    """On a failed/timed-out investigation the claim is released so a redelivery can retry."""
    store = IncidentDeduper(tmp_path / "dedupe.sqlite3")
    assert store.claim("incident-2") is True
    store.release("incident-2")
    assert store.claim("incident-2") is True  # retryable after release
