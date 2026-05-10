-- nconv: var2-4 fn2-5 tag-short
--[[
@module  settings_memory_app
@summary 内存信息业务逻辑层
@version 1.0
@date    2026.04.01
@author  江访
@usage
本模块为内存信息业务逻辑层，通过 rtos.meminfo 获取系统/Lua VM/PSRAM 内存信息并上报。
]]
--[[
@function get_memory_info
@summary 获取系统/Lua VM/PSRAM 内存信息
@return table 内存信息表
]]
local function gmi()
    local inf = {
        sys = { total = 0, used = 0, max = 0 },
        vm = { total = 0, used = 0, max = 0 },
        psram = { total = 0, used = 0, max = 0 }
    }
    -- 获取系统内存信息 (type = "sys")
    local rok1, t1, u1, x1 = pcall(rtos.meminfo, "sys")
    if rok1 then
        inf.sys.total = t1 or 0
        inf.sys.used = u1 or 0
        inf.sys.max = x1 or 0
    end
    -- 获取虚拟机内存信息 (type = "lua")
    local rok2, t2, u2, x2 = pcall(rtos.meminfo, "lua")
    if rok2 then
        inf.vm.total = t2 or 0
        inf.vm.used = u2 or 0
        inf.vm.max = x2 or 0
    end
    -- 获取PSRAM内存信息 (type = "psram")
    local rok3, t3, u3, x3 = pcall(rtos.meminfo, "psram")
    if rok3 then
        inf.psram.total = t3 or 0
        inf.psram.used = u3 or 0
        inf.psram.max = x3 or 0
    end
    return inf
end

--[[
@function memory_info_get_handler
@summary 处理内存信息查询请求，获取并上报内存信息
]]
local function migh()
    local inf = gmi()
    sys.publish("MEMORY_INFO", inf)
    log.info("sma", "上报内存信息")
end

-- 订阅内存信息查询事件
sys.subscribe("MEMORY_INFO_GET", migh)
