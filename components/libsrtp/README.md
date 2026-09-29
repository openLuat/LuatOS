# libsrtp for LuatOS

Pinned upstream: Cisco libsrtp **v2.8.1**.

- Release: https://github.com/cisco/libsrtp/releases/tag/v2.8.1
- Source: https://codeload.github.com/cisco/libsrtp/tar.gz/refs/tags/v2.8.1
- Archive SHA-256: `ef5569220749529d778013aae1178391d972570a2b4f7288dda22effa875b07c`
- License: BSD-3-Clause, see `LICENSE`. Upstream sources retain their copyright notices.

The vendored files contain upstream core sources, headers and startup
self-test vectors for the mbedTLS AES-ICM and HMAC-SHA1 backends. The
`cipher_test_cases` and `auth_test_cases` files are required by `srtp_init()`
when registering those implementations; they are not application test targets. No GCM,
OpenSSL/NSS backend, command-line tools, or architecture-specific binaries are
built. `port/luatos.patch` records the narrow changes from the pinned archive:
library-local includes use relative paths to avoid SDK header-name collisions,
diagnostics cast 32-bit values to match `%x` on ARM, and the three internal
cipher wrappers use the backend callback's `unsigned int` length type consistently
(`uint32_t` is `unsigned long` in this ARM libc). Cryptographic
algorithms are unchanged. The upstream AES backend also provides 192/256-bit primitives; the LuatOS
VoIP API negotiates only `AES_CM_128_HMAC_SHA1_80`.

`port/luat_srtp_alloc.c` replaces upstream `crypto/kernel/alloc.c` and uses
`luat_heap_calloc` / `luat_heap_free`. Upstream zeroing on context destruction is
preserved. Runtime key generation belongs to the VoIP security layer.

Build with per-file `forceincludes = {"luat_srtp_config.h"}` and private include directories `port`,
`crypto/include`, and `include`. Embedded builds additionally use `port/lwip`
for the narrow, self-contained `netinet/in.h` byte-order shim. It deliberately
does not include the vendor LwIP arch/debug configuration. Do not add `port` or
`crypto/include` globally: their generic header names can shadow other libraries.
Only `include` is public. The unique forced header defines `HAVE_CONFIG_H` (also
required by upstream byte-order helpers) and includes our config by a quoted path.
Do not restore generic `<config.h>` or cross-directory bare header includes:
xmake appends private include directories after global paths.
It also supplies the missing AES-192 table forward declaration required by the
upstream mbedTLS backend when GCM is disabled; this does not enable that suite.
Do not enable `ENABLE_DEBUG_LOGGING`: upstream debug
messages can include key material.

`LUAT_USE_SRTP` enables the SRTP dependency. `LUAT_USE_DTLS_SRTP` additionally
enables DTLS `use_srtp`, server role, key exporter, and local X.509 generation in
mbedTLS. PC enables both by default; `LUAT_USE_SRTP=n` disables both and
`LUAT_USE_DTLS_SRTP=n` keeps SDES only. EC718HM VoIP firmware enables both through
its final feature configuration; firmware variants without VoIP exclude them.

The explicit source list lives in the PC and EC718HM xmake integration. Do not
glob an expanded upstream checkout: compiling another allocator or crypto backend
would create duplicate symbols or change the supported crypto configuration.
