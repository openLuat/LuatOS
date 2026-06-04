# NDK 构建指南

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## 前置依赖

### 必需

- **操作系统**：Windows 10/11（当前仅 PC 模拟器已验证）
- **编译器**：Visual Studio 2019/2022（MSVC）或等效的 `cl.exe` 环境
- **构建工具**：[xmake](https://xmake.io) ≥ 2.7.0
- **PowerShell**：5.1+ 或 PowerShell Core 7.x

### Guest 镜像编译工具链（仅 LLVM）

Phase 3 起只支持 LLVM clang+ld.lld+llvm-objcopy。Phase 3 之前曾支持 GNU 工具链（`riscv64-unknown-elf-gcc` / `riscv32-unknown-elf-gcc` / `riscv-none-elf-gcc`），因不同工具链的 `-march` / `-mabi` / C 扩展默认不同易踩坑，已移除。

- **`clang`**：Windows 推荐 [LLVM 官方](https://releases.llvm.org/) 预编译版（≥ 16.0，自带 RISC-V backend 与 LLD 链接器）
- **`ld.lld`**：随 LLVM 一同发布
- **`llvm-objcopy`**：随 LLVM 一同发布

**验证命令在 PATH 中：**

```powershell
clang --version
ld.lld --version
llvm-objcopy --version
```

### Rust 工具链

（Phase 3 早期规划时考虑过 Rust no-std 示例，因 build 工具链复杂度放弃，本节保留作历史参考。）

- 安装 [rustup](https://rustup.rs/)
- 添加 RISC-V target：`rustup target add riscv32imac-unknown-none-elf`
- 装 core 源码：`rustup component add rust-src`
- 装 objcopy：`cargo install cargo-binutils`（提供 `rust-objcopy`）

---

## Guest 镜像重建

**何时需要：** 修改了 `components/ndk/guest/fixtures/rv32f_regression/main.c` 或 `link.ld` 后。

### 自动构建（推荐）

```powershell
cd components\ndk\guest\fixtures\rv32f_regression
cmd /c build.bat
```

脚本会：
1. 用 LLVM clang+ld.lld+llvm-objcopy 编译所有 RV32IMA / RV32IMF 源文件与 `.S` 文件
2. **自动同步**生成的 `.bin` 到 `testcase/ndk/ndk_basic/scripts/` 对应位置
3. （部分带 RV32C 变体的源）会顺带跑 `llvm-objdump` 验证压缩指令被正确发射

### 输出产物

| 文件 | 位置 | 说明 |
|------|------|------|
| `baremetal.elf` | `guest/build/` | 带符号的 ELF（调试用） |
| `baremetal.bin` | `guest/build/` | Flat binary（约 315 字节，具体大小会随工具链略有变化） |
| `baremetal.map` | `guest/build/` | 链接映射表 |
| ↳ 同步到 | `../scripts/baremetal.bin` | testcase 测试镜像 |
| ↳ 同步到 | `../../../../../bsp/pc/test/113.ndk_simple/baremetal.bin` | PC 快速测试 |

### 手动构建（调试用）

```powershell
cd components\ndk\guest\fixtures\rv32f_regression
mkdir build -ErrorAction SilentlyContinue

# LLVM clang
clang --target=riscv32-unknown-elf -fuse-ld=lld `
  -march=rv32ima_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g -mno-relax `
  -Wl,-T,link.ld -Wl,-Map=build\baremetal.map -Wl,--gc-sections -Wl,--no-relax `
  -o build\baremetal.elf main.c

llvm-objcopy -O binary build\baremetal.elf build\baremetal.bin

# 手动同步
copy build\baremetal.bin ..\scripts\baremetal.bin
copy build\baremetal.bin ..\..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
```

---

## Example 项目的 `build.ps1` / `build_example.ps1`

`components/ndk/guest/examples/` 下四个 C 示例每个都有自己的 `build.ps1`，都委托给共享的：

- `build_example.ps1`（C 4 个）— 调 LLVM clang+ld.lld+llvm-objcopy；自动加 `-I` 指向 `components/ndk/include` 与 `components/ndk/guest/include`，让 `#include "luat_ndk_helper.h"` 等生效。

```powershell
# 4 个 C 示例
cd components\ndk\guest\examples\hello_world;        cmd /c build.ps1
cd ..\exchange_buffer_demo;                          cmd /c build.ps1
cd ..\gpio_hostabi_demo;                             cmd /c build.ps1
cd ..\crypto_hash_demo;                              cmd /c build.ps1
```

---

## PC 宿主侧构建

**关键规则：必须使用 helper 脚本，不要直接运行 `xmake -y`**（会触发全量重建且输出被截断）。

### 标准构建

```powershell
cd bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

- **编译时间**：增量约 10-30 秒（首次约 2-5 分钟）
- **输出**：`build\out\luatos-lua.exe`
- **日志**：`build\logs\` 目录（完整编译日志）

### GUI 变体构建

如果修改了 `components/airui/`、LVGL、SDL 显示相关代码：

```powershell
cmd /c build_windows_32bit_msvc_gui.bat
```

### 验证构建成功

脚本输出末尾应显示：

```
[pc-build] Build completed successfully
```
