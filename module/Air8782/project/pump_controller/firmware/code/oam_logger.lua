--[[
@module  oam_logger
@summary 运维日志集中出口
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.5（必须启用运维日志）与嵌入式软件总体设计.md 4.16：
统一封装 excloud.mtn_log，供各业务模块记录运维日志，便于远程运维与故障诊断。
本模块有对外接口，末尾 return M。
]]

local excloud    = require("excloud")
local config_app = require("config_app")

local M = {}

--[[
记录一条运维日志
@param tag string 日志标签（模块名）
@param ... 可变参数，日志内容
]]
function M.log(tag, ...)
    if not config_app.mtn_log_enabled then
        return
    end
    excloud.mtn_log(tag, ...)
end

return M
