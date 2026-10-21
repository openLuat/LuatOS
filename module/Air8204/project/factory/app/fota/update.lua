--[[
@module  update
@summary FOTA 升级管理模块（libfota3，整机成品 FOTA）
@version 1.0
@date    2026.09.28
@usage
使用 libfota3（整机成品 FOTA，升级包由合宙平台按 product_key + IMEI 白名单下发）。
开机时通过 config() 写入参数并 check_update() 检测一次，
之后由 libfota3 的自动检测定时器按 8 小时周期循环（interval = 28800）。

与工作模式的关系：无关。boot.lua 在产测/出货分流之前调用 update.init()，
产测模式同样会检测升级，便于产线半成品开机即拉到最新脚本。

依赖：
  libfota3.lua（本工程 firmware/code/ 目录，整机成品 FOTA 库）
  main.lua 中的全局 PRODUCT_KEY（合宙 IoT 平台产品密钥，与 airlbs 的 project_key 不同）

关键参数：
  project_key  = main.lua 的 PRODUCT_KEY
  interval     = 28800（8 小时）
  升级包来源   = http://iot.openluat.com/api/site/turnkey_fota
]]

local update = {}

local libfota3 = require "libfota3"

-- 检测间隔：8 小时（秒）
local CHECK_INTERVAL = 28800

-- PRODUCT_KEY 有效性判定：为空或仍为占位符时视为未配置，跳过 FOTA
local PLACEHOLDER_KEY = "YOUR_PRODUCT_KEY_HERE"
local function is_key_valid(key)
    return key and key ~= "" and key ~= PLACEHOLDER_KEY
end

--[[
初始化并启动 FOTA（开机即执行，与工作模式无关）

@usage
update.init()
]]
function update.init()
    -- 无条件打印当前固件版本
    log.info("update", "===== 当前固件版本:", _G.PROJECT, _G.VERSION, "=====")

    local project_key = _G.PRODUCT_KEY
    if not is_key_valid(project_key) then
        log.warn("update", "PRODUCT_KEY 未配置真实值（当前为占位符或空），跳过 libfota3")
        return
    end

    -- 配置 FOTA 参数：PRODUCT_KEY / 脚本名 / 版本 / 自动检测间隔 8 小时
    libfota3.config({
        project_key = project_key,
        script_name = _G.PROJECT or "Air8204_Factory",
        script_version = _G.VERSION or "001.000.001",
        auto = true,
        interval = CHECK_INTERVAL,  -- 8 小时
        on_status = function(status, msg, percent)
            log.info("fota", status, msg, percent)
        end,
        on_confirm = function(action, info, callback)
            -- 无屏幕设备：下载与重启均自动确认
            callback(true)
        end,
    })

    -- 开机检测一次
    libfota3.check_update()

    log.info("update", "libfota3 已启动（开机检测一次 + 每", CHECK_INTERVAL / 3600, "小时自动检测）")
end

--[[
手动触发升级检查（需要时可调用）

@usage
update.check_update()
]]
function update.check_update()
    log.info("update", "libfota3 手动触发升级检查")
    libfota3.check_update()
end

return update
