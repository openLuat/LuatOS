--[[
@module  app_devsel
@summary 配件板选择：当前用温湿度还是空气质量（存 fskv，切换后重启生效）
@version 1.0
@date    2026.10.16
@usage
    local devsel = require "app_devsel"
    devsel.get()            -- "sht30" / "voc"
    devsel.name()           -- "温湿度" / "空气质量"
    devsel.is_active("voc") -- 本页/本模块是否当前启用
    devsel.other()          -- 另一个类型：id, 显示名（给"改用 XX"按钮用）
    devsel.set("voc")       -- 写 fskv 并重启生效

设计
1. 现场一次只接一块配件板（温湿度 or 空气质量），所以开机**只启动选中的那一个**：
   没插的那块完全不初始化 —— 不探测、不占总线，也就不会打出 not-found 那种"像坏了"的日志；
2. 选择存 fskv（键 sensor_type，重烧脚本不丢），没有记录时默认 "sht30"（温湿度）；
3. set() 之后需要重启才生效：重启能保证旧的采集 task 和总线状态不残留，最简单也最稳；
   界面上切换后黑屏 2~3 秒属正常。
]]

local M = {}

local KEY = "sensor_type"
local DEFAULT = "voc"

-- 可选配件板：id 存 fskv，name 给界面用
-- 2026-10-19：温湿度改用 485 传感器（temp_hum），板载 SHT30 不再作为配件板选项。
M.TYPES = {
    { id = "voc", name = "空气质量" },
}

local function find(id)
    for _, t in ipairs(M.TYPES) do
        if t.id == id then return t end
    end
end

--- 当前配件板类型（缺省或值非法都回落默认）
function M.get()
    local id = fskv.get(KEY)
    if not id or not find(id) then
        return DEFAULT
    end
    return id
end

--- 当前配件板显示名
function M.name(id)
    local t = find(id or M.get())
    return t and t.name or "未知"
end

--- 指定类型是否是当前启用的（页面用来判断"本页未启用"）
function M.is_active(id)
    return M.get() == id
end

function M.other()
    local cur = M.get()
    for _, t in ipairs(M.TYPES) do
        if t.id ~= cur then return t.id, t.name end
    end
    return nil, nil
end

function M.set(id)
    if not find(id) then
        log.error("app_devsel", "非法配件板类型:", tostring(id))
        return false
    end
    if id == M.get() then
        return false
    end

    fskv.set(KEY, id)
    log.warn("app_devsel", "配件板切换为", M.name(id), "，2 秒后重启生效（请确认已插好对应配件板）")
    sys.timerStart(rtos.reboot, 2000)     -- 留 2 秒把界面提示显示完整
    return true
end

return M
