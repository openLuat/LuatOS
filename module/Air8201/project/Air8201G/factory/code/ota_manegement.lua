--[[
@module  ota_manegement
@summary OTA 远程升级管理（基于 libfota3 + iot.openluat.com 平台）
@version 1.0
@date    2026.07.02
@description
    使用合宙官方 IoT 平台（iot.openluat.com）进行远程固件升级。
    基于 libfota3 库实现，支持自动定时检测、进度反馈。

    触发机制：
      1. 开机首次：自动检测升级
      2. 周期触发：每 12 小时自动检测一次

    依赖：
      - 全局变量 PRODUCT_KEY（main.lua 中配置）
      - libfota3 库
      - global_config 模块（需先初始化 fskv）

@usage
    local ota_manegement = require "ota_manegement"
    ota_manegement.init()
]]

local libfota3 = require "libfota3"

local ota_manegement = {}

-- ========== 常量（文件开头） ==========
-- 自动检测间隔：12 小时（秒）
local AUTO_INTERVAL = 12 * 3600

-- ========== 内部函数 ==========

-- libfota3 状态回调：统一 INFO 级别日志
local function on_status(status, msg, percent)
    if percent then
        log.info("OTA", "[" .. status .. "] " .. tostring(msg) .. " " .. percent .. "%")
    else
        log.info("OTA", "[" .. status .. "] " .. tostring(msg))
    end
end

-- libfota3 确认回调：工厂固件无屏幕，自动确认下载和重启
local function on_confirm(action, info, callback)
    log.info("OTA", "自动确认: action=" .. tostring(action))
    callback(true)
end

-- ========== 公开接口 ==========

--[[
@api ota_manegement.init()
@summary 初始化 OTA 管理模块
@return boolean 始终返回 true
@description
    流程：
      1. 检查 PRODUCT_KEY 是否配置
      2. 调用 libfota3.request() 启动自动检测（开机首次 + 每 12 小时）
    前置条件：global_config.init() 已调用（确保 fskv 已初始化）
]]
function ota_manegement.init()
    log.info("OTA", "初始化 OTA 管理模块")

    -- 1. 检查 PRODUCT_KEY
    local project_key = _G.PRODUCT_KEY
    if not project_key or project_key == "" then
        log.info("OTA", "PRODUCT_KEY 未配置，OTA 功能不可用")
        return true
    end

    -- 2. 启动 libfota3
    libfota3.request({
        project_key = project_key,
        auto = true,
        interval = AUTO_INTERVAL,
        on_status = on_status,
        on_confirm = on_confirm
    })

    log.info("OTA", "OTA 管理模块 已启动")
    return true
end

return ota_manegement
