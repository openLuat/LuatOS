--[[
@module  usb_hid_app
@summary USB HID 键盘鼠标管理模块（USB Host + Input 事件订阅）
@version 1.0
@date    2026.09.16
@usage
依赖: 固件需包含 LUAT_USE_USB_HOST + LUAT_USE_INPUT
硬件: 需 USB Host 接口（如 Air8601 GPIO12 控制 VBUS）

消息协议（订阅/发布）:
订阅: USB_HID_ENABLE           → 启用 USB HID（初始化 USB Host + 订阅 Input 事件）
订阅: USB_HID_DISABLE          → 禁用 USB HID（关闭 USB Host + 取消订阅）
订阅: USB_HID_GET_STATUS       → 查询 USB HID 当前状态
发布: USB_HID_STATUS(enabled)  → USB HID 状态返回
发布: USB_HID_DEVICE_ATTACHED(id, name, caps)  → 设备接入事件
发布: USB_HID_DEVICE_REMOVED(id)               → 设备移除事件
发布: USB_HID_KEY_EVENT(id, key, pressed)      → 键盘事件
发布: USB_HID_MOUSE_EVENT(id, axis, value)     → 鼠标事件（axis: REL_X/REL_Y）
发布: USB_HID_WHEEL_EVENT(id, delta)           → 滚轮事件

参考: C:\gitee\LuatOS\olddemo\demo\usb_hid
]]

local M = {}

-- ==================== 配置常量 ====================

local USB_BUS_ID = 0           -- USB 总线 ID（Air8601 使用总线 0）
local INPUT_QUEUE_BYTES = 4096 -- Input 事件队列大小（字节）
local VBUS_GPIO = 12           -- USB VBUS 供电控制 GPIO（Air8601 开发板）

-- ==================== 局部变量 ====================

local enabled = false          -- USB HID 启用状态
local subscription = nil       -- Input 订阅句柄
local devices = {}             -- 已连接设备表 {id = {name, caps}}

-- ==================== 私有函数 ====================

--[[
@function usb_power_control
@summary USB 电源控制
@param boolean on true=开启, false=关闭
@return nil
]]
local function usb_power_control(on)
    -- GPIO 控制 VBUS 供电（Air8601 开发板）
    if VBUS_GPIO then
        gpio.setup(VBUS_GPIO, on and 1 or 0, gpio.PULLUP)
        sys.wait(100)
    end
end

--[[
@function usb_host_init
@summary USB Host 模式初始化
@return boolean 成功返回 true，失败返回 false
]]
local function usb_host_init()
    -- 1. 关闭 USB 电源
    pm.power(pm.USB, false)
    usb_power_control(false)
    sys.wait(100)

    -- 2. 设置 USB Host 模式
    -- 关闭底层控制传输刷屏（保留 C HID/input 日志）
    usb.debug(USB_BUS_ID, false)
    local ok = usb.mode(USB_BUS_ID, usb.HOST)
    if not ok then
        log.error("usb_hid", "USB Host 模式设置失败")
        return false
    end

    -- 3. 开启 USB 电源
    usb_power_control(true)
    pm.power(pm.USB, true)

    log.info("usb_hid", "USB Host 初始化成功", "bus=" .. USB_BUS_ID)
    return true
end

--[[
@function usb_host_deinit
@summary USB Host 模式关闭
@return nil
]]
local function usb_host_deinit()
    pm.power(pm.USB, false)
    usb_power_control(false)
    log.info("usb_hid", "USB Host 已关闭")
end

--[[
@function input_handler
@summary Input 事件处理回调
@param string kind 事件类型: "attach" / "remove" / "reset" / "overflow" / "frame"
@param number id 设备 ID
@param table data 事件数据（frame 事件包含事件队列）
@return nil
]]
local function input_handler(kind, id, data)
    if kind == "attach" then
        -- 设备接入
        devices[id] = {
            name = data.name or "未知设备",
            caps = data.caps or {},
            vendor = data.vendor,
            product = data.product,
        }
        log.info("usb_hid", "设备接入", id, data.name,
            string.format("%04x:%04x", data.vendor or 0, data.product or 0))
        sys.publish("USB_HID_DEVICE_ATTACHED", id, data.name, data.caps)

    elseif kind == "remove" then
        -- 设备移除
        local dev = devices[id]
        devices[id] = nil
        log.info("usb_hid", "设备移除", id, dev and dev.name or "未知")
        sys.publish("USB_HID_DEVICE_REMOVED", id)

    elseif kind == "reset" then
        -- 设备重置
        log.info("usb_hid", "设备重置", id, data and data.sequence)

    elseif kind == "overflow" then
        -- 事件队列溢出
        log.warn("usb_hid", "事件队列溢出", data and data.reason)
        devices = {}  -- 清空设备表

    elseif kind == "frame" then
        -- 输入事件帧
        for i = 1, data.count do
            local t, c, v = data:get(i)

            if t == input.EV_KEY then
                -- 按键事件（键盘按键、鼠标按键）
                sys.publish("USB_HID_KEY_EVENT", id, c, v)

            elseif t == input.EV_REL then
                -- 相对移动事件
                if c == input.REL_X or c == input.REL_Y then
                    -- 鼠标移动
                    sys.publish("USB_HID_MOUSE_EVENT", id, c, v)
                elseif c == input.REL_WHEEL then
                    -- 滚轮
                    sys.publish("USB_HID_WHEEL_EVENT", id, v)
                end
            end
        end
    end
end

-- ==================== 公开接口 ====================

--[[
@function enable
@summary 启用 USB HID
@return boolean 成功返回 true，失败返回 false
]]
function M.enable()
    if enabled then
        log.info("usb_hid", "USB HID 已启用，跳过重复初始化")
        return true
    end

    -- 初始化 USB Host
    if not usb_host_init() then
        return false
    end

    -- 订阅 Input 事件
    local ok, sub = pcall(input.subscribe, {queue_bytes = INPUT_QUEUE_BYTES}, input_handler)
    if not ok or not sub then
        log.error("usb_hid", "Input 订阅失败", sub)
        usb_host_deinit()
        return false
    end
    subscription = sub

    enabled = true
    sys.publish("USB_HID_STATUS", true)
    log.info("usb_hid", "USB HID 已启用")
    return true
end

--[[
@function disable
@summary 禁用 USB HID
@return boolean 成功返回 true，失败返回 false
]]
function M.disable()
    if not enabled then
        log.info("usb_hid", "USB HID 已禁用，跳过重复操作")
        return true
    end

    -- 取消 Input 订阅
    if subscription then
        pcall(function() subscription:close() end)
        subscription = nil
    end

    -- 关闭 USB Host
    usb_host_deinit()

    -- 清空设备表
    devices = {}

    enabled = false
    sys.publish("USB_HID_STATUS", false)
    log.info("usb_hid", "USB HID 已禁用")
    return true
end

--[[
@function is_enabled
@summary 查询 USB HID 启用状态
@return boolean 启用返回 true，禁用返回 false
]]
function M.is_enabled()
    return enabled
end

--[[
@function get_devices
@summary 获取已连接设备列表
@return table 设备表 {id = {name, caps, vendor, product}}
]]
function M.get_devices()
    return devices
end

-- ==================== 事件订阅 ====================

sys.subscribe("USB_HID_ENABLE", function()
    M.enable()
end)

sys.subscribe("USB_HID_DISABLE", function()
    M.disable()
end)

sys.subscribe("USB_HID_GET_STATUS", function()
    sys.publish("USB_HID_STATUS", enabled)
end)

-- ==================== 启动时自动启用 USB HID ====================
sys.taskInit(function()
    sys.wait(2000)  -- 等待系统初始化完成（USB 任务创建）
    -- PC 模拟器没有 usb 库：跳过初始化，否则会在 usb_host_init 里以 nil 索引崩溃（Lua VM exit）
    if not usb then
        log.warn("usb_hid", "PC 模拟器无 usb 库，跳过 USB HID 初始化")
        return
    end
    M.enable()
end)

return M
