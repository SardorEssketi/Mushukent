# R2 public read failure — root cause (2026-10-18)

## Symptom
`backend/scripts/r2_disposable_smoke.py --execute`: upload PASS, exists PASS, public read `FAIL HTTPError`, cleanup PASS.

## Evidence (read-only probes, no uploads)
- `media.mushukistan.uz` resolves to Cloudflare (proxied); TLS is fine.
- Same missing key, two clients:
  - `User-Agent: Python-urllib/3.12` -> **403**, body `error code: 1010`, `Server: cloudflare`, `Cache-Control: private, no-store...`.
  - A normal UA -> **404** from R2 with `Cache-Control: no-store`, `cf-cache-status: BYPASS`.
- An existing public feed image (URL taken from the public `/api/v1/feed`): normal UA -> **200 image/jpeg**; `Python-urllib` UA -> **403**.

## Root cause
Cloudflare error 1010 is the Browser Integrity Check / browser-signature block. It rejects urllib's default
`Python-urllib/x` User-Agent. The custom domain, bucket mapping, URL construction (`R2ObjectStorage.public_url`)
and DNS are correct. This was a defect in the smoke script, not in storage or production configuration.
Browsers and the app are unaffected, so ordinary images are publicly accessible.

## Fix
- `public_read()` sends an explicit `MushukistanSmoke/1.0` User-Agent. No Cloudflare protection is changed.
- On HTTP errors it reports status, reason, and a safe header allowlist (server, content-type, cache-control,
  cf-cache-status, cf-ray), plus a WAF hint on 403. It never prints the URL, body or cookies.
- No retry was added: the failure is deterministic, not a visibility delay.
- Tests: `backend/tests/test_r2_smoke_script.py`.

## Remaining
Re-run the smoke test once (needs separate approval for another production upload) to see all four steps pass.
