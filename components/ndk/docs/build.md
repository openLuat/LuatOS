# NDK 构建指南

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## 前置依赖

### 必需

- **操作系统**：Windows 10/11（当前仅 PC 模拟器已验证）
- **编译器**：Visual Studio 2019/2022（MSVC）或等效的 `cl.exe` 环境
- **构建工具**：[xmake](https://xmake.io) ≥ 2.7.0
- **PowerShell**：5.1+ 或 PowerShell Core 7.x

### Guest 镜像编译工具链（二选一）

仅在需要重建 `baremetal.bin` 时必需。优先级顺序：

1. **GNU RISC-V 工具链**（推荐）
   - `riscv64-unknown-elf-gcc` / `riscv64-unknown-elf-objcopy`
   - 或 `riscv32-unknown-elf-gcc` / `riscv32-unknown-elf-objcopy`
   - 或 `riscv-none-elf-gcc` / `riscv-none-elf-objcopy`（xPack 工具链）
   - 获取：[xPack RISC-V GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)、[SiFive GNU Toolchain](https://github.com/sifive/freedom-tools/releases)

2. **LLVM/Clang** with RISC-V 支持（备用）
   - `clang` + `ld.lld` + `llvm-objcopy`（需要完整的 RISC-V backend 和 LLD 链接器）
   - 获取：[LLVM 官方](https://releases.llvm.org/)，Windows 下需 RISC-V target 编译版或手动开启 target

**验证命令在 PATH 中：**

```powershell
# GNU 工具链（任意一种）
riscv64-unknown-elf-gcc --version
# 或
riscv32-unknown-elf-gcc --version
# 或
riscv-none-elf-gcc --version

# LLVM（三个命令都需要）
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
1. 自动检测可用工具链（GNU > LLVM）
2. 编译 `main.c` 生成 RV32IMA flat binary
3. **自动同步**二进制到两个位置：
   - `testcase/ndk/ndk_basic/scripts/baremetal.bin`（testcase 使用）
   - `bsp/pc/test/113.ndk_simple/baremetal.bin`（PC 快速测试）

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

# GNU 工具链
riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g `
  -Wl,-T,link.ld -Wl,-Map=build\baremetal.map -Wl,--gc-sections `
  -o build\baremetal.elf main.c

riscv64-unknown-elf-objcopy -O binary build\baremetal.elf build\baremetal.bin

# 手动同步
copy build\baremetal.bin ..\scripts\baremetal.bin
copy build\baremetal.bin ..\..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
```

---

## Example 项目的 `build.ps1` / `build_example.ps1`

`components/ndk/guest/examples/` 下四个 C 示例每个都有自己的 `build.ps1`，都委托给共享的：

- `build_example.ps1`（C 4 个）— 自动检测 GNU/LLVM 工具链；自动加 `-I` 指向 `components/ndk/include` 与 `components/ndk/guest/include`，让 `#include "luat_ndk_helper.h"` 等生效。

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
