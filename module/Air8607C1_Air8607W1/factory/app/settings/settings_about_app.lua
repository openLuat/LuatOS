--[[
@module  settings_about_app
@summary 关于设备业务逻辑层
@version 1.0
@date    2026.04.01
@author  江访
@usage
本模块为关于设备业务逻辑层，收集设备型号、唯一ID、固件版本、内核版本等信息并上报。

消息协议（订阅/发布）:
订阅: ABOUT_DEVICE_GET_INFO          → 查询设备信息
发布: ABOUT_DEVICE_INFO({core, script, ...}) → 设备信息返回值
]]
-- ==================== 设备信息 ====================
-- 字段与固件「关于」页保持一致：设备名称 / 型号 / ID / 固件版本 / 内核版本 / 主控芯片 / 屏幕分辨率
local device_info = {
    device_name = "合宙引擎主机",
    model = "--",
    version = "1.0.0",
    kernel = "--",
    unique_id = "--",
    chip = "--",
    screen = "--",
}
device_info.version = _G.VERSION
--[[
@function get_device_info
@summary 获取设备信息（型号、唯一ID、固件版本、内核版本、主控芯片、屏幕分辨率）
@return table 设备信息表
]]
local function get_device_info()
    -- 获取设备型号
    device_info.model = (_G.project_config and _G.project_config.name) or ""
    -- 主控芯片：优先取工程配置（Air1603），回退底包 bsp
    device_info.chip = (_G.project_config and _G.project_config.chip)
        or (rtos.bsp and rtos.bsp()) or "--"
    -- 屏幕分辨率：取实际屏幕参数，未初始化时回退工程配置
    local lcd = _G.project_config and _G.project_config.hw and _G.project_config.hw.lcd
    local sw = screen_w or (lcd and lcd.w) or 0
    local sh = screen_h or (lcd and lcd.h) or 0
    if sw > 0 and sh > 0 then
        device_info.screen = string.format("%d × %d", sw, sh)
    end
    -- 设备名称未保存过时按芯片型号兜底（合宙引擎主机1603），与固件默认名一致
    if device_info.device_name == nil or device_info.device_name == ""
        or device_info.device_name == "合宙引擎主机" then
        local suffix = tostring(device_info.chip or ""):gsub("^Air", "")
        if suffix == "PC" then suffix = "" end   -- 模拟器不拼芯片名
        device_info.device_name = "合宙引擎主机" .. suffix
    end
    -- 获取MCU唯一ID（原始格式和十六进制格式）
    local ok, unique_id = pcall(mcu.unique_id)
    if ok and unique_id then
        -- 设备 ID 直接显示十六进制格式（与固件同为大写），不再保留原始格式
        device_info.unique_id = unique_id:toHex():upper()
    end
    -- 内核版本：按底包文件名重拼，形如 LuatOS-SoC_V1032_Air1603_102.soc
    -- 不用 rtos.firmware() 原串：部分底包会带板型段（…_Air8607C1_A），与底包文件名不一致
    local ok2, firmware = pcall(rtos.firmware)
    local ok3, ver_str, ver_num = pcall(rtos.version, true)
    local chip = (_G.project_config and _G.project_config.chip)
        or (rtos.bsp and rtos.bsp())
    local patch = ver_num
    if not patch and ok2 and firmware then
        patch = tostring(firmware):match("_(%d+)$")
    end
    if ok3 and ver_str and chip and patch then
        device_info.kernel = string.format("LuatOS-SoC_%s_%s_%s.soc", ver_str, chip, tostring(patch))
    elseif ok3 and ver_str and chip then
        device_info.kernel = string.format("LuatOS-SoC_%s_%s.soc", ver_str, chip)
    elseif ok2 and firmware then
        device_info.kernel = tostring(firmware)
    end
    return device_info
end

-- ==================== 事件订阅 ====================
-- 订阅设备信息查询事件
sys.subscribe("ABOUT_DEVICE_GET_INFO", function()
    local info = get_device_info()
    sys.publish("ABOUT_DEVICE_INFO", info)
    log.info("settings_about", "上报设备信息")
end)
