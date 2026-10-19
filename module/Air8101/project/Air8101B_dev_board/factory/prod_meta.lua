--[[
@module  prod_meta
@summary 产测元数据（工业模组型号 PROD / 硬件版本 PCB）的写入与回读
@version 1.0
@date    2026.10.15
@usage
产测阶段写入，用户模式启动时打印：
    local prodmeta = require "prod_meta"
    prodmeta.set("PROD", "Air8101B")
    prodmeta.dump()
当前实现落在 fskv（重烧脚本固件不丢）；若后续确认 Air8101 平台支持 OTP 读写，
只需在本模块内部切换到 OTP，业务侧接口保持不变。
命名说明：不能叫 prodmeta.lua —— LuatOS 扩展库里有同名文件（script/libs/prodmeta.lua）。
]]

local M = {}

local NS = "meta_"   -- fskv key 前缀，避免与业务 key 冲突

function M.set(key, value)
    if value == nil or value == "" then
        return false
    end
    fskv.set(NS .. key, value)
    return M.get(key) == value
end

function M.get(key)
    return fskv.get(NS .. key)
end

function M.dump()
    log.info("prodmeta", "PROD:", tostring(M.get("PROD")), "PCB:", tostring(M.get("PCB")))
end

return M
