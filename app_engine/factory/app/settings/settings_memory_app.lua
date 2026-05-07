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
local function get_memory_info()
    local info = {
        sys = { total = 0, used = 0, max = 0 },
        vm = { total = 0, used = 0, max = 0 },
        psram = { total = 0, used = 0, max = 0 }
    }

    -- 获取系统内存信息 (type = "sys")
    local ret1, total1, used1, max1 = pcall(rtos.meminfo, "sys")
    if ret1 then
        info.sys.total = total1 or 0
        info.sys.used = used1 or 0
        info.sys.max = max1 or 0
    end

    -- 获取虚拟机内存信息 (type = "lua")
    local ret2, total2, used2, max2 = pcall(rtos.meminfo, "lua")
    if ret2 then
        info.vm.total = total2 or 0
        info.vm.used = used2 or 0
        info.vm.max = max2 or 0
    end

    -- 获取PSRAM内存信息 (type = "psram")
    local ret3, total3, used3, max3 = pcall(rtos.meminfo, "psram")
    if ret3 then
        info.psram.total = total3 or 0
        info.psram.used = used3 or 0
        info.psram.max = max3 or 0
    end

    return info
end


--[[
@function memory_info_get_handler
@summary 处理内存信息查询请求，获取并上报内存信息
]]
local function memory_info_get_handler()
    local info = get_memory_info()
    sys.publish("MEMORY_INFO", info)
    log.info("settings_memory_app", "上报内存信息")
end

-- 订阅内存信息查询事件
sys.subscribe("MEMORY_INFO_GET", memory_info_get_handler)
