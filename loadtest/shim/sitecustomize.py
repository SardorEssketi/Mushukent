"""Load-test shim, loaded automatically by Python via PYTHONPATH=/loadtest-shim.

The backend runs unmodified in APP_ENV=production. Only the outbound edges are redirected:

* Cloudflare R2: the S3 endpoint is derived from the account id; point it at the mock server.
* FCM: firebase_admin needs a real service account; replace the sender with a stub that sleeps
  for a realistic send latency and reports success.

PostHog needs no patch: POSTHOG_HOST already points at the mock server.
Nothing here runs unless LOADTEST_SHIM=1, so the file is inert anywhere else.
"""

import os

if os.getenv("LOADTEST_SHIM") == "1":
    import time

    _mock = os.getenv("LOADTEST_MOCK_URL", "http://mocks:9000")

    from app.infrastructure.storage import r2 as _r2

    _r2.R2StorageConfig.endpoint_url = property(lambda self: _mock)

    _fcm_latency = float(os.getenv("LOADTEST_FCM_LATENCY_MS", "120")) / 1000.0

    from app.features.notifications.infrastructure import fcm as _fcm

    def _init(self, credentials_file, project_id):  # noqa: ARG001 - signature parity
        self.sent = 0

    def _send(self, token, title, body, data):  # noqa: ARG001
        time.sleep(_fcm_latency)
        self.sent += 1
        return _fcm.PushResult(success=True)

    _fcm.FcmSender.__init__ = _init
    _fcm.FcmSender.send = _send

    # Observation only: connection-pool pressure (checked-out connections, overflow and the
    # time a request thread waits for a connection), appended every 2 s as JSON lines.
    _pool_out = os.getenv("LOADTEST_POOL_LOG")
    if _pool_out:
        import json
        import threading

        from sqlalchemy.pool import QueuePool

        _waits: list[float] = []
        _timeouts = [0]
        _pools: list = []
        _orig_do_get = QueuePool._do_get

        def _timed_do_get(self):
            if self not in _pools:
                _pools.append(self)
            started = time.perf_counter()
            try:
                return _orig_do_get(self)
            except Exception:
                _timeouts[0] += 1
                raise
            finally:
                _waits.append(time.perf_counter() - started)

        QueuePool._do_get = _timed_do_get

        def _reporter():
            while True:
                time.sleep(2)
                waits, _waits[:] = sorted(_waits), []
                pool = _pools[0] if _pools else None
                row = {
                    "t": time.time(),
                    "checkouts": len(waits),
                    "wait_p50_ms": round(waits[len(waits) // 2] * 1000, 2) if waits else 0,
                    "wait_p95_ms": round(waits[int(len(waits) * 0.95)] * 1000, 2) if waits else 0,
                    "wait_max_ms": round(waits[-1] * 1000, 2) if waits else 0,
                    "checked_out": pool.checkedout() if pool else 0,
                    "overflow": pool.overflow() if pool else 0,
                    "pool_timeouts_total": _timeouts[0],
                    "threads": threading.active_count(),
                }
                try:
                    with open(_pool_out, "a", encoding="utf-8") as handle:
                        handle.write(json.dumps(row) + "\n")
                except OSError:
                    pass

        threading.Thread(target=_reporter, name="loadtest-pool-reporter", daemon=True).start()

    # Observation only (task 5a): where a request's server time goes. One JSON line per request
    # with total server time, DB time (cursor execute), pool wait, thread-pool hand-off wait, sync
    # run time and the CPU run-queue wait of the worker thread (/proc schedstat run_delay, which
    # includes quota throttling on the emulated core), plus a 1 s sampler for the event loop
    # (loop lag, loop thread run-queue wait). Enabled only with LOADTEST_TRACE=<file>.
    _trace_out = os.getenv("LOADTEST_TRACE")
    if _trace_out:
        import asyncio
        import contextvars
        import json
        import re
        import threading

        import anyio.to_thread
        from sqlalchemy import event
        from sqlalchemy.engine import Engine
        from sqlalchemy.pool import QueuePool
        from fastapi import FastAPI

        _pc = time.perf_counter
        _cur: contextvars.ContextVar = contextvars.ContextVar("loadtest_trace", default=None)
        _rows: list = []
        _ids = re.compile(r"/(?:\d+|[0-9a-f]{8}-[0-9a-f-]{27,})(?=/|$)")
        _loop = {"tid": None, "lags": []}

        def _run_delay(path="/proc/thread-self/schedstat"):
            try:
                with open(path) as handle:
                    return int(handle.read().split()[1])
            except (OSError, IndexError, ValueError):
                return 0

        _orig_get = QueuePool._do_get

        def _traced_get(self):
            started = _pc()
            try:
                return _orig_get(self)
            finally:
                rec = _cur.get()
                if rec is not None:
                    rec["pool_ms"] += (_pc() - started) * 1000

        QueuePool._do_get = _traced_get

        @event.listens_for(Engine, "before_cursor_execute")
        def _before(conn, cursor, statement, parameters, context, executemany):  # noqa: ARG001
            conn.info["loadtest_t0"] = _pc()

        @event.listens_for(Engine, "after_cursor_execute")
        def _after(conn, cursor, statement, parameters, context, executemany):  # noqa: ARG001
            rec = _cur.get()
            started = conn.info.pop("loadtest_t0", None)
            if rec is not None and started is not None:
                rec["db_ms"] += (_pc() - started) * 1000
                rec["db_n"] += 1

        _orig_run_sync = anyio.to_thread.run_sync

        async def _traced_run_sync(func, *args, **kwargs):
            rec = _cur.get()
            if rec is None:
                return await _orig_run_sync(func, *args, **kwargs)
            submitted = _pc()

            def _call(*inner):
                started = _pc()
                rd0 = _run_delay()
                rec["tp_wait_ms"] += (started - submitted) * 1000
                rec["tp_n"] += 1
                try:
                    return func(*inner)
                finally:
                    rec["tp_run_ms"] += (_pc() - started) * 1000
                    rec["tp_rq_ms"] += (_run_delay() - rd0) / 1e6

            return await _orig_run_sync(_call, *args, **kwargs)

        anyio.to_thread.run_sync = _traced_run_sync

        async def _lag_probe():
            while True:
                started = _pc()
                await asyncio.sleep(0.05)
                _loop["lags"].append((_pc() - started - 0.05) * 1000)

        def _sampler():
            path = None
            while True:
                time.sleep(1)
                if path is None and _loop["tid"] is not None:
                    path = f"/proc/self/task/{_loop['tid']}/schedstat"
                lags, _loop["lags"] = sorted(_loop["lags"]), []
                rows, _rows[:] = list(_rows), []
                sample = {
                    "kind": "loop",
                    "t": time.time(),
                    "loop_rq_ns": _run_delay(path) if path else 0,
                    "lag_p50_ms": round(lags[len(lags) // 2], 2) if lags else None,
                    "lag_p95_ms": round(lags[int(len(lags) * 0.95)], 2) if lags else None,
                    "lag_max_ms": round(lags[-1], 2) if lags else None,
                    "threads": threading.active_count(),
                }
                try:
                    with open(_trace_out, "a", encoding="utf-8") as handle:
                        for row in rows:
                            handle.write(json.dumps(row) + "\n")
                        handle.write(json.dumps(sample) + "\n")
                except OSError:
                    pass

        def _start_observers():
            _loop["tid"] = threading.get_native_id()
            asyncio.get_running_loop().create_task(_lag_probe())
            threading.Thread(target=_sampler, name="loadtest-trace", daemon=True).start()

        _orig_build = FastAPI.build_middleware_stack  # FastAPI overrides Starlette's

        def _traced_build(self):
            inner = _orig_build(self)
            started_observers = [False]

            async def traced(scope, receive, send):
                if scope["type"] != "http":
                    return await inner(scope, receive, send)
                if not started_observers[0]:
                    started_observers[0] = True
                    _start_observers()
                rec = {
                    "kind": "req", "t": time.time(), "m": scope["method"],
                    "p": _ids.sub("/{id}", scope["path"]), "s": 0, "ms": 0.0,
                    "db_ms": 0.0, "db_n": 0, "pool_ms": 0.0, "tp_wait_ms": 0.0, "tp_n": 0,
                    "tp_run_ms": 0.0, "tp_rq_ms": 0.0,
                }
                token = _cur.set(rec)
                began = _pc()

                async def traced_send(message):
                    if message["type"] == "http.response.start":
                        rec["s"] = message["status"]
                    await send(message)

                try:
                    await inner(scope, receive, traced_send)
                finally:
                    rec["ms"] = (_pc() - began) * 1000
                    _cur.reset(token)
                    for key in ("ms", "db_ms", "pool_ms", "tp_wait_ms", "tp_run_ms", "tp_rq_ms"):
                        rec[key] = round(rec[key], 2)
                    _rows.append(rec)

            return traced

        FastAPI.build_middleware_stack = _traced_build
