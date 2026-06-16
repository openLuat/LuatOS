# ems_server luac 预生成说明

## 背景

`ems_server` 组件将 `ems.lua` 预编译成 luac 字节码，以 C 数组形式嵌入到固件中。由于 LuatOS 同时支持 **32bit VM** 和 **64bit VM**，两种 VM 的字节码格式不兼容（主要是 `size_t` 宽度不同），因此需要提前生成两份 luac：

- `luat_ems_server_luac_32.c` — 供 32bit VM 固件使用
- `luat_ems_server_luac_64.c` — 供 64bit VM 固件使用

固件编译时通过 `LUAT_CONF_FIRMWARE_TYPE_NUM` 判断：

- `1 ~ 99`：使用 `luat_ems_server_luac_32.c`
- `>= 100`：使用 `luat_ems_server_luac_64.c`

> 注意：编译固件时 **不再自动调用** `gen_luac.bat`/`gen_luac.sh`。修改 `ems.lua` 后，需要手动重新生成对应版本的 luac 文件。

---

## 生成工具

当前目录下提供三个文件：

| 文件 | 用途 |
|------|------|
| `gen_luac.lua` | 实际生成 C 数组的 Lua 脚本 |
| `gen_luac.bat` | Windows 入口 |
| `gen_luac.sh` | Linux / macOS 入口 |

生成逻辑：

1. 加载 `ems.lua`
2. 使用 `string.dump()` 生成 luac 字节码
3. 输出为 `src/luat_ems_server_luac_<suffix>.c`

---

## Windows 下生成

### 1. 先准备对应的解释器

| 位数 | 首选解释器 | 默认路径 |
|------|-----------|----------|
| 32bit | PC 模拟器 | `LuatOS/bsp/pc/build/out/luatos-lua.exe` |
| 64bit | PC 模拟器 | `LuatOS/bsp/pc/build/out64/luatos-lua.exe` |
| 64bit | 备用：WSL `lua5.3` | 自动检测 `/usr/bin/lua5.3` |

- 32bit 模拟器通过 `bsp/pc/build_windows_32bit_msvc.bat` 构建（默认输出到 `build/out`）。
- 64bit 模拟器通过 `bsp/pc/build_windows_64bit_msvc.bat` 构建，构建后请复制/重命名到 `build/out64/luatos-lua.exe`。

如果已有其他 64bit Lua 5.3 解释器（Windows 原生 `.exe`），也可以通过环境变量指定：

```bat
set LUATOS_LUA_EXE=C:\path\to\lua53-64bit.exe
gen_luac.bat 64
```

> 提示：
> - `gen_luac.bat` 会优先使用 `LUATOS_LUA_EXE`；若未指定且 64bit 模拟器不存在，则会尝试调用 WSL 的 `lua5.3` 作为备用。因此在没有构建 64bit 模拟器的环境中，只要安装了 WSL + `lua5.3`，也能直接生成 64bit 版本。
> - **32bit 版本必须通过 32bit 解释器生成**。WSL 的 `lua5.3` 是 64bit，不能用于生成 32bit 字节码；生成 32bit 时请确保存在 32bit `luatos-lua.exe`。

### 2. 生成命令

```bat
cd LuatOS\components\ems_server

:: 生成 32bit 版本
gen_luac.bat 32

:: 生成 64bit 版本
gen_luac.bat 64
```

### 3. 验证输出

生成成功后会在 `src/` 目录下看到：

```text
src/luat_ems_server_luac_32.c
src/luat_ems_server_luac_64.c
```

---

## Linux / macOS 下生成

### 1. 准备 Lua 5.3 解释器

需要系统已安装 `lua5.3`（64bit 版本通常即为系统默认）。如果没有：

```bash
# Ubuntu/Debian
sudo apt-get install lua5.3

# macOS
brew install lua@5.3
```

32bit 字节码需要使用 32bit 的 `luatos-lua.exe` 或 32bit Lua 5.3 解释器；64bit 字节码使用系统 `lua5.3` 即可。

### 2. 生成命令

```bash
cd LuatOS/components/ems_server

# 生成 32bit 版本
LUAT_EMS_LUAC_SUFFIX=32 bash gen_luac.sh

# 生成 64bit 版本
LUAT_EMS_LUAC_SUFFIX=64 bash gen_luac.sh
```

如果要强制使用系统 `lua5.3` 而不是 `luatos-lua.exe`，可以指定一个不存在的 `luatos-lua.exe` 路径：

```bash
LUAT_EMS_LUAC_SUFFIX=64 LUATOS_LUA_EXE=/nonexistent bash gen_luac.sh
```

### 3. 验证输出

```bash
ls -la src/luat_ems_server_luac_*.c
```

---

## 如何确认字节码位数

查看生成文件第二行数据即可区分：

```text
32bit: 0x1B, 0x4C, 0x75, 0x61, 0x53, 0x00, 0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A, 0x04, 0x04, 0x04, 0x08,
                                                                    ^^ size_t = 4

64bit: 0x1B, 0x4C, 0x75, 0x61, 0x53, 0x00, 0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A, 0x04, 0x08, 0x04, 0x08,
                                                                    ^^ size_t = 8
```

Lua 5.3 字节码头格式：

- 字节 1~4：`\x1BLua`
- 字节 5：版本号 `0x53`
- 字节 6：格式号 `0x00`
- 字节 7~12：固定校验数据
- 字节 13：int 大小
- 字节 14：**size_t 大小**（32bit=4，64bit=8）
- 字节 15：Instruction 大小
- 字节 16：lua_Number 大小

---

## 与固件编译的关联

修改后的 `luatos-soc-2024/project/luatos/xmake.lua` 会在 `on_config` 阶段读取 `luat_conf_bsp.txt`：

```lua
local LUAT_CONF_FIRMWARE_TYPE_NUM = tonumber(conf_data:match("#define LUAT_CONF_FIRMWARE_TYPE_NUM (%d+)"))
local ems_luac_suffix = "32"
if LUAT_CONF_FIRMWARE_TYPE_NUM and LUAT_CONF_FIRMWARE_TYPE_NUM >= 100 then
    ems_luac_suffix = "64"
end
target:add("files", luatos_root .. "/components/ems_server/src/luat_ems_server_luac_" .. ems_luac_suffix .. ".c")
```

因此：

- 固件序号 `1 ~ 99` → 编译 `luat_ems_server_luac_32.c` → 运行时使用 32bit VM
- 固件序号 `>= 100` → 编译 `luat_ems_server_luac_64.c` → 运行时使用 64bit VM

`luat/modules/luat_main.c` 中也会根据 `LUAT_CONF_VM_64bit` 宏选择对应的数组：

```c
#ifdef LUAT_CONF_VM_64bit
  const unsigned char* ems_luac = ems_server_luac_64;
  size_t ems_luac_len = ems_server_luac_64_len;
#else
  const unsigned char* ems_luac = ems_server_luac_32;
  size_t ems_luac_len = ems_server_luac_32_len;
#endif
```

---

## 修改 ems.lua 后的流程

1. 修改 `ems.lua`
2. 重新生成两份 luac：
   - Windows：`gen_luac.bat 32` 和 `gen_luac.bat 64`
   - Linux/macOS：`LUAT_EMS_LUAC_SUFFIX=32 bash gen_luac.sh` 和 `LUAT_EMS_LUAC_SUFFIX=64 bash gen_luac.sh`
3. 提交两个生成的 `.c` 文件到仓库
4. 编译固件

---

## 常见问题

### Q1：没有 64bit 的 `luatos-lua.exe` 怎么办？

Windows 下可以：

1. 构建 64bit PC 模拟器：`bsp/pc/build_windows_64bit_msvc.bat`
2. 将产物复制到 `bsp/pc/build/out64/luatos-lua.exe`

或者在已安装 64bit Lua 5.3 的机器上通过 `set LUATOS_LUA_EXE=...` 指定。

Linux/macOS 下通常直接安装系统 `lua5.3` 即可生成 64bit 版本。

### Q2：可以只生成一份吗？

如果只针对单一固件类型开发，可以只生成对应版本。但建议两份都生成并提交，避免 CI 或其他开发者编译不同序号固件时报错。

### Q3：旧的 `luat_ems_server_luac.c` 还有用吗？

当前 `xmake.lua` 已经不再编译 `luat_ems_server_luac.c`，它仅作为历史文件保留。建议保留或删除均可，但不会影响新逻辑。
