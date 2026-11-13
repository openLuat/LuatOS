--[[
@module  platform_loader
@summary 项目配置加载器（PROJECT → 配置文件 → _G.project_config）
@version 1.0
@date    2026.11.13

=== 执行流程 ===

require 即执行，顺序：
  1. 编译清单：包进永不调用的 _compile_manifest()，仅供编译系统文本扫描打包，运行时不执行
  2. PROJECT 映射：长名 "NS2009_RESISTIVE_TOUCH_1024_600" → 配置文件名 "ns2009_1024_600"
  3. 配置加载：require(cfg_name) → 返回配置 table → 存入 _G.project_config
  4. 对外提供 M.get() / M.apply_touch_pins() / M.power_on() 供 main.lua 编排使用

=== 关键设计 ===

- PROJECT 是唯一编译时变量：换屏幕/分辨率只改 main.lua 的 PROJECT 一行，
  其余全部由本加载器 + config/*.lua 配置驱动（参考 factory 的配置驱动架构）。

- 三级回退（容错）：
  第一级 PROJECT_MAP 命中 → require 配置文件 → 返回 table；
  第二级 require 返回非 table → 回退 800x480 配置；
  第三级 PROJECT_MAP 未命中 → 回退 800x480 配置。
  回退后日志会打 warn，便于定位 PROJECT 填错。

- require 编译清单：不是给运行时用的，是给编译系统文本扫描用的。
  动态 require（变量名 cfg_name）扫不到 config/*.lua，必须在此静态列出，
  编译系统才能把三份配置都打包进固件；包进永不调用的函数后运行时不执行。
]]

-- ==================== 编译清单（编译系统文本扫描，运行时不执行） ====================
-- 新增屏幕分辨率配置文件时，在此加一行 require，编译系统会自动打包对应 .lua。
local function _compile_manifest()
    require("ns2009_800_480")       -- 800x480（宏显伟业 0700A001 / HX8264）
    require("ns2009_1024_600")      -- 1024x600
    require("ns2009_480_272")       -- 480x272 小屏
end

-- ==================== 1. PROJECT 长名 → 配置文件名映射 ====================
-- 配置文件名格式: ns2009_{宽}x{高}
local PROJECT_MAP = {
    ["NS2009_RESISTIVE_TOUCH_800_480"]  = "ns2009_800_480",
    ["NS2009_RESISTIVE_TOUCH_1024_600"] = "ns2009_1024_600",
    ["NS2009_RESISTIVE_TOUCH_480_272"]  = "ns2009_480_272",
}

-- ==================== 2. 加载项目配置 ====================
local function load_config(project)
    local cfg_name = PROJECT_MAP[project]
    local cfg
    if cfg_name then
        cfg = require(cfg_name)
    end
    if type(cfg) ~= "table" then
        if cfg_name then
            log.warn("platform_loader", "配置文件加载失败:", cfg_name, "回退 800x480")
        else
            log.warn("platform_loader", "未找到 PROJECT 映射:", tostring(project), "回退 800x480")
        end
        cfg = require("ns2009_800_480")
    end
    _G.project_config = cfg
    log.info("platform_loader", "配置加载成功", tostring(project),
        cfg.lcd.w .. "x" .. cfg.lcd.h,
        "bus_speed=" .. tostring(cfg.lcd.bus_speed),
        "cal_kv=" .. tostring(cfg.touch.cal_kv),
        "font_size=" .. tostring(cfg.ui.font_size))
    return cfg
end

-- require 即执行：加载配置到 _G.project_config（后续所有模块通过它读参数）
local config = load_config(_G.PROJECT)

local M = {}

--[[取当前项目配置表（main.lua 用；也可直接读 _G.project_config）]]
function M.get()
    return _G.project_config
end

--[[I2C1 触摸引脚显式复用（CFG.touch.pins），避免 pin 默认功能不是 I2C1]]
function M.apply_touch_pins(cfg)
    if not (pins and pins.setup) then
        log.info("platform_loader", "固件没有 pins 库，跳过触摸引脚复用")
        return
    end
    for _, p in ipairs((cfg.touch and cfg.touch.pins) or {}) do
        local ok, ret = pcall(pins.setup, p[1], p[2])
        log.info("platform_loader", "pins.setup", "PIN" .. p[1], p[2], ok and ret or "failed")
    end
end

--[[底板上电时序（真机必须；PC 无 gpio 自动跳过）。含 sys.wait，须在协程里调用。]]
function M.power_on(cfg)
    if not (gpio and gpio.setup and gpio.set) then
        log.info("platform_loader", "无 gpio 库（PC 模拟器），跳过上电时序")
        return
    end
    for _, step in ipairs(cfg.power_on or {}) do
        gpio.setup(step.pin, step.dir or 0)
        gpio.set(step.pin, step.level or 0)
        log.info("platform_loader", "供电轨", "GPIO" .. step.pin, "=" .. (step.level or 0))
        if step.delay and step.delay > 0 then
            sys.wait(step.delay)
        end
    end
end

return M
