--[[
@module  platform_loader
@summary PROJECT 解析 → 出厂整机配置加载 → 板级输出上电（Air8801 factory 配置驱动入口）
@version 1.1
@date    2026.11.24

require 即执行，顺序固定：

  1. 读 main.lua 的 PROJECT → parse_model() 解析 → 得到 { panel, touch, serial_mode, ... }
  2. air8801_config.load(panel, touch, model) → hw / features / ui 就绪 → _G.project_config
  3. 协程里给板级输出（LCD_3V3 / RS232_EN / SD_EN / 蜂鸣器）置低，完成后发 POWER_ON_DONE

PROJECT 是唯一的编译时变量：换屏 / 换触摸 / 换串口电平只改 main.lua 一行。
新增同尺寸异分辨率机型 = 在 air8801_config.panels 加一份 profile，型号字符串自动解析，不用改本文件。

=== PROJECT → 屏 / 触摸 / 串口（K8801 整机型号）===

  K8801_<TTL|232>_<LCD|CTP|RTP>_<尺寸>_<宽>x<高>[_<尾段>]

  例：K8801_TTL_RTP_7_1024x600_1
      = K8801 · TTL 电平 · 电阻触摸 · 7 寸 · 1024×600 · 尾段 1

  各段怎么用：
    电平   TTL → cfg.serial.mode = "ttl"  ；232 → "rs232"（GPIO12 供电）
    屏型   LCD → touch = "none"（裸屏，无触摸芯片）；CTP → "capacitive"；RTP → "resistive"
    尺寸   只用于校验，与分辨率 profile 的 inches 不一致时只打 warn 不阻断
    宽*高  直接组合成 panels 的键（1024x600 / 800x480 / 1280x800），宽高之间也接受 x
    尾段   当前只用 1，原样保留在型号里，程序不解释其含义；省略按 1

  完整可选型号表见 main.lua 头部。语法合法、且分辨率在 panels 里的型号都能跑，
  所以新增同尺寸异分辨率机型不必改这张映射，只在 panels 加 profile 即可。
  旧命名（Air8801_7inch_1024x600_Resistive_000_V000 等）回退出厂默认屏并打 warn。
]]
local cfg = require "air8801_config"
local board = require "air8801_board"

-- 型号语法：K8801_<TTL|232>_<LCD|CTP|RTP>_<尺寸>_<宽>x<高>[_1]
-- 段分隔符统一用下划线 `_`，同时兼容老型号的连字符 `-`；宽高之间 x 与 * 都收
-- 尾段可省略（等同 _1），不解释其含义
-- 解析方式：先把 `-` 归一成 `_`，再用 gmatch 切段、逐段白名单校验。
-- 不用一条长 pattern 匹配整串——那种失败只能报「语法不符」，说不清是哪一段错。
local SERIAL_BY_LEVEL = {TTL = "ttl", ["232"] = "rs232"}
local TOUCH_BY_TYPE = {LCD = "none", CTP = "capacitive", RTP = "resistive"}

-- 按分隔符切段：K8801_232_RTP_4_480x272_1 -> {"K8801","232","RTP","4","480x272","1"}
local function split_model(name)
    local segs = {}
    local norm = name:gsub("%-", "_")
    for seg in norm:gmatch("[^_]+") do
        segs[#segs + 1] = seg
    end
    return segs
end

--[[
解析 K8801 型号。语法不对、或分辨率在 panels 里没有对应 profile 时返回 nil + 原因（由调用方回退）。
@param string name main.lua 的 PROJECT
@return table|nil {model, panel, touch, panel_type, inches, serial_mode}, string|nil 失败原因
]]
local function parse_model(name)
    if type(name) ~= "string" then return nil, "PROJECT 不是字符串" end
    local segs = split_model(name)
    if #segs < 5 then
        return nil, "段数不足（" .. #segs .. " 段），应为 K8801_<TTL|232>_<LCD|CTP|RTP>_<寸>_<宽>x<高>"
    end
    if segs[1] ~= "K8801" then
        return nil, "首段不是 K8801，实为 " .. tostring(segs[1])
    end
    local serial_mode = SERIAL_BY_LEVEL[segs[2]]
    if not serial_mode then
        return nil, "串口段只认 TTL 或 232，实为 " .. tostring(segs[2])
    end
    local touch = TOUCH_BY_TYPE[segs[3]]
    if not touch then
        return nil, "触摸段只认 LCD/CTP/RTP，实为 " .. tostring(segs[3])
    end
    local inches = tonumber(segs[4])
    if not inches then
        return nil, "尺寸段不是整数，实为 " .. tostring(segs[4])
    end
    local w, h = segs[5]:match("^(%d+)[x%*](%d+)$")
    if not w then
        return nil, "分辨率段应形如 480x272，实为 " .. tostring(segs[5])
    end
    local panel = w .. "x" .. h
    if not cfg.panels[panel] then
        return nil, "panels 里没有 " .. panel .. " 的 profile"
    end
    return {
        model = name,
        panel = panel,
        touch = touch,
        panel_type = segs[3],
        inches = inches,
        serial_mode = serial_mode,
    }
end

-- 静态登记 lcd_common 依赖，供 LuaTools 收集。
local function display_modules()
    require "lcd_display_rgb"
    require "air8801_touch"
end

--[[
PROJECT → 整机配置。型号不合法时回退出厂默认屏并打 warn：
不阻断（黑屏更难定位），但日志会明确写出「型号不符」与正确示例。
@param string name main.lua 的 PROJECT
@return table parse_model 的结果（回退时也补齐全部字段，调用方不用判空）
]]
local function resolve_project(name)
    local hit, reason = parse_model(name)
    if hit then
        local profile = cfg.panels[hit.panel]
        if profile.inches and profile.inches ~= hit.inches then
            log.warn("platform_loader", "型号尺寸与 profile 不符，按 profile 跑",
                hit.inches .. "inch", hit.panel, profile.inches .. "inch")
        end
        return hit
    end

    local d = cfg.factory_default
    local why = (type(name) == "string" and name:find("^Air8801"))
        and "PROJECT 是旧 Air8801 命名，请改成 K8801 型号"
        or "PROJECT 不是合法 K8801 型号"
    log.warn("platform_loader", why, tostring(name), reason or "", "回退出厂默认屏",
        d.panel, d.touch, "示例 K8801_TTL_RTP_7_1024x600_1")
    return {
        model = name or "--",
        panel = d.panel, touch = d.touch, panel_type = d.panel_type,
        inches = cfg.panels[d.panel].inches,
        serial_mode = d.serial_mode,
    }
end

_G.is_pc = rtos.bsp() == "PC"
_G.__power_on_done = false

local model = resolve_project(_G.PROJECT)
cfg.load(model.panel, model.touch, model)
_G.project_config = cfg
_G.model_str = _G.is_pc and "PC" or cfg.chip

log.info("platform_loader", "型号解析", cfg.model, cfg.panel_type,
    "电平=" .. cfg.serial.mode)

log.info("platform_loader", "整机装配", cfg.project, cfg.panel, cfg.touch_mode,
    cfg.panel_source == "fskv" and "面板来源=fskv调试覆盖" or "面板来源=PROJECT")

sys.taskInit(function()
    if _G.is_pc or (hmeta and hmeta.chip and hmeta.chip() == "CCM4211") then
        local ok, ready = pcall(board.init_outputs)
        if ok and ready then
            sys.wait(50) -- LCD_3V3 随 VBAT 上电。
            _G.__power_on_done = true
        else
            log.error("platform_loader", "板级输出初始化失败", ready)
        end
    else
        log.error("platform_loader", "Air8801 需要 CCM4211 底包")
    end
    sys.publish("POWER_ON_DONE")
end)
