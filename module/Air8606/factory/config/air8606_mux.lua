-- Air8606 的接口用途在开机时锁存，保存的选择从下一次启动开始生效。
local M = {}
local CONFIG_KEY = "air8606_mux_config"
local active, saved

M.groups = {
    { key = "radio", title = "SPI2", hint = "SPI2 的数据线、CS 和 RDY 由两种装配共用。请按实物选择一路。",
        options = {
            { id = "4g", title = "Air780EX2 4G", detail = "R176～R180 接 EX2。启用 4G、GNSS 和 EX2 网口测试。" },
            { id = "wifi", title = "Air6205 Wi-Fi", detail = "R171～R175 接 Air6205。启用 Wi-Fi 扫描和连接。" },
        } },
    { key = "uart2", title = "UART2", hint = "UART2 的两组电阻按实物选择，所选模式决定功能测试入口。",
        options = {
            { id = "can", title = "CAN", detail = "R32/R34 装配，使用 CAN2，测试速率 500 kbps。" },
            { id = "rs232", title = "RS232", detail = "R31/R33 装配，使用 UART2，测试参数 57600/8N1。" },
        } },
    { key = "rs4851", title = "UART1", hint = "485-1 的两种装配共用 UART1、GPIO0 方向控制和 GPIO14 供电。",
        options = {
            { id = "isolated", title = "隔离 485-1", detail = "选择 U11 装配，功能测试显示隔离 485-1。" },
            { id = "nonisolated", title = "非隔离 485-1", detail = "选择 U1101 装配，功能测试显示非隔离 485-1。" },
        } },
    { key = "uart3", title = "UART3", hint = "人脸串口与 485-2 共用 UART3。摄像头与 485 测试按页面互斥供电。",
        options = {
            { id = "auto", title = "按测试页切换", detail = "保留 485-2 和人脸测试，打开测试时切换占用。" },
            { id = "rs485", title = "隔离 485-2", detail = "UART3 用于 485-2，UVC 模式下保留 USB 视频预览。" },
            { id = "face", title = "人脸串口", detail = "UART3 用于人脸模组，USB Host 需选择 UVC 摄像头。" },
        } },
    { key = "uart6", title = "UART6", hint = "按板上电阻装配选择 UART6 用途，保存并重启后生效。",
        options = {
            { id = "air1103", title = "SIP 通话（Air1103）", detail = "R25/R26 接 Air1103。双向通话需在「音频回放」中选择与实物对应的 C237。" },
            { id = "ttl", title = "TTL 串口（J22）", detail = "R99/R119 接 J22，R25/R26 空贴。串口测试使用 115200、8N1。" },
        } },
    { key = "audio_playback", title = "音频回放", hint = "按功放输入电容选择。SIP 通话使用 C237，TTL 档可通过 C104 独立播放。",
        options = {
            { id = "air1103", title = "Air1103（C237）", detail = "C237 实贴、C104 空贴。UART6 发送 PCM，由 Air1103 输出到功放。" },
            { id = "dac", title = "主控 DAC（C104）", detail = "C104 实贴、C237 空贴。由 Air1602 内置 DAC 输出到功放。" },
        } },
    { key = "usb", title = "USB Host", hint = "UVC 摄像头和 USB 键鼠共用主机接口与 GPIO13 供电。",
        options = {
            { id = "uvc", title = "UVC 摄像头", detail = "打开功能测试中的摄像头预览，按 UART3 设置提供人脸页签。" },
            { id = "hid", title = "USB 键鼠", detail = "开机启动 USB 键盘和鼠标输入。" },
        } },
}

local function valid(group, value)
    for _, option in ipairs(group.options) do
        if option.id == value then return true end
    end
    return false
end

local function copy(selection)
    local out = {}
    for _, group in ipairs(M.groups) do out[group.key] = selection[group.key] end
    return out
end

local function read(key)
    if not fskv then return nil end
    local ok, value = pcall(fskv.get, key)
    if ok then return value end
end

function M.load(default_radio, options)
    if fskv then pcall(fskv.init) end
    local stored = read(CONFIG_KEY)
    if type(stored) ~= "table" then stored = {} end
    local legacy_usb = read("usb_mode_config")
    local default_usb = options.usb or "uvc"
    if legacy_usb == "hid" or legacy_usb == "uvc" then default_usb = legacy_usb end
    local defaults = {
        radio = default_radio,
        uart2 = options.uart2,
        rs4851 = options.rs4851,
        uart3 = options.uart3 or "auto",
        uart6 = options.uart6 or "air1103",
        usb = default_usb,
        audio_playback = options.audio_playback or "air1103",
    }
    local selection = {}
    for _, group in ipairs(M.groups) do
        local value = stored[group.key]
        if not valid(group, value) then value = defaults[group.key] end
        assert(valid(group, value), "invalid Air8606 default: " .. group.key)
        selection[group.key] = value
    end
    if selection.usb == "hid" and selection.uart3 == "face" then
        selection.uart3 = "auto"
    end
    active, saved = selection, copy(selection)
    return copy(active)
end

function M.state()
    return copy(active), copy(saved)
end

function M.current(key)
    return active and active[key]
end

function M.same(a, b)
    for _, group in ipairs(M.groups) do
        if a[group.key] ~= b[group.key] then return false end
    end
    return true
end

function M.save(selection)
    if not saved then return false, "接口配置尚未加载" end
    if type(selection) ~= "table" then return false, "请选择接口模式" end
    for _, group in ipairs(M.groups) do
        if not valid(group, selection[group.key]) then
            return false, "请选择有效的 " .. group.title .. " 模式"
        end
    end
    if selection.uart3 == "face" and selection.usb ~= "uvc" then
        return false, "使用人脸串口时，请将 USB Host 设为 UVC 摄像头。"
    end
    if M.same(selection, saved) then return true end
    local next_modes = copy(selection)
    if not fskv then return false, "配置存储不可用" end
    local ok, written = pcall(fskv.set, CONFIG_KEY, next_modes)
    if not ok or written ~= true then return false, "写入配置失败，请重试" end
    saved = next_modes
    return true
end

return M
