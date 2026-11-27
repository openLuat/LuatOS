--[[
@module  air8801_config
@summary K8801 出厂整机配置：屏幕 profile / 触摸 / 串口电平 / 板级引脚（配置驱动）
@version 1.2
@date    2026.11.24

引脚依据 AIR8801_V0_20261117_2100.pdf 第 1～5 页。显示尺寸配置与底板供电/引脚分开。

=== 屏幕与触摸怎么选（优先级从高到低）===

  1. 调试口 PANEL,<profile>,<touch># 写进 fskv 的临时覆盖
     —— 只用于 bring-up 阶段试例外屏，重启仍生效；出厂前必须 PANEL,RESET# 清掉，
        否则整机型号（PROJECT）与实装屏会对不上。
  2. main.lua 的 PROJECT 经 core/platform_loader.lua 的 parse_model() 解析出的屏 + 触摸 + 电平
     —— 出厂整机配置，正常量产只走这一条。
  3. PROJECT 不是合法 K8801 型号 → 回退 factory_default（7 寸 1024×600 电阻屏 + TTL）并打 warn。

=== PROJECT 命名（K8801 整机型号）===

  K8801_<TTL|232>_<LCD|CTP|RTP>_<尺寸>_<宽>x<高>[_<尾段>]

    TTL / 232 : 串口电平，决定 cfg.serial.mode（ttl / rs232），界面上只出现一项
    LCD/CTP/RTP: 裸屏 / 电容触摸 / 电阻触摸，决定 cfg.touch_mode（none / capacitive / resistive）
    尺寸      : 7（当前只做 7 寸）
    宽*高     : 1024*600 / 800*480 / 1280*800
    尾段      : 当前只用 1，原样保留在型号里，程序不解释其含义；缺省按 1

  型号由 core/platform_loader.lua 的 parse_model() 解析，完整可选表见 main.lua 头部。
  裸屏（LCD）没有触摸芯片：touch_mode = "none"，boot_ui 跳过触摸初始化，
  标定项与触摸校准自动消失，其余测试项照常。
]]

-- 四档电容屏共用的 RGB 时序（实装规格为准）。
local cap_timing = {hbp = 140, hspw = 20, hfp = 160, vbp = 20, vspw = 3, vfp = 12, pclk_hz = 50000000}

-- 出厂默认：首板 QT-TPM169-7.0（7 寸 1024×600 + NS2009 四线电阻 + TTL）。
local FACTORY_DEFAULT = {panel = "1024x600", touch = "resistive", serial_mode = "ttl",
    panel_type = "RTP"}

local TOUCH_LABEL = {resistive = "电阻触摸", capacitive = "电容触摸", none = "无触摸"}
local SCREEN_LABEL = {LCD = "裸屏", CTP = "电容触摸", RTP = "电阻触摸"}

local M = {
    name = "K8801",
    baseboard = "K8801 V0",
    chip = "Air1101 / CCM4211",
    features = {other_func = true},
    ui = {show_other_func = true},
    network = {},
    panels = {
        -- K8801 当前只做 7 寸，三种分辨率都按 7 寸 RGB 屏给时序。
        ["1024x600"] = {w = 1024, h = 600, pclk_hz = 51000000, inches = 7, font = 20},
        ["800x480"] = {w = 800, h = 480, pclk_hz = 33000000, inches = 7, font = 16},
        ["1280x800"] = {w = 1280, h = 800, pclk_hz = 71000000, inches = 7, font = 24},
        -- 480×272：4.3 寸工装屏。型号尺寸段只接受整数，实物 4.3 寸统一按 4 记
        -- （见 main.lua 头部 K8801_TTL_CTP_4_480x272_1），这样 parse_model 不会打尺寸不符 warn。
        ["480x272"] = {w = 480, h = 272, pclk_hz = 15000000, inches = 4, font = 14},
        ["5in"] = {w = 800, h = 480, inches = 5, font = 16, timing = cap_timing, touch = "capacitive"},
        ["7in"] = {w = 1024, h = 600, inches = 7, font = 20, timing = cap_timing, touch = "capacitive"},
        ["9in"] = {w = 1024, h = 600, inches = 9, font = 20, timing = cap_timing, touch = "capacitive"},
        ["10in"] = {w = 1024, h = 600, inches = 10, font = 20, timing = cap_timing, touch = "capacitive"},
    },
    -- 触摸：电容 GT911 与电阻 NS2009 共用 I2C1 / WAKEUP(51) / GPIO14（RST 或 A0），按模式接一套。
    touch = {port = 1, pin_int = 51, pin_rst = 14},
    sd = {id = 1, cs = 8, power = 74, hz = 10000000, mount = "/sd"},
    buzzer = {channel = 1, pin = 65, hz = 2700, duration_ms = 180},
    -- mode 由 K8801 型号里的电平段解析后写入：ttl（收发器不贴）/ rs232（实贴，GPIO12 供电）
    serial = {id = 2, tx = 54, rx = 55, power = 12, baud = 9600, mode = "ttl"},
}

-- PROJECT 未命中时的回退值（platform_loader 读这里）
M.factory_default = FACTORY_DEFAULT

local VALID_TOUCH = {resistive = true, capacitive = true, none = true}

local function valid_pair(panel, touch)
    local profile = M.panels[panel]
    return profile and VALID_TOUCH[touch] and (not profile.touch or profile.touch == touch)
end

--[[
加载整机配置。panel / touch 由 main.lua 的 K8801 型号经 platform_loader.parse_model 解析后传入；
无效或未传时回退出厂默认。fskv 里的面板覆盖（调试口 PANEL 指令写入）优先于 PROJECT。
@param string panel 屏幕 profile 键（1024x600 / 800x480 / 1280x800，调试口可用早期 profile）
@param string touch "resistive"（NS2009）/ "capacitive"（GT911）/ "none"（裸屏，无触摸芯片）
@param table opts 型号附加信息：serial_mode（ttl / rs232）、panel_type（LCD / CTP / RTP）、
                   model（完整型号字符串）
]]
function M.load(panel, touch, opts)
    opts = opts or {}
    M.project = _G.PROJECT
    M.model = opts.model or _G.PROJECT or "K8801"
    M.panel_type = opts.panel_type or FACTORY_DEFAULT.panel_type

    if not valid_pair(panel, touch) then
        panel, touch = FACTORY_DEFAULT.panel, FACTORY_DEFAULT.touch
        M.panel_type = FACTORY_DEFAULT.panel_type
    end
    M.project_panel, M.project_touch = panel, touch

    local saved = fskv and fskv.init() and fskv.get("air8801_panel")
    local saved_panel = type(saved) == "table" and saved.panel
    local saved_touch = type(saved) == "table" and saved.touch
    if valid_pair(saved_panel, saved_touch) then
        M.panel_source = "fskv"
        if saved_panel ~= panel or saved_touch ~= touch then
            log.warn("air8801_config", "调试口面板覆盖生效，与 PROJECT 出厂配置不一致",
                saved_panel, saved_touch, "PROJECT", panel, touch, "清掉用 PANEL,RESET#")
        end
        panel, touch = saved_panel, saved_touch
    else
        M.panel_source = "project"
    end

    M.panel, M.touch_mode = panel, touch
    -- 调试口覆盖可能改掉屏型，panel_type 跟着反推，避免型号描述与实际不符
    if M.panel_source == "fskv" then
        M.panel_type = (touch == "none" and "LCD") or (touch == "capacitive" and "CTP") or "RTP"
    end

    -- 串口电平由型号的 TTL/232 段决定：单板只贴一条支路，界面因此只出现一项
    local mode = opts.serial_mode
    if mode ~= "ttl" and mode ~= "rs232" then
        if mode ~= nil then
            log.warn("air8801_config", "型号串口电平非法，按 ttl 处理", tostring(mode))
        end
        mode = "ttl"
    end
    M.serial.mode = mode
    log.info("air8801_config", "串口通道", mode,
        mode == "rs232" and "U232 实贴 · GPIO12 供电" or "J101 直出 TTL · GPIO12 保持低")

    local p = M.panels[panel]
    -- 设备型号直接显示完整型号（K8801_TTL_RTP_7_1024x600_1），产线一眼看出实装配置
    M.name = M.model
    M.screen_desc = string.format("%s %s", panel,
        SCREEN_LABEL[M.panel_type] or TOUCH_LABEL[touch] or touch)
    local params = {interface = "rgb", pin_rst = 15, w = p.w, h = p.h}
    for key, value in pairs(p.timing or cap_timing) do params[key] = value end
    if p.pclk_hz then params.pclk_hz = p.pclk_hz end
    M.hw = {
        lcd = {
            model = "lcd_display_rgb", screen_size = p.inches,
            params = params,
            font = {size = p.font},
            backlight = {pwm_ch = 3, pwm_freq = 1000, level = 20},
        },
        tp = {model = "air8801_touch", params = M.touch},
    }

    log.info("air8801_config", "面板就绪", panel, touch, p.inches .. "inch",
        "source=" .. M.panel_source, "型号=" .. tostring(M.model))
end

--- 调试口保存临时面板覆盖（fskv），重启生效
function M.save_panel(panel, touch)
    if not valid_pair(panel, touch) then
        return false, "INVALID_PANEL"
    end
    if not (fskv and fskv.init() and fskv.set("air8801_panel", {panel = panel, touch = touch})) then
        return false, "FSKV"
    end
    return true
end

--- 清掉调试口的面板覆盖，回到 PROJECT 出厂配置（出厂前必做），重启生效
function M.clear_panel()
    if not (fskv and fskv.init()) then
        return false, "FSKV"
    end
    fskv.del("air8801_panel")
    return true
end

return M
