--[[
@module  platform_loader
@summary 硬件配置加载器：PROJECT 字符串 → 板级配置文件 → _G.project_config
@version 1.1
@date    2026.10.15
@usage
main.lua 设好 PROJECT 后 require 本模块并调用 load()，
之后全工程通过 _G.project_config 取硬件参数。

新增板型/屏幕只需要两步：
1. 在本目录新增 config_xxx.lua；
2. 在下面的 CONFIGS 表里加一行静态 require（必须静态，保证被打包）。
]]

-- 用静态 require 列出所有板级配置（烧录合并器只跟踪静态引用）
local CONFIGS = {
    EVB_Air8101B_5inch_800x480_000   = require "config_5i_800x480",
    EVB_Air8101B_10inch_1024x600_000 = require "config_10i_1024x600",
    -- 待补：EVB_Air8101B_7inch_1024x600_000 = require "config_7i_1024x600",
    -- 待补：EVB_Air8101B_9inch_1024x600_000 = require "config_9i_1024x600",
}

local function load()
    local project = _G.PROJECT
    local cfg = CONFIGS[project]
    if not cfg then
        log.error("platform_loader", "未登记的 PROJECT:", tostring(project))
        return false
    end

    _G.project_config = cfg
    log.info("platform_loader", "PROJECT:", project,
        "| chip:", cfg.chip, "| baseboard:", cfg.baseboard, "| lcd:", cfg.hw.lcd.model)
    return true
end

return { load = load, CONFIGS = CONFIGS }
