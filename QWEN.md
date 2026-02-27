# LuatOS 项目上下文

## 项目概述

**LuatOS** 是一个基于 Lua 5.3 虚拟机的嵌入式操作系统，由合宙（openLuat）开发。它支持多种硬件平台（Air8000/Air8101/Air780E 等系列），提供 74+ 核心库、55+ 扩展库和 1000+ API，用于智能设备开发。

### 技术栈
- **核心语言**: Lua 5.3.5（经合宙优化）
- **构建系统**: xmake
- **目标平台**: 嵌入式 MCU（ARM/RISC-V）、PC 模拟器（Windows/Linux/macOS）
- **授权**: MIT License

## 目录结构

```
LuatOS/
├── lua/              # Lua 虚拟机源码（基于 5.3.5 官方版本）
├── luat/             # LuatOS 核心框架
│   ├── include/      # 核心头文件
│   ├── modules/      # C 实现的 Lua 库（GPIO/UART/SPI 等）
│   ├── vfs/          # 虚拟文件系统
│   └── weak/         # 弱定义实现
├── components/       # 扩展组件库（74+ 核心库）
│   ├── network/      # 网络协议栈（LwIP/MQTT/HTTP 等）
│   ├── airui/        # GUI 框架（基于 LVGL 9）
│   ├── mbedtls/      # 加密库
│   ├── fatfs/        # 文件系统
│   └── ...           # 其他组件（蓝牙/音频/传感器等）
├── bsp/              # 板级支持包
│   ├── pc/           # PC 模拟器源码（xmake 构建）
│   └── [模组型号]/    # 各硬件平台的固件和 demo
├── module/           # 模组固件和方案代码
│   ├── Air780EPM/    # 具体模组型号的固件/ demo /project
│   ├── Air8000/
│   └── spec/         # 协议规范文档
├── script/           # Lua 脚本库
│   ├── corelib/      # 核心库（sys.lua 等）
│   ├── libs/         # 外部驱动库
│   └── turnkey/      # 准项目级方案
├── testcase/         # 测试用例
├── tools/            # 辅助工具
└── build/            # 构建输出目录
```

## 构建和运行

### PC 模拟器构建（xmake）

```bash
# 进入 PC BSP 目录
cd bsp/pc

# 配置（32 位或 64 位）
xmake f -a x86 -y        # 32 位
xmake f -a x64 -y        # 64 位

# 构建
xmake -y

# 清理
xmake clean -a
```

**输出位置**: `build/out/luatos-lua.exe`（Windows）

### 运行测试

```bash
# 运行单个测试用例
build/out/luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/<feature>/<feature>_basic/scripts/
```

**测试结构**:
```
testcase/<feature>/<feature>_basic/scripts/
├── metas.json          # 测试元数据
├── main.lua            # 入口（定义 PROJECT/VERSION，调用 sys.taskInit）
└── <feature>_test.lua  # 测试函数（test_ 开头）
```

### 关键宏定义（xmake.lua）

| 宏 | 说明 |
|---|---|
| `LUAT_USE_GUI` | 启用 GUI 支持（LVGL/SDL2） |
| `LUAT_CONF_VM_64bit` | 64 位 Lua 虚拟机 |
| `MBEDTLS_CONFIG_FILE` | mbedtls 版本配置（2.x 或 3.x） |

## 开发规范

### C 代码（核心模块）

- **API 前缀**: `luat_`（如 `luat_gpio_set`、`luat_uart_open`）
- **头文件位置**: `luat/include/`
- **模块命名**: `luat_lib_<module>.c`（如 `luat_lib_gpio.c`）
- **组件宏**: `LUAT_USE_<FEATURE>` 控制编译

### Lua 代码（脚本/测试）

- **任务管理**: 使用 `sys.taskInit(function() ... end)` 实现并发
- **入口点**: 脚本以 `sys.run()` 结束
- **日志**: `log.info(tag, message)`
- **断言**: `assert(condition, message)`
- **测试函数**: 必须以 `test_` 开头

### 测试框架

```lua
-- main.lua 模板
PROJECT = "testcase_name"
VERSION = "1.0.0"

require("testrunner")
sys.taskInit(function()
    -- 测试逻辑
end)
sys.run()
```

```lua
-- <feature>_test.lua 模板
local function test_feature_name()
    log.info("test", "testing...")
    assert(condition, "error message")
end
```

## 核心架构

### 1. Lua 虚拟机层（`lua/`）
- 基于 Lua 5.3.5 官方源码
- 合宙优化版本（性能/内存优化）

### 2. 核心框架层（`luat/`）
- **任务调度**: 协程管理、事件循环
- **VFS**: 统一文件接口（支持 FATFS/LFS 等）
- **HAL**: 硬件抽象层（GPIO/UART/SPI/I2C 等）

### 3. 组件层（`components/`）
- **网络**: LwIP、MQTT、HTTP、WebSocket、CoAP
- **GUI**: LVGL 9 + AirUI、U8G2
- **安全**: mbedtls、crypto、xxtea
- **存储**: FATFS、LFS、SFUD、FlashDB
- **多媒体**: 音频编解码（OPUS/AMR）、图像（JPEG/PNG）

### 4. 脚本层（`script/`）
- **corelib**: 系统核心库（sys.lua 任务系统）
- **libs**: 标准化外设驱动库
- **turnkey**: 完整项目方案参考

## 关键文件

| 文件 | 说明 |
|---|---|
| `bsp/pc/xmake.lua` | PC 模拟器构建配置 |
| `luat/include/luat.h` | 核心头文件 |
| `script/corelib/sys.lua` | Lua 任务系统核心 |
| `module/<型号>/core` | 模组固件描述 |
| `.github/workflows/` | CI/CD 配置 |

## 文档和资源

- **官方文档**: https://docs.openluat.com/
- **API 参考**: https://docs.openluat.com/osapi/
- **第三方工具**: LuatOS IDE Helper (https://gitee.com/tianyiw/LuatOS-ide-helper)

## 快速入门流程

1. **硬件准备**: 使用支持的开发板或 PC 模拟器
2. **刷机工具**: 使用 LuaTools 下载固件
3. **学习路径**: 浏览 API 文档 → 运行 demo → 开发业务代码
4. **调试方式**: PC 模拟器测试 → 硬件部署

---

```lua
-- 感谢您使用 LuatOS ^_^
-- Thank you for using LuatOS ^_^
print("Hello LuatOS!")
```
