--[[
@module  settings_storage_app
@summary 存储业务逻辑层
@version 1.0
@date    2026.04.01
@author  LuatOS
]]

-- ==================== 存储信息 ====================
local storage_info = {
    total = "--",
    used = "--",
    free = "--",
    used_percent = 0
}

--[[
格式化存储大小（字节转可读格式）
@param size 大小（字节）
@return string 格式化后的字符串
]]
local function format_size(size)
    if size == nil or type(size) ~= "number" or size < 0 then
        return "--"
    end
    
    local units = {"B", "KB", "MB", "GB"}
    local unit_index = 1
    
    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end
    
    return string.format("%.2f %s", size, units[unit_index])
end

--[[
获取存储信息
@return table 存储信息表
]]
local function get_storage_info()
    -- PC模拟器使用模拟数据
    if rtos.bsp() == "PC" then
        -- 总容量 1GB
        local total_bytes = 1024 * 1024 * 1024

        -- 新方案：直接生成 1~99 的百分比
        local percent = math.random(1, 99)

        -- 整数运算，无浮点、无BUG、无nil
        local used_bytes = total_bytes * (percent / 100.0)
        local free_bytes = total_bytes - used_bytes

        -- 赋值
        storage_info.total = format_size(total_bytes)
        storage_info.used = format_size(used_bytes)
        storage_info.free = format_size(free_bytes)
        storage_info.used_percent = percent

        -- 日志
        log.info("settings_storage_app", "PC模拟器模拟存储数据",
            "used:", storage_info.used,
            "free:", storage_info.free,
            "percent:", percent .. "%"
        )

        return storage_info
    end

    -- 尝试获取文件系统信息
    -- io.fsstat 返回值: success, total_blocks, used_blocks, block_size, fs_type
    local ret, success, total_blocks, used_blocks, block_size = pcall(io.fsstat, "/")
    
    log.info("settings_storage_app", "获取存储信息", "ret:", ret, "success:", success, "total_blocks:", total_blocks, "used_blocks:", used_blocks, "block_size:", block_size)

    if ret and success == true and total_blocks and used_blocks and block_size then
        local total_bytes = total_blocks * block_size
        local used_bytes = used_blocks * block_size
        local free_bytes = total_bytes - used_bytes
        
        storage_info.total = format_size(total_bytes)
        storage_info.used = format_size(used_bytes)
        storage_info.free = format_size(free_bytes)
        storage_info.used_percent = math.tointeger(math.floor(used_bytes * 100 / total_bytes))
    else
        -- 如果获取失败，使用模拟数据或默认值
        storage_info.total = "--"
        storage_info.used = "--"
        storage_info.free = "--"
        storage_info.used_percent = 0
        log.warn("settings_storage_app", "获取存储信息失败")
    end
    
    return storage_info
end

-- ==================== 事件订阅 ====================

-- 存储信息查询处理函数
local function storage_info_get_handler()
    local info = get_storage_info()
    sys.publish("STORAGE_INFO", info)
    log.info("settings_storage_app", "上报存储信息", "total:", info.total, "used:", info.used, "free:", info.free, "percent:", info.used_percent)
end

-- 订阅存储信息查询事件
sys.subscribe("STORAGE_GET_INFO", storage_info_get_handler)

log.info("settings_storage_app", "模块加载完成")
