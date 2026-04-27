--[[
@module  settings_memory_app
@summary 内存信息业务逻辑层
@version 1.0
@date    2026.04.01
@author  LuatOS
]]

-- 导入 excloud 库
local excloud = require("excloud")

--[[
获取内存信息
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

-- ==================== AirCloud 内存信息上报 ====================

--[[
内存信息字段 ID 定义 (1030-1038)
1030 - 系统总内存大小
1031 - 系统当前已使用内存大小
1032 - 系统历史最高已使用内存大小
1033 - Lua 虚拟机总内存大小
1034 - Lua 虚拟机当前已使用内存大小
1035 - Lua 虚拟机历史最高已使用内存大小
1036 - PSRAM 总内存大小
1037 - PSRAM 当前已使用内存大小
1038 - PSRAM 历史最高已使用内存大小
]]
local MEMORY_FIELD_IDS = {
    SYS_TOTAL = 1030,
    SYS_USED = 1031,
    SYS_MAX = 1032,
    VM_TOTAL = 1033,
    VM_USED = 1034,
    VM_MAX = 1035,
    PSRAM_TOTAL = 1036,
    PSRAM_USED = 1037,
    PSRAM_MAX = 1038
}

--[[
上报内存信息到 AirCloud 平台
使用自定义字段 ID (1030-1038)
]]
local function report_memory_to_aircloud()
    local info = get_memory_info()
    
    -- 构建 TLV 数据列表
    local tlv_list = {
        -- 系统内存信息
        { field_meaning = MEMORY_FIELD_IDS.SYS_TOTAL, data_type = excloud.DATA_TYPES.INTEGER, value = info.sys.total },
        { field_meaning = MEMORY_FIELD_IDS.SYS_USED, data_type = excloud.DATA_TYPES.INTEGER, value = info.sys.used },
        { field_meaning = MEMORY_FIELD_IDS.SYS_MAX, data_type = excloud.DATA_TYPES.INTEGER, value = info.sys.max },
        -- Lua 虚拟机内存信息
        { field_meaning = MEMORY_FIELD_IDS.VM_TOTAL, data_type = excloud.DATA_TYPES.INTEGER, value = info.vm.total },
        { field_meaning = MEMORY_FIELD_IDS.VM_USED, data_type = excloud.DATA_TYPES.INTEGER, value = info.vm.used },
        { field_meaning = MEMORY_FIELD_IDS.VM_MAX, data_type = excloud.DATA_TYPES.INTEGER, value = info.vm.max },
        -- PSRAM 内存信息
        { field_meaning = MEMORY_FIELD_IDS.PSRAM_TOTAL, data_type = excloud.DATA_TYPES.INTEGER, value = info.psram.total },
        { field_meaning = MEMORY_FIELD_IDS.PSRAM_USED, data_type = excloud.DATA_TYPES.INTEGER, value = info.psram.used },
        { field_meaning = MEMORY_FIELD_IDS.PSRAM_MAX, data_type = excloud.DATA_TYPES.INTEGER, value = info.psram.max }
    }
    
    -- 发布到 AirCloud 上报队列
    sys.publish("AIRCLOUD_REPORT_DATA", tlv_list)
    log.info("settings_memory_app", "内存信息已加入 AirCloud 上报队列")
end

-- ==================== 事件订阅 ====================

-- 内存信息查询处理函数
local function memory_info_get_handler()
    local info = get_memory_info()
    sys.publish("MEMORY_INFO", info)
    log.info("settings_memory_app", "上报内存信息")
end

-- 订阅内存信息查询事件
sys.subscribe("MEMORY_INFO_GET", memory_info_get_handler)

-- AirCloud 连接成功后延迟上报内存信息的任务函数
local function aircloud_connected_task()
    sys.wait(2000)
    report_memory_to_aircloud()
end

-- AirCloud 连接成功事件处理函数
local function aircloud_connected_handler()
    log.info("settings_memory_app", "AirCloud 连接成功，准备上报内存信息")
    -- 延迟 2 秒上报，确保连接完全就绪
    sys.taskInit(aircloud_connected_task)
end

-- 订阅 AirCloud 连接成功事件，只在连接成功后上报一次内存信息
sys.subscribe("aircloud_connected", aircloud_connected_handler)

log.info("settings_memory_app", "模块加载完成")
