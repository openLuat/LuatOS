# NDK Guest Examples

This folder provides customer-facing standalone guest projects that compile into `.bin` images for `ndk.rv32i`.

## Included Examples

- `hello_world` - minimal completion flow and exchange marker write.
- `exchange_buffer_demo` - fixed-layout request/response exchange buffer usage.
- `gpio_hostabi_demo` - guest-side GPIO host-ABI CSR command flow.
- `crypto_hash_demo` - guest C MD5/CRC32 hash demo.

## Customer Workflow (source -> build -> run)

1. Enter an example directory:
   - `components\ndk\guest\examples\<example>`
2. Build:
   - PowerShell: `.\build.ps1`
   - CMD: `build.bat`
3. Collect artifact:
   - `build\<example>.bin`
4. Copy `.bin` to your script storage (for example `/luadb/` on target).
5. Run from Lua with `ndk.rv32i`:

```lua
local image = "/luadb/hello_world.bin"
local ctx, err = ndk.rv32i(image, 32 * 1024, 1024)
assert(ctx, tostring(err))

local ok, ret_or_err, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
assert(ok == true, string.format("exec failed: %s mcause=%s mtval=%s", tostring(ret_or_err), tostring(mcause), tostring(mtval)))
```

## Build Entrypoints

- Per-example:
  - `components\ndk\guest\examples\<example>\build.ps1`
  - `components\ndk\guest\examples\<example>\build.bat`
- Shared helper:
  - `components\ndk\guest\examples\build_example.ps1`
  - `components\ndk\guest\examples\build_example.bat`

`build_example.ps1` auto-detects GNU RISC-V or LLVM toolchains and prints clear error messages when no usable toolchain is present.

## Note on Testcase Compatibility

These examples are intentionally standalone customer samples. Existing testcase consumption paths (`testcase\ndk\...`) remain unchanged and are not overwritten by these example build scripts.
