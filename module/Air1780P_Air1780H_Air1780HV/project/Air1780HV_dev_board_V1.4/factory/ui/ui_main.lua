--[[
@module  ui_main
@summary UI 主控：单页信息展示（AirUI 简约版）
@version 2.1.0
@date    2026.10.20
@usage
竖屏 320×480 单页展示（无触摸，无需翻页），采用左标签 + 右数值的简约列表布局：
  标题区  合宙设备 / 版本 / 环境监测终端
  信息行  网络状态 / IP 地址 / 温度 / 湿度 / 空气质量
  底部    设备编号

配色：白底、深灰正文、浅灰次要文字、极浅分隔线，仅网络状态用绿色点缀。
字体：全局字体由 lcd_drv.lua 的 airui.font_load 决定；底部设备编号显式指定 16 号，
      避免长 ID 在 272px 宽度内换行后被 h=24 裁掉。

刷新：每 2 秒刷新一次；按键事件触发时立即刷新。
数据：订阅 "read_sensor_rsp" 更新 _G.ui_data 缓存。
]]

local TAG = "ui_main"

-- 简约配色
local COLOR_BG      = 0xFFFFFF  -- 背景
local COLOR_INK     = 0x1A1A1A  -- 主文字
local COLOR_SUB     = 0x8C8C8C  -- 次要文字
local COLOR_LINE    = 0xEFEFEF  -- 分隔线
local COLOR_OK      = 0x34C759  -- 在线状态
local COLOR_IDLE    = 0xB0B0B0  -- 未就绪状态

-- 传感器数据缓存（sensor_app 采集后更新）
_G.ui_data = _G.ui_data or { temp = nil, hum = nil, voc = nil }

sys.subscribe("read_sensor_rsp", function(temp, hum, voc)
    _G.ui_data.temp = temp
    _G.ui_data.hum = hum
    _G.ui_data.voc = voc
end)

-- 安全读取（PC 模拟器上 hmeta/mcu 可能缺失，失败返回 nil）
local function safe_call(fn)
    local ok, val = pcall(fn)
    if ok then return val end
    return nil
end

-- 设备识别 ID 统一由 hmeta.devid() 提供（4G=IMEI / WiFi=MAC / MCU=生产流程 ID）
local function get_device_id()
    local devid = safe_call(function() return hmeta.devid() end)
    if devid and devid ~= "" then
        return tostring(devid)
    end
    return nil
end

local lbl = {}

local function divider(parent, y)
    airui.container({ parent = parent, x = 24, y = y, w = 272, h = 1, color = COLOR_LINE })
end

-- 一行信息：左侧浅灰标签，右侧深色数值
local function row(parent, key, name, y)
    airui.label({ parent = parent, text = name, x = 24, y = y + 16, w = 120, h = 24, color = COLOR_SUB })
    lbl[key] = airui.label({
        parent = parent, text = "--", x = 148, y = y + 16, w = 148, h = 24,
        color = COLOR_INK, align = airui.TEXT_ALIGN_RIGHT,
    })
end

local function ui_build()
    local root = airui.container({ x = 0, y = 0, w = 320, h = 480, color = COLOR_BG })

    -- 标题区
    airui.label({ parent = root, text = "合宙设备", x = 24, y = 30, w = 120, h = 24, color = COLOR_INK })
    airui.label({
        parent = root, text = "v" .. tostring(VERSION), x = 140, y = 30, w = 156, h = 24,
        color = COLOR_SUB, align = airui.TEXT_ALIGN_RIGHT,
    })
    airui.label({ parent = root, text = "环境监测终端", x = 24, y = 60, w = 272, h = 24, color = COLOR_SUB })
    divider(root, 100)

    -- 信息行（行高 56）
    row(root, "net",  "网络状态", 108)
    divider(root, 164)
    row(root, "ip",   "IP 地址",  164)
    divider(root, 220)
    row(root, "temp", "温度",     220)
    divider(root, 276)
    row(root, "hum",  "湿度",     276)
    divider(root, 332)
    row(root, "voc",  "空气质量", 332)
    divider(root, 388)

    -- 底部设备编号：用小字号，避免长 ID 换行后被 h=24 裁掉
    local device_id = get_device_id()
    local id_text = "设备编号  " .. (device_id or "--")
    airui.label({
        parent = root, text = id_text,
        x = 24, y = 406, w = 272, h = 24, color = COLOR_SUB,
        font = "hzfont", font_size = 16,
    })
end

local function refresh()
    local ip_addr = safe_call(function() return socket.localIP(socket.dft()) end)
    local ok, adapter = pcall(function() return socket.adapter(socket.dft()) end)
    local net_ready = ok and adapter and adapter ~= nil

    local d = _G.ui_data
    lbl.net:set_text(net_ready and "已连接" or "未连接")
    lbl.net:set_color(net_ready and COLOR_OK or COLOR_IDLE)
    lbl.ip:set_text(ip_addr or "--")
    lbl.temp:set_text(d.temp and string.format("%.1f C", d.temp) or "--")
    lbl.hum:set_text(d.hum and string.format("%.1f %%", d.hum) or "--")
    lbl.voc:set_text(d.voc and (tostring(d.voc) .. " ppb") or "--")
end

local function ui_main()
    if not _G.airui_ready then
        log.error(TAG, "airui 未初始化，UI 不启动")
        return
    end

    ui_build()
    log.info(TAG, "ui ready")

    while true do
        refresh()
        -- 按键事件触发立即刷新，超时则每 2 秒刷新一次
        sys.waitUntil("KEY_EVENT", 2000)
    end
end

sys.taskInit(ui_main)
