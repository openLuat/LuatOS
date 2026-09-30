--[[
@module  board_config
@summary AirCAMERA_1032 Demo 板型适配配置（型号驱动）
@version 1.0
@date    2026.09.18
@author  CodeBuddy
@usage
本文件用于在 AirCAMERA_1032 Demo 中统一管理不同开发板的硬件差异，包括：
USB 主机模式/摄像头总供电、LCD 复位/背光、触摸复位/中断、TF 卡供电（SD_EN）。

与 AirCAMERA_1034 Demo 保持同一套「配置驱动」架构：
型号常量在 main.lua 中声明，本文件把型号映射为具体引脚，
业务模块（preview / photo_uart_post / photo_to_aircloud / h264_power_test /
video_http_post / rtmp_app）以及 lcd_drv / tp_drv 只读引脚，不关心板型。

==================== 使用方法 ====================
切换开发板只需修改 main.lua 中的 BOARD 常量，无需改动本文件：

    BOARD = "Air8601"        -- ← 改这一行即可切换开发板

可选值：
    "Air1601_V11"  → Air1601_V1.1   摄像头总供电 GPIO12
    "Air1601_V12"  → Air160X_V1.2   摄像头总供电 GPIO58   ← 默认
    "Air8601"      → Air8601        摄像头总供电 GPIO73

容错：若 BOARD 未定义或取值非法（例如单独 require 本模块做单元测试），
      自动回退到默认板型 Air1601_V12，不会中断 sys.run() 启动。

==================== 引脚速查表 ====================
| 板型         | 摄像头供电          | LCD_RST | LCD_BL | TP_RST | TP_INT | TF卡供电(SD_EN) |
| ------------ | ------------------- | ------- | ------ | ------ | ------ | --------------- |
| Air1601_V1.1 | GPIO12 (USB主机总供电) | GPIO15  | GPIO2  | GPIO2  | GPIO51 | 无              |
| Air160X_V1.2 | GPIO58 (USB主机总供电) | GPIO15  | GPIO2  | GPIO2  | GPIO51 | GPIO56          |
| Air8601      | GPIO73 (UVC_EN)     | GPIO15  | GPIO13 | GPIO72 | GPIO51 | 无              |

==================== 注意事项 ====================
- Air8601 的背光脚是 PIN43，且 PIN43 复位后默认不是 GPIO 功能，
  必须先执行 pins.setup(43, "GPIO13") 复用，之后 gpio.set(13, 1) 才会真正落到引脚上。
  本文件的 apply_pin_mux() 负责这一步，lcd_drv 在初始化 LCD 前会先调用它。
  漏掉该复用会导致背光不亮 -> 白屏（Air8601 寄存柜工程踩过同样的坑）。
- Air8601 的 TP_RST / TP_INT 取 GPIO72 / GPIO51：与两块已上板验证通过的寄存柜工程
  （Air8601/ Air8602_deposit_cabinet 的 hardware.lua）完全一致，也与官方 9 寸板配置
  app_engine/factory_new/config/eng_8601_9i_v0.lua 一致（TP_RESET = GPIO72、
  TP_INT = GPIO51）。注意 7 寸板配置 eng_8601_7i_v0.lua 写的是 GPIO56 / WAKEUP0，
  那是 7 寸板的接线，不要混用。
- Air8601 触摸没反应，第一个要查的就是本文件的 power_on 上电时序：
  寄存柜工程 hardware.lua 里同一段代码特意注释过「各 GPIO 电平切换之间必须延时等待，
  确保电源/复位引脚电平稳定后再进行下一步，否则外设（LCD/触摸/4G）可能上电不完整
  导致初始化失败」。
- Air8601 上 GPIO56 同时是触摸相关引脚（7 寸板接线里它就是 TP_RST），
  因此本表 tf_pwr 留空，避免与触摸抢同一个引脚。
- Air1601_V1.1 / Air860X_V1.2 的 LCD_BL 与 TP_RST 沿用本 demo 原有取值（GPIO2），
  未做改动，以保证已有底板的显示/触摸行为不变。
]]

local M = {}

-- ==================== 板型标识常量 ====================
-- 取值与 main.lua 中 BOARD 常量的字符串完全一致
M.BOARD_AIR1601_V11 = "Air1601_V11"
M.BOARD_AIR1601_V12 = "Air1601_V12"
M.BOARD_AIR8601     = "Air8601"

-- 默认板型：Air160X_V1.2（与历史版本保持兼容）
M.BOARD_DEFAULT = M.BOARD_AIR1601_V12

-- ==================== 板型引脚表 ====================
-- 每块板子的引脚定义；nil 表示该板子无此功能或不需要此引脚
-- pins_mux   ：板型专属的引脚功能复用，{ pin = GPIO号, func = 复用功能名 }
-- power_on   ：板型专属上电时序，按数组顺序逐条执行，delay 单位 ms；nil/空表表示无需时序
-- tp_rst_pre ：调用 tp.init 之前是否需要手动做一次「拉低 -> 高阻」预复位
local board_pins = {
    [M.BOARD_AIR1601_V11] = {
        name     = "Air1601_V1.1",
        cam_power = 12,        -- USB 主机模式/摄像头总供电，高电平有效
        lcd_rst  = 15,
        lcd_bl   = 2,          -- 背光
        tp_rst   = 2,
        tp_int   = 51,
        tf_pwr   = nil,        -- 该底板无 SD_EN 引脚
        pins_mux = nil,
        tp_rst_pre = true,     -- 沿用本 demo 原实现（tp_drv 里的 gpio.setup/gpio.close）
        power_on = nil,        -- 该底板无需上电时序
    },
    [M.BOARD_AIR1601_V12] = {
        name     = "Air160X_V1.2",
        cam_power = 58,        -- USB 主机模式/摄像头总供电，高电平有效
        lcd_rst  = 15,
        lcd_bl   = 2,          -- 背光
        tp_rst   = 2,
        tp_int   = 51,
        tf_pwr   = 56,         -- SD_EN，使用 TF 卡的模块需要拉高
        pins_mux = nil,
        tp_rst_pre = true,
        power_on = nil,
    },
    [M.BOARD_AIR8601] = {
        name     = "Air8601",
        cam_power = 73,        -- UVC_EN，USB 主机模式/摄像头总供电，高电平有效
        lcd_rst  = 15,
        lcd_bl   = 13,         -- 背光，物理引脚为 PIN43，需先 pins.setup(43,"GPIO13")
        tp_rst   = 72,
        tp_int   = 51,
        tf_pwr   = nil,        -- GPIO56 在本板上是触摸相关引脚，不复用为 SD_EN
        pins_mux = {
            { pin = 43, func = "GPIO13" },   -- ★ 背光必需：PIN43 复用成 GPIO13
        },
        -- 不做手动预复位：GPIO72 在本板上是「TP I2C 上拉」控制脚（官方 7i 配置注释：
        -- { pin = 72, level = 1 } -- TP I2C 上拉（485_RE_DE 拉高，同时 TP I2C 就绪）），
        -- 先拉低再置高阻会让 TP 的 I2C 上拉失效，交给 tp.init 内部的复位时序处理即可。
        -- 两块已验证跑通的寄存柜工程也都是直接调 tp.init，没有这一步。
        tp_rst_pre = false,
        -- ★ 板型上电时序：与已验证跑通的 Air8601 / Air8602 寄存柜工程 hardware.lua 逐字一致。
        -- 顺序即依赖（4G 复位 -> 背光 -> 外设供电 -> UVC 摄像头），delays 不可省：
        -- 官方原注释写明「否则外设（LCD/触摸/4G）可能上电不完整导致初始化失败」，
        -- 触摸没反应时首先怀疑这里。
        power_on = {
            { pin = 42, level = 1, delay = 50 },
            { pin = 65, level = 0, delay = 100 },
            { pin = 65, level = 1, delay = 1000 },
            { pin = 13, level = 1 },              -- 背光（PIN43，依赖上面的 pins_mux 复用）
            { pin = 52, level = 1 },
            { pin = 56, level = 1 },
            { pin = 73, level = 1, delay = 200 }, -- UVC_EN，等 200ms 摄像头就绪
        },
    },
}

-- ==================== 解析当前板型 ====================
-- main.lua 中的 BOARD 常量是唯一编译时变量
local selected = _G.BOARD or M.BOARD_DEFAULT

-- 注意：这里的局部变量不能叫 pins —— 会遮蔽全局 pins 库，
-- 导致下面 apply_pin_mux() 里的 pins.setup() 调用失败，故命名 cfg
local cfg = board_pins[selected]
if not cfg then
    log.warn("board_config", "未知板型", tostring(selected),
        "，回退使用", M.BOARD_DEFAULT)
    selected = M.BOARD_DEFAULT
    cfg = board_pins[selected]
end

M.BOARD_VERSION = selected
M.name          = cfg.name

M.cam_power_pin = cfg.cam_power   -- USB 主机模式/摄像头总供电使能引脚
M.lcd_rst_pin   = cfg.lcd_rst     -- LCD 复位引脚
M.lcd_bl_pin    = cfg.lcd_bl      -- LCD 背光引脚
M.tp_rst_pin    = cfg.tp_rst      -- 触摸复位引脚
M.tp_int_pin    = cfg.tp_int      -- 触摸中断引脚
M.tf_pwr_pin    = cfg.tf_pwr      -- TF 卡供电使能（SD_EN），nil 表示无
M.pins_mux      = cfg.pins_mux or {}
M.lcd_en_pin    = nil              -- 三款底板均无独立 LCD_EN
M.power_on_steps = cfg.power_on or {}          -- 板型上电时序（含延时）
M.tp_rst_pre     = cfg.tp_rst_pre and true or false  -- tp.init 前是否需要手动预复位

-- ==================== 上电时序延时 ====================
-- 优先 sys.wait 让出 CPU；若当前上下文不可让出（极少数情况），退化为忙等，
-- 保证延时一定被满足 —— 上电时序延时不足会直接导致 LCD/触摸初始化失败
local function wait_ms(ms)
    if coroutine.isyieldable and coroutine.isyieldable() then
        sys.wait(ms)
    elseif mcu and mcu.ticks then
        local t = mcu.ticks()
        while mcu.ticks() - t < ms do end
    end
end
M.wait_ms = wait_ms

-- ==================== 板型上电时序 ====================
-- 部分底板（Air8601）必须按固定顺序 + 延时把各外设电源/复位脚拉起来，
-- 之后 LCD 和触摸才能初始化成功；无该需求的板型自动跳过（步骤为空表）。
-- 调用时机：apply_pin_mux() 之后、LCD / 触摸初始化之前。
function M.power_on()
    if #M.power_on_steps == 0 then
        return true
    end
    for _, s in ipairs(M.power_on_steps) do
        gpio.setup(s.pin, 0)
        gpio.set(s.pin, s.level)
        if s.delay then
            wait_ms(s.delay)
        end
    end
    log.info("board_config", "[" .. M.name .. "] 上电时序完成")
    return true
end

-- ==================== 引脚功能复用 ====================
-- 板型专属复用（例如 Air8601 背光 PIN43 -> GPIO13）。
-- 必须在 LCD 初始化之前调用；重复调用安全（幂等）。
function M.apply_pin_mux()
    for _, m in ipairs(M.pins_mux) do
        pins.setup(m.pin, m.func)
        log.info("board_config", "[" .. M.name .. "] 引脚复用",
            "PIN" .. m.pin .. " -> " .. m.func)
    end
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

-- ==================== TF 卡供电便捷接口 ====================
-- 部分底板有 SD_EN（Air160X_V1.2=GPIO56），无该引脚的底板自动跳过
function M.power_on_tf()
    if not M.tf_pwr_pin then
        log.info("board_config", "[" .. M.name .. "] 无 SD_EN 引脚，跳过 TF 卡供电")
        return false
    end
    gpio.setup(M.tf_pwr_pin, 1)
    log.info("board_config", "[" .. M.name .. "] TF 卡供电已开启: GPIO" .. M.tf_pwr_pin)
    return true
end

-- ==================== 启动日志 ====================
log.info("board_config", "当前板型:", M.name,
    "摄像头供电=GPIO" .. M.cam_power_pin,
    "LCD_RST=GPIO" .. M.lcd_rst_pin,
    "LCD_BL=GPIO" .. M.lcd_bl_pin,
    "TP_RST=GPIO" .. M.tp_rst_pin,
    "TP_INT=GPIO" .. M.tp_int_pin,
    M.tf_pwr_pin and ("TF供电=GPIO" .. M.tf_pwr_pin) or "无 SD_EN")

return M
