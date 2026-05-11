-- nconv: var2-4 fn2-5 tag-short
--[[
@module  settings_about_app
@summary 关于设备业务逻辑层
@version 1.0
@date    2026.04.01
@author  江访
@usage
本模块为关于设备业务逻辑层，收集设备型号、唯一ID、固件版本、内核版本等信息并上报。
]]
-- ==================== 设备信息 ====================
local di = {
    device_name = "Air8101",
    model = "--",
    version = "1.0.0",
    kernel = "--",
    unique_id = "--",
    unique_id_hex = "--"
}
di.version = _G.VERSION
--[[
@function get_device_info
@summary 获取设备信息（型号、唯一ID、固件版本、内核版本）
@return table 设备信息表
]]
local function gdi()
    -- 获取设备型号
    di.model = _G.model_str
    -- 获取MCU唯一ID（原始格式和十六进制格式）
    local rok, uid = pcall(mcu.unique_id)
    if rok and uid then
        di.unique_id = uid
        di.unique_id_hex = uid:toHex()
    end
    -- 获取内核固件基础名称
    local rok2, fw = pcall(rtos.firmware)
    if rok2 and fw then
        -- 获取版本号信息，more=true 返回版本号数字
        local rok3, vs, vn = pcall(rtos.version, true)
        if rok3 then
            -- 拼接完整内核版本信息
            -- 格式: LuatOS-SoC_V2022_PC_1
            if fw:find("LuatOS%-SoC") then
                -- firmware 已经包含前缀，直接拼接版本号
                di.kernel = fw .. "_" .. tostring(vn)
            else
                -- 需要加上前缀
                di.kernel = fw .. "_" .. tostring(vn)
            end
        else
            -- 获取版本号失败，只显示firmware
            di.kernel = fw
        end
    end
    return di
end

-- ==================== 事件订阅 ====================
-- 订阅设备信息查询事件
sys.subscribe("ABOUT_DEVICE_GET_INFO", function()
    local inf = gdi()
    sys.publish("ABOUT_DEVICE_INFO", inf)
    log.info("saa", "上报设备信息")
end)
