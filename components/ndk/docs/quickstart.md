# NDK 快速验证

> 本文是 NDK 文档集的一部分。完整索引见 [`../README.md`](../README.md)。

## RV32F 当前支持说明（阶段性）

- 通过 `ndk.rv32i(..., { isa = "rv32imf" })` 启用单精度浮点扩展。
- 当前已覆盖常见编译器发射路径：`FLW/FSW`、`FMV.*`、`FADD/FSUB/FMUL/FDIV/FSQRT.S/FMADD.S/FMSUB.S/FNMSUB.S/FNMADD.S`、`FMIN/FMAX.S`、`FEQ/FLT/FLE.S`、`FCLASS.S`、`FCVT.S.W/WU`、`FCVT.W/WU.S`。
- 当前 host-backed rounding 支持 `RNE/RTZ/RDN/RUP`（`rm/frm = 0..3`）。
- `RMM`（`rm/frm = 4`）**当前仍未支持**，遇到该 rounding mode 会按非法指令路径处理（阶段性限制，后续再扩展）。
- 已补充 `RMM` 限制回归：`baremetal_fadd_rmm_static.bin`（`rm=4`）与 `baremetal_fadd_rmm_dynamic.bin`（`frm=4 + rm=dyn`）在 `rv32imf` 模式下都应触发非法指令 trap。

---

## 快速验证流程

如果你已经有了可用的构建环境，直接执行：

```powershell
# 1. 重建 ndk_basic guest 镜像（可选，如果二进制已是最新则跳过）
cd components\ndk\guest\fixtures\rv32f_regression
cmd /c build.bat

# 2. 重建 hostabi fixture（含 crypto + RV32C 回归镜像）
cd ..\..\
.\build_hostabi_v1.ps1

# 3. 构建 PC 模拟器
cd ..\..\..\..\bsp\pc
cmd /c build_windows_32bit_msvc.bat

# 4. 运行 hostabi 回归（含 crypto 命令链）
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\

# 5. 运行 ndk_basic 回归
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

期望输出：`Total: N passed, 0 failed`（当前基线：`ndk_hostabi_basic` 为 `39 passed, 0 failed`；`ndk_basic` 为 `42 passed, 0 failed`）

---

## 完整验证流程（从零开始）

### Step 1: 检查依赖

```powershell
# 检查 xmake
xmake --version

# 检查 MSVC（在 VS Developer Command Prompt 中）
cl

# 检查 RISC-V 工具链（可选，仅重建 guest 时需要）
riscv64-unknown-elf-gcc --version
# 或
riscv-none-elf-gcc --version
# 或
clang --version
ld.lld --version
```

### Step 2: 克隆仓库（如果尚未）

```powershell
git clone https://gitee.com/openLuat/LuatOS.git
cd LuatOS
```

### Step 3: 重建 Guest 镜像

```powershell
cd components\ndk\guest\fixtures\rv32f_regression
cmd /c build.bat
```

期望输出：
```
=== Building RISC-V Baremetal Guest ===
Using GNU toolchain: riscv64-unknown-elf
...
=== Build successful ===
  BIN: build\baremetal.bin (315 bytes)
...
=== Syncing binary to target locations ===
  Copying to: ...\testcase\ndk\ndk_basic\scripts\baremetal.bin
  Copying to: ...\bsp\pc\test\113.ndk_simple\baremetal.bin
=== All done! ===
```

### Step 4: 重建 Host ABI fixture（含 crypto + RV32C）

```powershell
cd ..\..\
.\build_hostabi_v1.ps1
```

期望输出包含：
```
[build] Success: hostabi_v1.bin (...)
[build] Success: hostabi_v1_rvc.bin (...)
```

### Step 5: 构建 PC 模拟器

```powershell
cd ..\..\..\..\bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

期望输出末尾：
```
[pc-build] Build completed successfully
```

### Step 6: 运行 hostabi suite（含 crypto 命令链）

```powershell
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

### Step 7: 运行 ndk_basic suite

```powershell
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

---

## 预期结果

### 成功输出示例

```
[I]/testcase/ndk/ndk_basic/scripts/main.lua:15 ndk test result Total: N passed, 0 failed
```

### 关键日志（调试级别）

测试中会看到 guest 通过 CSR 写发出的调试信息：

```
vm:  main is at: 0x80000014
vm:  Buffer is at: 0x80001120
vm:  Stack top is at: 0x8000113F
vm:  Testing strlen optimization:
vm num:  Length of teststr1: 13
vm num:  Length of teststr2: 71
Control Store: set val to 00005555
```

**注意**：上述地址值（`0x80000014` 等）会因编译器版本、优化级别和工具链差异而变化，但消息格式和关键数值（`13`、`71`、`00005555`）保持稳定。

最后一行 `Control Store: set val to 00005555` 表示 guest 正常退出（写 `0x5555` 到 SYSCON）。

### 失败迹象

- **错误 1**：`can't open /luadb/baremetal.bin`
  - **原因**：guest 镜像未同步或路径错误
  - **解决**：重新运行 `build.bat` 确保同步完成

- **错误 2**：`exec fail timeout` 或 trap 错误
  - **原因**：二进制损坏或源码不匹配
  - **解决**：清理 `guest/build/` 后重建

- **错误 3**：测试数量不对（如 `Total: 0 passed`）
  - **原因**：testcase 脚本未找到或加载错误
  - **解决**：检查命令行参数顺序（common 在前，ndk_basic 在后）
