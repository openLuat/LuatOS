--[[
@module  board_config
@summary AirCAMERA_1034 Demo 板型适配配置（型号驱动）
@version 2.0
@date    2026.09.18
@author  CodeBuddy
@usage
本文件用于在 AirCAMERA_1034 Demo 中统一管理不同开发板的硬件差异，
包括：USB 摄像头供电使能、LCD 复位/背光/电源、触摸复位/中断 等引脚。

本文件采用与 app_engine/factory 相同的「配置驱动」架构：
型号常量在 main.lua 中声明，本文件负责把型号映射为具体引脚，
业务模块（face_demo / photo_to_aircloud / audio_record）只读引脚，不关心板型。

==================== 使用方法 ====================
切换开发板只需修改 main.lua 中的 BOARD 常量，无需改动本文件：

    PROJECT = "Air1601_AirCAMERA_1034_Demo"   -- 项目名（Luatools / FOTA 用）
    VERSION = "001.999.000"                   -- 固件版本号
    BOARD   = "Air1601_V12"                   -- ← 改这一行即可切换开发板

可选值：
    "Air1601_V11"  → Air1601 V1.1   摄像头供电 GPIO12（5V_EN）
    "Air1601_V12"  → Air1601 V1.2   摄像头供电 GPIO58（VC_EN）  ← 默认
    "Air1602_V12"  → Air1602 V1.2   摄像头供电 GPIO58（VC_EN）
    "Air8601"      → Air8601        摄像头供电 GPIO73（UVC_EN）
    "Air8602"      → Air8602        摄像头供电 GPIO73（UVC_EN）

容错：若 BOARD 未定义（例如单独 require 本模块做单元测试），
      自动回退到默认板型 Air1601_V12，不会中断 sys.run() 启动。

==================== 引脚差异速查表 ====================
| 板型              | 摄像头供电    | LCD_EN | LCD_RST | LCD_BL | TP_RST | TP_INT | TP_8311_EN |
| ----------------- | ------------- | ------ | ------- | ------ | ------ | ------ | ---------- |
| Air1601_V1.1      | GPIO12(5V_EN) | 无     | GPIO15  | GPIO2  | GPIO3  | GPIO51 | GPIO43     |
| Air1601_V1.2      | GPIO58(VC_EN) | GPIO57 | GPIO15  | GPIO13 | GPIO3  | GPIO51 | GPIO43     |
| Air1602_V1.2      | GPIO58(VC_EN) | GPIO57 | GPIO15  | GPIO13 | GPIO3  | GPIO51 | GPIO43     |
| Air8601           | GPIO73(UVC_EN)| 无     | GPIO15  | GPIO13 | GPIO56 | GPIO51 | 无         |
| Air8602           | GPIO73(UVC_EN)| 无     | GPIO15  | GPIO13 | GPIO72 | GPIO51 | 无         |

==================== 注意事项 ====================
- 为什么不能自动识别板型：V1.1/V1.2 底板插的是同一颗 Air1601 模组，
  rtos.bsp() / hmeta.model() / hmeta.hwver() 均只返回模组级信息，无法区分底板版本，
  因此必须在 main.lua 中人工指定 BOARD 常量。
- GPIO73 在不同板子上功能不同：Air1601_V1.2 上是 PA_EN（功放），Air8601 上是 UVC_EN（摄像头供电）。
  因此不能把 12/58/73 三个脚同时拉高来"兼容所有板型"，会造成误触发。
- GPIO56 在 Air8601 上同时是触摸复位引脚，请避免与 TF 卡供电复用。
- 其他业务引脚（UART2、I2C1、SPI1 等）在各板型上保持一致。
]]

local M = {}

-- ==================== 板型标识常量 ====================
-- 取值与 main.lua 中 BOARD 常量的字符串完全一致
M.BOARD_AIR1601_V11 = "Air1601_V11"
M.BOARD_AIR1601_V12 = "Air1601_V12"
M.BOARD_AIR1602_V12 = "Air1602_V12"
M.BOARD_AIR8601     = "Air8601"
M.BOARD_AIR8602     = "Air8602"

-- 默认板型：Air1601_V1.2 / Air1602_V1.2（与历史版本保持兼容）
M.BOARD_DEFAULT = M.BOARD_AIR1601_V12

-- ==================== 板型引脚表 ====================
-- 每块板子的引脚定义；nil 表示该板子无此功能或不需要此引脚
-- power_on：上电时序，格式参考 app_engine/factory 的 config.power_on
--           { pin = GPIO号, dir = 0输出/1输入, level = 0低/1高, [delay = 延时ms] }
local board_pins = {
    [M.BOARD_AIR1601_V11] = {
        name       = "Air1601_V1.1",
        cam_power  = 12,        -- 5V_EN，USB 主机/摄像头总供电
        lcd_en     = nil,       -- 无 LCD_EN
        lcd_rst    = 15,
        lcd_bl     = 2,
        tp_rst     = 3,
        tp_int     = 51,
        tp_8311_en = 43,        -- 触摸 8311 使能，需要拉高
        power_on   = {
            { pin = 12, dir = 0, level = 1, delay = 200 },  -- 5V_EN：USB 主机/摄像头总供电
        },
    },
    [M.BOARD_AIR1601_V12] = {
        name       = "Air1601_V1.2",
        cam_power  = 58,        -- VC_EN，USB 主机/摄像头总供电
        lcd_en     = 57,        -- LCD_EN，高电平有效
        lcd_rst    = 15,
        lcd_bl     = 13,
        tp_rst     = 3,
        tp_int     = 51,
        tp_8311_en = 43,        -- 触摸 8311 使能，需要拉高
        power_on   = {
            { pin = 58, dir = 0, level = 1, delay = 200 },  -- VC_EN：USB 主机/摄像头总供电
        },
    },
    [M.BOARD_AIR1602_V12] = {
        name       = "Air1602_V1.2",
        cam_power  = 58,        -- VC_EN，USB 主机/摄像头总供电
        lcd_en     = 57,        -- LCD_EN，高电平有效
        lcd_rst    = 15,
        lcd_bl     = 13,
        tp_rst     = 3,
        tp_int     = 51,
        tp_8311_en = 43,        -- 触摸 8311 使能，需要拉高
        power_on   = {
            { pin = 58, dir = 0, level = 1, delay = 200 },  -- VC_EN：USB 主机/摄像头总供电
        },
    },
    [M.BOARD_AIR8601] = {
        name       = "Air8601",
        cam_power  = 73,        -- UVC_EN，USB 主机/摄像头总供电
        lcd_en     = nil,       -- 无 LCD_EN
        lcd_rst    = 15,
        lcd_bl     = 13,
        tp_rst     = 56,        -- 注意：与 audio_record 默认 TF 卡供电脚冲突，按需调整
        tp_int     = 51,
        tp_8311_en = nil,       -- 无
        power_on   = {
            { pin = 73, dir = 0, level = 1, delay = 200 },  -- UVC_EN：USB 主机/摄像头总供电
        },
    },
    [M.BOARD_AIR8602] = {
        name       = "Air8602",
        cam_power  = 73,        -- UVC_EN，USB 主机/摄像头总供电
        lcd_en     = nil,       -- 无 LCD_EN
        lcd_rst    = 15,
        lcd_bl     = 13,
        tp_rst     = 72,
        tp_int     = 51,
        tp_8311_en = nil,       -- 无
        power_on   = {
            { pin = 73, dir = 0, level = 1, delay = 200 },  -- UVC_EN：USB 主机/摄像头总供电
        },
    },
}

-- ==================== 解析当前板型 ====================
-- 与 app_engine/factory 一致：main.lua 中的型号常量是唯一编译时变量
-- 优先读取 main.lua 定义的全局 BOARD；未定义时回退到默认板型
local selected = _G.BOARD or M.BOARD_DEFAULT

local pins = board_pins[selected]
if not pins then
    log.warn("board_config", "未知板型", tostring(selected),
        "，回退使用", M.BOARD_DEFAULT)
    selected = M.BOARD_DEFAULT
    pins = board_pins[selected]
end

M.BOARD_VERSION  = selected           -- 当前生效的板型标识
M.name           = pins.name          -- 板型中文名
M.cam_power_pin  = pins.cam_power     -- USB 摄像头/USB 主机总供电使能引脚
M.lcd_en_pin     = pins.lcd_en        -- LCD 电源使能（nil 表示无）
M.lcd_rst_pin    = pins.lcd_rst       -- LCD 复位引脚
M.lcd_bl_pin     = pins.lcd_bl        -- LCD 背光引脚
M.tp_rst_pin     = pins.tp_rst        -- 触摸复位引脚
M.tp_int_pin     = pins.tp_int        -- 触摸中断引脚
M.tp_8311_en_pin = pins.tp_8311_en    -- 触摸 8311 使能引脚（nil 表示无）

-- ==================== 上电时序（配置驱动） ====================
-- 与 factory 的 platform_loader 一致：遍历配置表逐条执行
-- 注意：内部使用 sys.wait，必须在协程中调用（如 sys.taskInit 内）
M.power_on = pins.power_on or {}

function M.apply_power_on()
    for _, step in ipairs(M.power_on) do
        gpio.setup(step.pin, step.dir or 0)
        gpio.set(step.pin, step.level or 1)
        if step.delay and step.delay > 0 then
            sys.wait(step.delay)
        end
    end
    log.info("board_config", "[" .. M.name .. "] 上电时序完成，步骤数:", #M.power_on)
    return true
end

-- ==================== 摄像头供电便捷接口 ====================
-- 仅拉高摄像头/USB 总供电引脚（同步操作，可在任意位置调用，不含 sys.wait）
-- 业务模块若需要等待电源稳定，自行 sys.wait 即可
function M.power_on_camera()
    gpio.setup(M.cam_power_pin, 1, gpio.PULLUP)
    log.info("board_config", "[" .. M.name .. "] 摄像头供电已开启: GPIO" .. M.cam_power_pin)
    return true
end

-- ==================== 启动日志 ====================
log.info("board_config", "当前板型:", M.name,
    "摄像头供电=GPIO" .. M.cam_power_pin,
    "LCD_RST=GPIO" .. M.lcd_rst_pin,
    "LCD_BL=GPIO" .. M.lcd_bl_pin,
    M.lcd_en_pin and ("LCD_EN=GPIO" .. M.lcd_en_pin) or "无 LCD_EN",
    "TP_RST=GPIO" .. M.tp_rst_pin,
    "TP_INT=GPIO" .. M.tp_int_pin,
    M.tp_8311_en_pin and ("TP_8311_EN=GPIO" .. M.tp_8311_en_pin) or "无 TP_8311_EN")

return M