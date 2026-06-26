# ndk（RV32I 运行时）

`ndk` 用于在 LuatOS 内运行 MiniRV32IMA 镜像，并通过交换区与 Lua 侧交互。

## 文档索引

| 文档 | 用途 |
|---|---|
| [`docs/quickstart.md`](./docs/quickstart.md) | 快速验证 + 完整验证流程 + 预期结果 / 失败迹象 |
| [`docs/build.md`](./docs/build.md) | 前置依赖 + Guest 镜像重建 + PC 宿主侧构建 + Rust 工具链 |
| [`docs/troubleshooting.md`](./docs/troubleshooting.md) | 常见问题 Q1–Q8（含 512K RAM、不限步数、Rust target 等新增） |
| [`docs/lua-api.md`](./docs/lua-api.md) | Lua `ndk.*` API 完整参考 + 最小使用示例 |
| [`docs/csr-abis.md`](./docs/csr-abis.md) | CSR / MMIO / Host ABI v1 / GPIO v2 / UART v1 / **Crypto v1** |
| [`docs/examples.md`](./docs/examples.md) | 4 个 C guest 示例 + 自写示例的最小模板 |
| [`docs/api-helper.md`](./docs/api-helper.md) | `luat_ndk_helper.h` 的 API 文档（guest "标准库"） |
| [`docs/changelog.md`](./docs/changelog.md) | NDK 变更日志 |
| [`DESIGN.md`](./DESIGN.md) | 15 节设计文档：架构、ABI、执行模型、内存布局、非目标、验收标准 |
| [`AGENTS.md`](./AGENTS.md) | 开发备忘：合约、坑点、验证技巧（开发用） |

## 快速回顾

```lua
local ctx, err = ndk.rv32i("/luadb/baremetal.bin", 32 * 1024, 1024)
assert(ctx, err)
ndk.setData(ctx, "ping")
local ok, ret = ndk.exec(ctx, {steps = 0, elapsed = 100})   -- steps=0 = 不限步数
assert(ok, ret)
log.info("ndk", "ret", ret, "data", ndk.getData(ctx, 16, 0))
ndk.stop(ctx, 1000); ndk.reset(ctx)
```

更多上下文：参见 [`docs/quickstart.md`](./docs/quickstart.md) 与 [`docs/lua-api.md`](./docs/lua-api.md)。

## Build status

- PC 模拟器：在 `bsp/pc/build_windows_32bit_msvc.bat` 增量 10–30 秒
- `testcase/ndk/ndk_basic` 回归基线：**42 passed, 0 failed**
- `testcase/ndk/ndk_hostabi_basic` 回归基线：**39 passed, 0 failed**
- 512 KiB RAM 烟雾测试：`bsp/pc/test/113.ndk_simple`

## 相关

- Runtime 实现：`src/luat_ndk.c`
- CSR 处理器：`src/luat_ndk_host.c`
- Host API 头：`include/luat_ndk.h`
- Guest helper 头：`guest/include/luat_ndk_helper.h`
- mini-rv32ima 上游：https://github.com/cnlohr/mini-rv32ima
- 设计参考：`docs/superpowers/specs/2026-05-20-gpio-v2-design.md`（v2 ABI）、`2026-05-20-uart-v1-design.md`（v1 UART）

## License

NDK runtime 基于 mini-rv32ima（MIT-x11/NewBSD），与 LuatOS MIT License 兼容。
