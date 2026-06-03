# NDK Guest 示例索引

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

NDK 的 guest 程序都是独立的小项目，每个目录自带 `main.c`（或 `src/main.rs`）+ `link.ld` + `build.ps1`，编译产出 `<name>.bin`，再用 `ndk.rv32i(...)` 加载。

| 目录 | 语言 | 用途 | 关键 host 调用 |
|---|---|---|---|
| [`../guest/examples/hello_world/`](../guest/examples/hello_world) | C | 最小化：写 exchange + SYSCON 退出 | 无 |
| [`../guest/examples/exchange_buffer_demo/`](../guest/examples/exchange_buffer_demo) | C | 演示 exchange buffer 的请求/响应布局 | 无 |
| [`../guest/examples/gpio_hostabi_demo/`](../guest/examples/gpio_hostabi_demo) | C | GPIO v2 CSR 请求/应答模式 | `GPIO_CONFIG` / `GPIO_WRITE` / `GPIO_READ` |
| [`../guest/examples/crypto_hash_demo/`](../guest/examples/crypto_hash_demo) | C | MD5 / CRC32 host 计算 | `CRYPTO_MD5` / `CRYPTO_CRC32` |

更"严肃"的回归与基准程序在 `components/ndk/guest/fixtures/`：

| 目录 | 用途 |
|---|---|
| [`../guest/fixtures/rv32f_regression/`](../guest/fixtures/rv32f_regression) | RV32F 浮点回归（20+ 个 .S 文件 + hardfloat_*） |
| [`../guest/fixtures/hostabi_v1/`](../guest/fixtures/hostabi_v1) | Host ABI v1 命令链回归（含 RV32C 变体） |

---

## 一个示例的完整生命周期

```powershell
# 1. 进目录
cd components\ndk\guest\examples\hello_world

# 2. 编译
cmd /c build.ps1
# => build\hello_world.bin

# 3. 同步到 PC 测试脚本目录
copy build\hello_world.bin ..\..\..\..\..\testcase\ndk\ndk_basic\scripts\hello_world.bin

# 4. 重建 PC 固件（如首次需要）
cd ..\..\..\..\..\bsp\pc
cmd /c build_windows_32bit_msvc.bat

# 5. 跑
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

---

## 用 helper 写一个自己的示例

所有 4 个 C 示例都已经改用 `luat_ndk_helper.h`。新写一个示例的最简模板：

```c
/* my_example/main.c */
#include "luat_ndk_helper.h"   /* 自动 include luat_ndk_builtin.h + luat_ndk_abi.h */

static int main(void) {
    /* 与 host 交换数据 */
    ndk_exchange_write_bytes(0, (const uint8_t *)"MY_DATA", 7);

    /* 可选：调 host CSR */
    uint32_t status = ndk_hash_md5(/*in*/ 0, /*len*/ 7, /*out*/ 64);
    ndk_exchange_write_u32(32, status);

    /* 退出 */
    ndk_exit_ok();
    return 0;
}
NDK_GUEST_START(main)
```

```ld
/* my_example/link.ld */
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.* COMMON) }
}
```

```powershell
# my_example/build.ps1
& "$PSScriptRoot\..\build_example.ps1" -ExampleName "my_example"
```

`build_example.ps1` 会自动把 `-I` 指向 helper 头文件所在的 `components/ndk/guest/include` 和 `components/ndk/include`。helper 暴露的 API 详见 [`api-helper.md`](./api-helper.md)。
