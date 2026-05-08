--[[
@module  settings_storage_app
@summary 存储业务逻辑层
@version 1.0
@date    2026.04.01
@author  江访
@usage
本模块为存储业务逻辑层，通过 io.fsstat 获取文件系统容量/已用/可用空间信息并上报。
]]
-- naming: fn(2-5char), var(2-4char)

-- ==================== 存储信息 ====================
local si = {
    total = "--",
    used = "--",
    free = "--",
    used_percent = 0
}

--[[
@function format_size
@summary 格式化存储大小（字节转可读格式）
@param size 大小（字节）
@return string 格式化后的字符串
]]
local function fs(sz)
    if sz == nil or type(sz) ~= "number" or sz < 0 then
        return "--"
    end

    local us = {"B", "KB", "MB", "GB"}
    local ui = 1

    while sz >= 1024 and ui < #us do
        sz = sz / 1024
        ui = ui + 1
    end

    return string.format("%.2f %s", sz, us[ui])
end

--[[
@function get_storage_info
@summary 获取文件系统存储信息（PC 模拟器返回模拟数据）
@return table 存储信息表
]]
local function gsi()
    -- PC模拟器使用模拟数据
    if _G.model_str:find("PC") then
        local tb = 1024 * 1024 * 1024

        -- 新方案：直接生成 1~99 的百分比
        local pct = math.random(1, 99)

        -- 整数运算，无浮点、无BUG、无nil
        local ub = tb * (pct / 100.0)
        local fb = tb - ub

        si.total = fs(tb)
        si.used = fs(ub)
        si.free = fs(fb)
        si.used_percent = pct

        log.info("sstg", "PC模拟器模拟存储数据",
            "used:", si.used,
            "free:", si.free,
            "percent:", pct .. "%"
        )

        return si
    end

    -- 尝试获取文件系统信息
    -- io.fsstat 返回值: success, total_blocks, used_blocks, block_size, fs_type
    local r, ok, tbk, ubk, bsz = pcall(io.fsstat, "/")

    log.info("sstg", "获取存储信息", "ret:", r, "success:", ok, "total_blocks:", tbk, "used_blocks:", ubk, "block_size:", bsz)

    if r and ok == true and tbk and ubk and bsz then
        local tb = tbk * bsz
        local ub = ubk * bsz
        local fb = tb - ub

        si.total = fs(tb)
        si.used = fs(ub)
        si.free = fs(fb)
        si.used_percent = math.tointeger(math.floor(ub * 100 / tb))
    else
        si.total = "--"
        si.used = "--"
        si.free = "--"
        si.used_percent = 0
        log.warn("sstg", "获取存储信息失败")
    end

    return si
end

-- ==================== 事件订阅 ====================

local function sih()
    local info = gsi()
    sys.publish("STORAGE_INFO", info)
    log.info("sstg", "上报存储信息", "total:", info.total, "used:", info.used, "free:", info.free, "percent:", info.used_percent)
end

-- 订阅存储信息查询事件
sys.subscribe("STORAGE_GET_INFO", sih)
