--[[
@module  task_runtime
@summary 读取持久任务并确定本次启动的音频模式
@version 2.0
@date    2026.09.29
@author  王世豪
@usage
协同配置版本：运行模式独立于主动任务保存，删除任务不改变模式。
首次无配置时启动单 SIP；cc 为独立蜂窝电话，phone 为 SIP_CC。
跨模式保存后空闲重启，能力检查由 aircloud_settings 统一处理。
]]
assert(fskv and fskv.init(), "fskv unavailable")
local settings = require "aircloud_settings"
local saved = settings.record
if type(saved) ~= "table" then saved = {revision="0", boot_count=0} end
if saved.runtime_mode ~= "single" and saved.runtime_mode ~= "phone" and saved.runtime_mode ~= "cc" then
    saved.runtime_mode = type(saved.task)=="table" and saved.task.mode == "phone" and "phone" or "single"
    assert(fskv.set("sip_task_v1", saved), "mode migration storage failed")
end
local M = {active = saved.runtime_mode}
if settings.single_only or rtos.bsp() == "PC" then
    M.active = "single"
    M.switchable = false -- 明确选择单 SIP 时，不允许网页切换到其他音频分支。
    log.info("task_runtime", "boot mode", M.active, rtos.bsp() == "PC" and "PC direct audio" or "Air1103 single SIP")
    return M
end
M.switchable = settings.switchable -- 旧任务协议的 single/phone 切换能力。
log.info("task_runtime", "boot mode", M.active)
return M
