# NDK 常见问题

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## Q1: 找不到 RISC-V 工具链

**症状**：`build.bat` 报错 `No suitable RISC-V toolchain found`

**解决**：

1. **选择工具链**：
   - 推荐 xPack RISC-V GCC：https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
   - 下载 Windows x64 版本，解压并添加 `bin/` 到 PATH

2. **验证安装**：
   ```powershell
   $env:PATH += ";C:\path\to\xpack-riscv-none-elf-gcc-12.2.0-3\bin"
   riscv-none-elf-gcc --version
   ```

3. **替代方案**：使用 LLVM（如果已安装）
   - 确保 LLVM 编译时启用了 RISC-V target 且安装了 LLD 链接器
   - 测试：`clang --target=riscv32-unknown-elf --version` 和 `ld.lld --version`

## Q2: baremetal.bin 生成路径不对

**症状**：构建成功但测试找不到二进制

**原因**：`build.bat` 自动同步机制依赖相对路径

**解决**：
1. 确保在 `components/ndk/guest/fixtures/rv32f_regression/` 目录内运行 `build.bat`（或使用兼容入口 `testcase/ndk/ndk_basic/guest/build.bat`）
2. 手动验证同步：
   ```powershell
   ls ..\scripts\baremetal.bin
   ls ..\..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
   ```

## Q3: PC 模拟器构建失败（MSVC 错误）

**症状**：`build_windows_32bit_msvc.bat` 报链接错误或找不到头文件

**解决**：
1. 确保在 **VS Developer Command Prompt** 中运行（`cl.exe` 在 PATH 中）
2. 或在普通终端中通过 `cmd /c` 串联执行（确保 `vcvars32.bat` 设置的环境变量在同一进程里生效）：
   ```powershell
   cmd /c "\"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat\" && build_windows_32bit_msvc.bat"
   ```
3. 清理后重试：
   ```powershell
   xmake clean -a
   cmd /c build_windows_32bit_msvc.bat
   ```

## Q4: testcase 找不到 `/luadb/baremetal.bin`

**症状**：运行时报错 `can't open /luadb/baremetal.bin`

**根因**：LuatOS VFS 在 PC 模拟器下将脚本目录挂载为 `/luadb/`，但二进制不在该目录

**解决**：
1. 确保 `testcase/ndk/ndk_basic/scripts/baremetal.bin` 存在
2. 重新运行 guest 构建（会自动同步）：
   ```powershell
   cd components\ndk\guest\fixtures\rv32f_regression
   cmd /c build.bat
   ```

## Q5: 修改了 guest 代码但测试结果未变

**原因**：忘记重建或仅重建了 guest 未重建 PC

**完整流程**：
```powershell
# 1. 重建 guest
cd components\ndk\guest\fixtures\rv32f_regression
cmd /c build.bat

# 2. 不需要重建 PC（guest 是运行时加载的）

# 3. 直接测试
cd ..\..\..\..\..\bsp\pc
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

**注意**：guest 二进制是运行时动态加载，无需重新编译 PC 模拟器。

## Q6: 想让示例配 1 MB RAM 怎么配？

**症状**：guest 报 `image too large` 或 `no memory`

**原因**：NDK 的 guest RAM 受 `LUAT_NDK_MAX_RAM_SIZE` 上限约束。

**解决**：本 PR 之后硬上限是 **512 KiB**（`components/ndk/include/luat_ndk.h:10`），老文档中的 32 KiB 已经废除。在 Lua 侧用 `ndk.rv32i(path, 512*1024, 1024)` 即可拿到最大允许 RAM。要更小，常见值 32 KiB / 64 KiB / 128 KiB 都可。512 KiB 的 smoke 测试见 `bsp/pc/test/113.ndk_simple/main.lua`。

## Q7: `ndk.exec(ctx, {steps = 0})` 是不是无限循环？

**是，但不危险**。`steps = 0` 的新语义是"不限步数"——guest 会一直跑到：

- 写 SYSCON `0x5555`（正常退出）
- `ecall`（`mcause=11`，返回 `a0`）
- 任何 trap（非法指令 / load fault / ...）
- 调用 `ndk.stop(ctx, ...)` 打断

调用 `ndk.stop(ctx, 1000)` 可以在 1 秒内强行打断。所以"无限循环"guest 不会真的让固件死锁。设计动机：之前 `steps = 0` 隐含默认值 32768，对稍微长一点的循环不够用。

> **注意**：调试/测试长 guest 时建议主动传 `steps` 上限（如 1000000）以便在异常情况下及时 bail。

## Q8: Rust 工具链装哪个 target？

（Phase 3 早期规划时考虑过 Rust no-std 示例，因 build 工具链复杂度放弃。如未来重启，可以参考：）

```powershell
rustup target add riscv32imac-unknown-none-elf
rustup component add rust-src
cargo install cargo-binutils
```

`build.ps1` 会自动检测并安装 `rust-src` 与 `riscv32imac-unknown-none-elf`，但 `cargo install cargo-binutils` 不会自动装（耗时长，会打网络）。如果你不想用 `cargo-binutils`，可以在 PATH 里放一个 `llvm-objcopy` 作为替代。
