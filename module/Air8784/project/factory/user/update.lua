--[[
@module  update
@summary FOTA 升级管理模块（libfota3）
@version 1.0
@date    2026.09.28
@author  王世豪
@usage
默认 libfota3（只能合宙人员根据客户提供的IMEI升级，客户无法自行操作）。
设备首次烧录执行检测一次，之后每 8 小时自动检测一次。
与工作模式无关（产测模式下也会检测），便于产线半成品直接拉到最新脚本。

依赖：
  libfota3.lua（已放入本工程目录）

服务器下发指令支持：
  {"type":"update"}                                 -- 触发升级检查
  {"command":"update","data":{"params":{}}}         
  文本短命令 "update" / "fota"                       -- AirCloud web 端直接下发

]]

local update = {}

-- ==================== libfota3 ====================

local libfota3 = require("libfota3")

--[[
初始化并启动 FOTA（开机即执行，与工作模式无关）

@usage
update.init()
]]
function update.init()
    -- 无条件打印当前版本号
    log.info("update", "===== 当前固件版本:", _G.PROJECT, _G.VERSION, "=====")

    local project_key = _G.PRODUCT_KEY
    if not project_key or project_key == "" then
        log.warn("update", "PRODUCT_KEY 未配置，跳过 libfota3")
        return
    end

    -- request() 配置参数 + 启动 8h 定时；时间同步后检测到"首次运行"会立即触发一次检查
    libfota3.request({
        project_key = project_key,
        script_name = _G.PROJECT or "Air8784_Factory",
        script_version = _G.VERSION or "001.000.000",
        auto = true,
        interval = 28800,  -- 8小时
        on_status = function(status, msg, percent)
            log.info("fota", status, msg, percent)
        end,
        on_confirm = function(action, info, callback)
            callback(true)
        end,
    })

    -- 立即检测由 request 在时间同步后自动触发
    log.info("update", "libfota3 已启动（首次烧录检测 + 每8小时自动检测）")
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
