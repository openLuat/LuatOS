--[[
@module  settings_about_app
@summary 关于设备业务逻辑层
@version 1.0
@date    2026.04.01
@author  LuatOS
]]

-- ==================== 设备信息 ====================
local device_info = {
    device_name = "Air8101",
    model = "--",
    version = "1.0.0",
    kernel = "--",
    unique_id = "--",
    unique_id_hex = "--"
}

--[[
获取设备信息
@return table 设备信息表
]]
local function get_device_info()
    -- 获取设备型号
    local ret, model = pcall(hmeta.model)
    if ret and model then
        device_info.model = model
    end

    -- 获取MCU唯一ID（原始格式和十六进制格式）
    local ret_id, unique_id = pcall(mcu.unique_id)
    if ret_id and unique_id then
        device_info.unique_id = unique_id
        device_info.unique_id_hex = unique_id:toHex()
    end

    -- 获取内核固件基础名称
    local ret2, firmware = pcall(rtos.firmware)
    if ret2 and firmware then
        -- 获取版本号信息，more=true 返回版本号数字
        local ret3, ver_str, ver_num = pcall(rtos.version, true)
        if ret3 then
            -- 拼接完整内核版本信息
            -- 格式: LuatOS-SoC_V2022_PC_1
            if firmware:find("LuatOS%-SoC") then
                -- firmware 已经包含前缀，直接拼接版本号
                device_info.kernel = firmware .. "_" .. tostring(ver_num)
            else
                -- 需要加上前缀
                device_info.kernel = firmware .. "_" .. tostring(ver_num)
            end
        else
            -- 获取版本号失败，只显示firmware
            device_info.kernel = firmware
        end
    end

    return device_info
end

-- ==================== 事件订阅 ====================

-- 订阅版本号事件（从 main.lua 获取）
sys.subscribe("APP_VERSION", function(ver)
    device_info.version = ver
    log.info("settings_about_app", "收到版本号: " .. ver)
end)

-- 订阅设备信息查询事件
sys.subscribe("ABOUT_DEVICE_GET_INFO", function()
    local info = get_device_info()
    sys.publish("ABOUT_DEVICE_INFO", info)
    log.info("settings_about_app", "上报设备信息")
end)

log.info("settings_about_app", "模块加载完成")
