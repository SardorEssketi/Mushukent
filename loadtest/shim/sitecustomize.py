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
