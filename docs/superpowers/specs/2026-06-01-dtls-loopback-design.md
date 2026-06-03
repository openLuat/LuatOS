# DTLS loopback utest design

## Summary

Add a new PC-only C-layer DTLS regression suite that matches the existing TCP/HTTP/HTTPS utest pattern:

- Lua-visible entrypoint: `socket.utest("dtls_loopback_psk")`
- Runner suite: `testcase\unit_testcase_tools\c_utest_dtls_basic\`
- Coverage path: `bsp\pc\pc_utest_coverage.ps1 -Suite c_utest_dtls_basic`

The DTLS test must be deterministic and local. It will use a tiny PC-only DTLS-PSK echo helper bound to `127.0.0.1` so the client side exercises the real `socket` public API without depending on any external network service.

## Context

The current repository already has:

- PC C-layer utests for external TCP/HTTP/HTTPS reachability
- a canonical PC coverage helper at `bsp\pc\pc_utest_coverage.ps1`
- DTLS-capable client transport in `socket` / `network_adapter` through UDP + TLS mode

The current repository does **not** have:

- a DTLS utest suite
- a DTLS testcase runner under `testcase\unit_testcase_tools\`
- a reusable DTLS loopback peer for the PC simulator

The current generic network stack initializes TLS as client mode only, so this change must not try to turn the generic product network layer into a general DTLS server implementation.

## Goals

1. Add a DTLS suite that is a first-class peer to the current TCP/HTTP/HTTPS PC utests.
2. Keep the client path on real product APIs (`socket.create`, `socket.config`, `socket.connect`, `socket.tx`, `socket.read`).
3. Make the DTLS test deterministic under both plain runner and OpenCppCoverage.
4. Keep all DTLS server behavior scoped to the PC test environment.

## Non-goals

1. No external DTLS dependency or public DTLS endpoint.
2. No generic server-side DTLS feature for the production network adapter.
3. No broad refactor of the existing TCP/HTTP/HTTPS utest flow.

## Chosen approach

Use a split design:

- `components\utest\socket\luat_socket_utest.c` owns the client-side utest case and Lua bridge.
- `bsp\pc` owns a tiny DTLS-PSK echo helper that exists only to serve this PC regression.
- `testcase\unit_testcase_tools\c_utest_dtls_basic\` mirrors the existing C-layer suite structure.

This keeps the product-side path realistic while keeping the server fixture isolated and easy to reason about.

## Architecture

### 1. Socket utest entrypoint

Add a new case to `socket.utest(...)`:

- case name: `dtls_loopback_psk`
- return contract: `true` on full success, `false` on any failure
- execution model: same yieldable `lua_pcallk` bridge already used for current socket/http utests

### 2. PC-only DTLS echo helper

Add a small helper under `bsp\pc\src\` plus a matching header in `bsp\pc\include\`.

The helper must:

- bind to `127.0.0.1`
- allocate an ephemeral UDP port
- configure mbedTLS in `MBEDTLS_SSL_IS_SERVER` + `MBEDTLS_SSL_TRANSPORT_DATAGRAM`
- use fixed test PSK and PSK identity
- accept one client session
- echo one payload back exactly
- shut down cleanly after success or failure

The helper is a test fixture, not a public runtime feature.

### 3. DTLS testcase runner

Add:

- `testcase\unit_testcase_tools\c_utest_dtls_basic\metas.json`
- `testcase\unit_testcase_tools\c_utest_dtls_basic\scripts\main.lua`
- `testcase\unit_testcase_tools\c_utest_dtls_basic\scripts\c_utest_dtls_test.lua`

The runner should assert:

```lua
assert(socket.utest("dtls_loopback_psk") == true)
```

and keep the existing PC runner behavior, including explicit termination expectations already used by PC suites.

## Data flow

1. `socket.utest("dtls_loopback_psk")` starts the PC DTLS helper.
2. The helper returns its selected loopback port and a ready state.
3. The utest creates a normal `socket` client and configures:
   - UDP mode
   - TLS enabled
   - PSK + PSK identity
4. The client connects to `127.0.0.1:<helper_port>`.
5. The client generates a per-run unique payload token and sends it over DTLS.
6. The helper echoes the payload back byte-for-byte.
7. The client reads the response and asserts exact equality.
8. Both sides shut down and release resources.

## Payload rule

The DTLS payload must not be a fixed constant. Each run must generate a unique token, for example:

- timestamp from `os.date()`
- attempt or nonce suffix

Example shape:

```text
dtls-utest:20260601-101530:42
```

Success means the exact generated token for this run is echoed back unchanged. This prevents false confidence from accidental canned responses or stale buffered data.

## Error handling

The DTLS loopback suite should be strict and deterministic. Unlike the external TCP/HTTP/HTTPS suites, it should not include best-effort retry logic for transient network noise.

Recommended failure buckets:

- `helper_start_failed`
- `helper_bind_failed`
- `dtls_connect_timeout`
- `dtls_tx_timeout`
- `dtls_echo_mismatch`
- `helper_stop_failed`

Failures should surface the stage name in logs so plain and coverage failures are actionable.

## Verification plan

The final implementation must pass:

1. non-UTEST PC build
2. UTEST PC build
3. plain `c_utest_dtls_basic`
4. coverage `c_utest_dtls_basic`
5. a rerun of the existing `c_utest_tcp_basic`, `c_utest_http_basic`, and `c_utest_https_basic` suites to prove the new helper does not regress the current chain

## Documentation impact

Update the same discoverability surfaces already used for the PC utest workflow:

- `bsp\pc\AGENTS.md`
- `components\utest\AGENTS.md`
- `testcase\README.md`
- `bsp\pc\docs\web_console_runbook.md`

Only add DTLS-specific usage and verification notes that are needed for this new suite.

## File plan

- `components\utest\socket\luat_socket_utest.c`
- `bsp\pc\src\` new DTLS helper source
- `bsp\pc\include\` new DTLS helper header
- `testcase\unit_testcase_tools\c_utest_dtls_basic\metas.json`
- `testcase\unit_testcase_tools\c_utest_dtls_basic\scripts\main.lua`
- `testcase\unit_testcase_tools\c_utest_dtls_basic\scripts\c_utest_dtls_test.lua`
- docs listed above, only if implementation changes require updated instructions

## Why this design

This design gives the DTLS suite the same product-facing surface as the current socket/http utests while avoiding the flakiness and dependency risk of any external DTLS service. It also keeps server-only DTLS logic out of the generic production network adapter, which matches the current codebase boundary and keeps the change easier to test and maintain.
