--[[
@module  fota3
@summary FOTA 远程升级模块
@version 2.0
@date    2026.10.23
@author  马梦阳
@description
    本模块负责管理 FOTA 配置、状态跟踪和升级触发，基于 libfota3 实现：
    - request()：一站式启动升级流程
    - check_update()：手动触发检测更新
    - config()：动态修改配置

    模块内部维护一个状态机，跟踪升级全流程：
    - state=0：空闲
    - state=1：检测中
    - state=2：下载中
    - state=3：已结束（成功/失败）

@usage
    -- 在 main.lua 中 require "fota3" 即可加载运行
    require("fota3")
]]

local libfota3 = require("libfota3")
local config_storage = require("config_storage")

--============================================================
-- 常量
--============================================================

-- 合宙 IoT 平台上本项目的 project_key
local PROJECT_KEY = "T9Me8d5Y5zVjfedJROFso4viUlREz4Gq"

-- FOTA 错误码定义：将错误描述映射为数字，0=成功
local FOTA_ERROR_CODES = {
    ["升级成功"] = 0,
    ["网络连接失败"] = 1,
    ["检测失败"] = 2,
    ["无新版本"] = 3,
    ["下载失败"] = 4,
    ["升级失败"] = 5,
    ["升级包已就绪"] = 6,
    ["正在重启"] = 7,
}

--============================================================
-- 内存配置
--============================================================

local g_config = {
    auto = 1,
    period = 86400,
}

--============================================================
-- 升级状态跟踪
--============================================================

local g_state = {
    state = 0,              -- 阶段：0=空闲 1=检测中 2=下载中 3=已结束
    percent = 0,            -- 下载进度（state=2 时有效）
    fota_error_cause = nil, -- 失败时的错误码
}

--============================================================
-- 内部函数
--============================================================

-- 将错误描述转换为错误码，未知错误返回默认值 99
local function get_error_code(msg)
    if not msg then return nil end
    return FOTA_ERROR_CODES[msg] or 99
end

-- 重置升级状态，用于在升级完成后或配置变更时调用
local function reset_state()
    g_state.state = 0
    g_state.percent = 0
    g_state.fota_error_cause = nil
end

-- 应用配置，将内存配置应用到libfota3中
local function apply_config()
    libfota3.config({auto = g_config.auto == 1, interval = g_config.period})
end

-- 从配置存储中加载FOTA配置
local function load_config()
    g_config.auto = config_storage.get("fota_auto", 1)
    g_config.period = config_storage.get("fota_period", 86400)
end

--============================================================
-- on_status 回调
--============================================================

-- 处理libfota3的升级状态回调
local function on_status(status, msg, percent)
    log.info("fota3", status, msg, percent)

    if status == "boot_report" then
        g_state.state = 1
        g_state.percent = 0
        g_state.fota_error_cause = nil
    elseif status == "checking" then
        g_state.state = 1
        g_state.percent = 0
        g_state.fota_error_cause = nil
    elseif status == "new_version" then
        g_state.state = 1
        g_state.percent = 0
        g_state.fota_error_cause = nil
    elseif status == "download_start" then
        g_state.state = 2
        g_state.percent = 0
        g_state.fota_error_cause = nil
    elseif status == "downloading" then
        g_state.state = 2
        g_state.percent = percent or 0
    elseif status == "check_fail" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("检测失败")
    elseif status == "no_new_version" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("无新版本")
    elseif status == "download_fail" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("下载失败")
    elseif status == "download_done" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("升级包已就绪")
    elseif status == "rebooting" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("正在重启")
    elseif status == "network_fail" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("网络连接失败")
    elseif status == "upgrade_success" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("升级成功")
    elseif status == "upgrade_fail" then
        g_state.state = 3
        g_state.fota_error_cause = get_error_code("升级失败")
    end
end

--============================================================
-- 模块导出
--============================================================

local M = {}

--[[
@api fota3.trigger()
@summary 手动触发 FOTA 升级
]]
function M.trigger()
    reset_state()
    libfota3.check_update()
end

--[[
@api fota3.set_param(tag, value, savetoNV)
@summary 设置 FOTA 配置参数
@param string tag 配置项标识："AUTO" / "PERIOD"
@param string value 配置值
@param number savetoNV 持久化标志：0=保存（默认），1=不保存
]]
function M.set_param(tag, value, savetoNV)
    if tag == "AUTO" then
        local v = tonumber(value)
        if v == nil or (v ~= 0 and v ~= 1) then
            return nil, "ERROR"
        end
        if savetoNV ~= 1 then
            config_storage.set("fota_auto", v)
        end
        g_config.auto = v
        apply_config()
        return true
    elseif tag == "PERIOD" then
        local v = tonumber(value)
        if v == nil or v < 60 then
            return nil, "ERROR"
        end
        if savetoNV ~= 1 then
            config_storage.set("fota_period", v)
        end
        g_config.period = v
        apply_config()
        return true
    end
    return nil, "ERROR"
end

--[[
@api fota3.get_param(tag)
@summary 查询 FOTA 配置参数
@param string tag 配置项标识："AUTO" / "PERIOD"
]]
function M.get_param(tag)
    if tag == "AUTO" then
        return tostring(g_config.auto), nil
    elseif tag == "PERIOD" then
        return tostring(g_config.period), nil
    end
    return nil, "ERROR"
end

--[[
@api fota3.get_status()
@summary 查询当前 FOTA 升级状态
@return number state 升级阶段：0/1/2/3
@return number percent 下载进度百分比（state=2 时有效）
]]
function M.get_status()
    return g_state.state, g_state.percent, g_state.fota_error_cause
end

--============================================================
-- 模块加载时执行
--============================================================

-- 从 fskv 读取持久化的配置项（AUTO / PERIOD）
load_config()
-- 启动FOTA升级流程（包含时间同步 + 定时器启动）
libfota3.request({
    project_key = PROJECT_KEY,
    on_status = on_status,
    auto = (g_config.auto == 1),
    interval = g_config.period,
})

return M
