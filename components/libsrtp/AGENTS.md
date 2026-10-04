# LuatOS libsrtp Integration

## Scope

Pinned third-party SRTP core and its LuatOS allocator/portability adapter.

## Where to Look

- `README.md`: authoritative version, checksum, source selection and build contract.
- `port/`: LuatOS-owned configuration, allocator and embedded byte-order shim.
- `include/srtp.h`: public upstream API; VoIP policy lives in `components/voip`.

## Conventions

Keep imported upstream changes limited to the recorded `port/luatos.patch`. Put platform
adaptation in `port/`. Preserve the upstream license and document version updates
in `README.md`.

## Recipes

For integration changes, follow `README.md`'s private-header and explicit-source
rules in both PC and EC718HM builds. Validate the enabled mbedTLS 2/3 configurations
and an encrypted VoIP session. Keep the upstream cipher/authentication self-test
vectors: `srtp_init()` requires them when registering its crypto implementations.
Use the PC build helper required by `../../bsp/pc/AGENTS.md`.

## Anti-Patterns

Do not globally expose the generic private header names. Do not glob extra crypto
backends or the upstream allocator into the build. Do not enable key-bearing
upstream debug output. The exact build contract is in `README.md`.

## Related Docs

- `README.md`
- `../../AGENTS.md`
- `../../bsp/pc/AGENTS.md`
