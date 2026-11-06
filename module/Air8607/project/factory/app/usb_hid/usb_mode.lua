--[[
@module  usb_mode
@summary USB 外设模式：UVC 摄像头与 USB 键鼠二选一（fskv 持久化，默认 UVC）
@version 1.0
@date    2026.11.03
@author  江访

=== 背景 ===

USB 键鼠与 UVC 摄像头共用同一个 USB Host 与同一条供电轨，同一时刻只能有一方占用。
带 UVC 摄像头又开了 features.usb_hid 的机型，把两者做成互斥开关：模式写 fskv，
默认 "uvc"（摄像头），切换后重启生效。切换入口「设置 → 外设模式」，交互与网络设置页同款。

=== 接口 ===

usb_mode.has_uvc(cfg)                 → config.peripherals 里有没有 uvc 条目
usb_mode.available(cfg)               → 本机型是否需要这个二选一（既有 UVC 又开了 usb_hid）
usb_mode.mode()                       → 当前模式 "uvc" | "hid"
usb_mode.set(mode)                    → 写 fskv，返回 ok, err
usb_mode.list(cfg)                    → 设置页两行的显示数据
usb_mode.preview_toggle(id, enable)   → 预演开关（互斥 / 需重启 / 是否最后一项）
usb_mode.set_enabled(id, enable)      → 写 fskv
usb_mode.should_start_hid(cfg)        → 本机该不该启动 usb_hid_app
usb_mode.filter(list)                 → 当前模式下可用的外设清单（HID 模式去掉 uvc 条目）
usb_mode.apply_boot(cfg)              → 开机按模式给 UVC 使能脚上电 / 断电

=== 约定 ===

- 模式是单值而非两个独立开关：写 "uvc" 即隐含 hid 关闭，反过来同理，
  从根上杜绝两项同时开启
- HID 模式下 filter() 会把 uvc 条目从外设清单里摘掉，功能测试页也就没有摄像头行，
  避免用户在 HID 模式下手动给摄像头上电又把 USB Host 抢回去
- 任何 fskv 调用都包 pcall 并先判 fskv 是否存在（PC 模拟器没有这个库）
]]

local airlink_pin = require "airlink_pin"

local M = {}

-- ==================== 常量 ====================

local CONFIG_KEY = "usb_mode_config" -- fskv 存储键
local MODE_UVC = "uvc"               -- UVC 摄像头模式
local MODE_HID = "hid"               -- USB 键鼠模式

-- 可选模式定义（设置页按此顺序列出）
local MODES = {
    [MODE_UVC] = {
        id = MODE_UVC,
        name = "UVC 摄像头",
        detail = "USB 摄像头出图 + 人脸识别模组",
        icon = "img",
    },
    [MODE_HID] = {
        id = MODE_HID,
        name = "USB 键鼠",
        detail = "USB 键盘 / 鼠标输入",
        icon = "mouse",
    },
}

-- 互斥对方
local OTHER_OF = {
    [MODE_UVC] = MODE_HID,
    [MODE_HID] = MODE_UVC,
}

-- ==================== fskv 读写 ====================

local kv_ready = false -- fskv 是否已初始化

-- 首次访问前确保 fskv 已初始化（重复调用安全，同 net_manager）
local function kv_ensure()
    if kv_ready or not fskv then return end
    pcall(fskv.init)
    kv_ready = true
end

-- 读 fskv，fskv 不存在或读失败都返回 nil
local function kv_get(key)
    if not fskv then return nil end
    kv_ensure()
    local ok, v = pcall(fskv.get, key)
    if ok then return v end
    return nil
end

-- 写 fskv，返回是否成功
local function kv_set(key, value)
    if not fskv then return false, "fskv unavailable" end
    kv_ensure()
    local ok, r = pcall(fskv.set, key, value)
    if not ok then return false, r end
    return (r and true or false), r
end

-- ==================== 一、能力与模式 ====================

--[[
@function has_uvc
@summary config.peripherals 里有没有 uvc 条目
@param table cfg  _G.project_config
@return boolean
]]
function M.has_uvc(cfg)
    local list = cfg and cfg.peripherals
    if type(list) ~= "table" then return false end
    for _, p in ipairs(list) do
        if p and p.type == "uvc" then return true end
    end
    return false
end

--[[
@function has_hid
@summary 本机型有没有启用 USB 键鼠能力（features.usb_hid）
@param table cfg  _G.project_config
@return boolean
]]
function M.has_hid(cfg)
    local feat = cfg and cfg.features
    return (type(feat) == "table") and (feat.usb_hid == true)
end

--[[
@function available
@summary 本机型是否需要 UVC / USB HID 二选一（两者都有才存在冲突）
@param table cfg  _G.project_config
@return boolean
]]
function M.available(cfg)
    return M.has_uvc(cfg) and M.has_hid(cfg)
end

--[[
@function mode
@summary 当前 USB 外设模式
@return string "uvc" | "hid"
]]
function M.mode()
    local saved = kv_get(CONFIG_KEY)
    if saved == MODE_HID then return MODE_HID end
    return MODE_UVC -- 默认 UVC 摄像头
end

--[[
@function set
@summary 写 USB 外设模式到 fskv
@param string mode  "uvc" | "hid"
@return boolean, string|nil  是否成功，失败原因
]]
function M.set(mode)
    if not MODES[mode] then return false, "unknown mode: " .. tostring(mode) end
    if M.mode() == mode then return true end
    local ok, err = kv_set(CONFIG_KEY, mode)
    if ok then
        log.info("usb_mode", "外设模式已写入:", mode)
        sys.publish("USB_MODE_CHANGED", mode)
    else
        log.error("usb_mode", "外设模式写入失败", err)
    end
    return ok, err
end

--[[
@function list
@summary 设置页两行的显示数据（只列本机型实际具备的模式）
@param table cfg  _G.project_config
@return table  { {id, name, detail, enabled}, ... }
]]
function M.list(cfg)
    local cur = M.mode()
    local out = {}
    if M.has_uvc(cfg) then
        out[#out + 1] = {
            id = MODE_UVC,
            name = MODES[MODE_UVC].name,
            detail = MODES[MODE_UVC].detail,
            icon = MODES[MODE_UVC].icon,
            enabled = (cur == MODE_UVC),
        }
    end
    if M.has_hid(cfg) then
        out[#out + 1] = {
            id = MODE_HID,
            name = MODES[MODE_HID].name,
            detail = MODES[MODE_HID].detail,
            icon = MODES[MODE_HID].icon,
            enabled = (cur == MODE_HID),
        }
    end
    return out
end

-- ==================== 二、开关预演与写入 ====================

--[[
@function preview_toggle
@summary 预演一次开关操作，不落盘
@param string id       "uvc" | "hid"
@param boolean enable  目标状态
@return table  { ok, need_reboot, reason, will_disable, changes }
   reason: "usb_mutex" 开另一项需关掉当前项（确认后重启） /
           "usb_switch" 单项写入，无互斥（need_reboot=false 时为无变化） /
           "last_one" 两项必须留一项，不许关掉当前项 / "unknown" 未知 id
]]
function M.preview_toggle(id, enable)
    local result = {
        ok = false,
        need_reboot = false,
        will_disable = {},
        changes = {},
        reason = "",
    }
    if not MODES[id] then
        result.reason = "unknown"
        return result
    end
    local value = (enable == true)
    local cur = M.mode()

    if not value then
        -- 两项必须二选一：不允许把唯一开启的那项关掉
        if cur == id then
            result.reason = "last_one"
            return result
        end
        result.ok = true
        result.reason = "usb_switch"
        return result
    end

    result.ok = true
    result.changes[id] = true
    if cur == id then
        -- 本就是当前模式，无变化，不必重启
        result.reason = "usb_switch"
        return result
    end
    result.need_reboot = true
    local other = OTHER_OF[id]
    result.changes[other] = false
    result.will_disable[#result.will_disable + 1] = other
    result.reason = "usb_mutex"
    return result
end

--[[
@function set_enabled
@summary 按预演结果写入开关（写完需重启生效）
@param string id       "uvc" | "hid"
@param boolean enable  目标状态
@return boolean 是否写入成功
]]
function M.set_enabled(id, enable)
    local preview = M.preview_toggle(id, enable)
    if not preview.ok then return false end
    for mode_name, value in pairs(preview.changes) do
        if value then
            local ok = M.set(mode_name)
            if not ok then return false end
        end
    end
    return true
end

-- ==================== 三、开机应用 ====================

--[[
@function should_start_hid
@summary 本机该不该启动 usb_hid_app
@param table cfg  _G.project_config
@return boolean
]]
function M.should_start_hid(cfg)
    if not M.has_hid(cfg) then return false end
    -- 没有 UVC 就不存在冲突，USB 键鼠直接启用
    if not M.has_uvc(cfg) then return true end
    return (M.mode() == MODE_HID)
end

--[[
@function filter
@summary 按当前模式过滤外设清单：HID 模式摘掉 uvc 条目
@param table list  config.peripherals
@return table  过滤后的清单（新表，原表不动）
]]
function M.filter(list)
    if type(list) ~= "table" then return list end
    if M.mode() ~= MODE_HID then return list end
    local out = {}
    for _, p in ipairs(list) do
        if not (p and p.type == "uvc") then
            out[#out + 1] = p
        end
    end
    return out
end

--[[
@function apply_boot
@summary 开机按当前模式给 UVC 使能脚上电 / 断电
@param table cfg  _G.project_config
@return nil
]]
function M.apply_boot(cfg)
    local list = cfg and cfg.peripherals
    if type(list) ~= "table" then return end
    local on = (M.mode() ~= MODE_HID)
    for _, p in ipairs(list) do
        if p and p.type == "uvc" and p.en_pin then
            local level = on and 1 or 0
            -- WiFi 侧使能脚（GPIO ≥100）由 airlink_pin 延后到链路就绪后下发，开机不等链路
            airlink_pin.defer(p.en_pin, level)
            log.info("usb_mode", "UVC 供电", on and "开启" or "关闭", "GPIO" .. tostring(p.en_pin))
        end
    end
end

-- ==================== 四、状态查询消息 ====================

sys.subscribe("USB_MODE_GET", function()
    sys.publish("USB_MODE_STATUS", M.mode())
end)

return M
