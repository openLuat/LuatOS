--[[
@module  update
@summary FOTA 升级管理模块（libfota3，整机成品 FOTA）
@version 1.0
@date    2026.09.28
@usage
默认使用 libfota3（整机成品 FOTA，只能合宙人员根据客户提供的 IMEI 升级，客户无法自行操作）。
开机即执行检测一次，之后每 8 小时自动检测一次（异步后台执行，不阻塞开机流程）。

依赖：
  libfota3.lua（本工程 firmware/code/ 目录，整机成品 FOTA 库）
  main.lua 中的全局 PRODUCT_KEY（合宙 IoT 平台产品密钥，与 airlbs 的 project_key 不同）

服务器下发指令支持：
  {"command":"update","data":{"params":{}}}          -- 触发升级检查
]]

local update = {}

-- ==================== libfota3 ====================

local libfota3 = require("libfota3")

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
    -- 无条件打印当前版本号
    log.info("update", "===== 当前固件版本:", _G.PROJECT, _G.VERSION, "=====")

    local project_key = _G.PRODUCT_KEY
    if not is_key_valid(project_key) then
        log.warn("update", "PRODUCT_KEY 未配置真实值（当前为占位符或空），跳过 libfota3")
        return
    end

    -- config() 配置 project_key 等参数并启动 8h 定时
    libfota3.config({
        project_key = project_key,
        script_name = _G.PROJECT or "Air8204_Factory",
        script_version = _G.VERSION or "001.000.001",
        auto = true,
        interval = 28800,  -- 8 小时
        on_status = function(status, msg, percent)
            log.info("fota", status, msg, percent)
        end,
        on_confirm = function(action, info, callback)
            callback(true)
        end,
    })

    -- 开机立即检测一次
    libfota3.check_update()
    log.info("update", "libfota3 已启动（开机检测 + 每 8 小时自动检测）")
end

--[[
手动触发升级检查（服务器下发 update 命令时调用）

@usage
update.check_update()
]]
function update.check_update()
    log.info("update", "libfota3 手动触发升级检查")
    libfota3.check_update()
end

return update
