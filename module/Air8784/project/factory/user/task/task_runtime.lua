--[[
@module  task_runtime
@summary 读取持久任务并确定本次启动的音频模式
@version 2.0
@date    2026.09.29
@author  王世豪
@usage
协同配置版本：运行模式独立于主动任务保存，删除任务不改变模式。
首次无任务时启动SIP_CC。需要cc.setBridge和rtos.reboot才允许网页跨模式切换。
固件缺少路由选择时仅提供phone模式，避免把CC音频错误接到单SIP。
]]
assert(fskv and fskv.init(), "fskv unavailable")
local saved = fskv.get("sip_task_v1")
if type(saved) ~= "table" then saved = {revision="0", boot_count=0} end
if saved.runtime_mode ~= "single" and saved.runtime_mode ~= "phone" then
    saved.runtime_mode = saved.task and saved.task.mode ~= "phone" and "single" or "phone"
    assert(fskv.set("sip_task_v1", saved), "mode migration storage failed")
end
local M = {active = "phone"}
M.switchable = cc and type(cc.setBridge) == "function" and rtos and type(rtos.reboot) == "function" or false
if M.switchable and saved.runtime_mode == "single" then
    M.active = "single"
end
if not M.switchable then
    log.warn("task_runtime", "firmware lacks cc.setBridge/rtos.reboot; only phone mode available")
end
log.info("task_runtime", "boot mode", M.active)
return M
