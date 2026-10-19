--[[
@module  ui_main
@summary UI 主控：单页信息展示
@version 1.0.0
@date    2026.10.16
@usage
竖屏 320×480 单页展示（无触摸，无需翻页）：
  标题栏  合宙设备（32号中文字库）
  网络    信号 / 网络
  传感器  温度 / 湿度 / 空气质量
  信息    设备 / 版本

字体：标题用 32 号中文字库（customer_font_32.bin），标签用 16 号中文字库（customer_font_16.bin），数值用内置英文（opposansm16）。
刷新：每 2 秒重绘一次；按键事件触发时立即重绘（手动刷新）。
数据：订阅 "read_sensor_rsp" 更新 _G.ui_data 缓存。
]]

local WHITE = 0xFFFF
local BLACK = 0x0000
local BLUE = 0x001F
local GRAY = 0x8410

-- 传感器数据缓存（sensor_app 采集后更新）
_G.ui_data = _G.ui_data or { temp = nil, hum = nil, voc = nil }

sys.subscribe("read_sensor_rsp", function(temp, hum, voc)
    _G.ui_data.temp = temp
    _G.ui_data.hum = hum
    _G.ui_data.voc = voc
end)

-- 安全读取（PC 模拟器上 mobile/hmeta 可能缺失，失败返回 nil）
local function safe_call(fn)
    local ok, val = pcall(fn)
    if ok then return val end
    return nil
end

-- 画一行：中文标签（16号字库）+ 数值（16号内置英文）
local function draw_row(y, label, value_x, value)
    lcd.setFontFile("/luadb/customer_font_16.bin")
    lcd.drawStr(20, y, label, BLACK)
    lcd.setFont(lcd.font_opposansm16)
    lcd.drawStr(value_x, y, ": " .. value, BLACK)
end

local function draw()
    lcd.clear(WHITE)

    -- 标题栏（32号中文）
    lcd.fill(0, 0, 320, 44, BLUE)
    lcd.setFontFile("/luadb/customer_font_32.bin")
    lcd.drawStr(96, 32, "合宙设备", WHITE)

    -- 数据
    local csq = safe_call(function() return mobile.csq() end)
    local net_ready = false
    local ok, v = pcall(function() return socket.adapter(socket.dft()) end)
    if ok then net_ready = not not v end
    local d = _G.ui_data
    local devid = safe_call(function() return hmeta.devid() end)
    if not devid or devid == "" then
        devid = safe_call(function() return mobile.imei() end)
    end

    -- 网络
    draw_row(64, "信号", 60, csq and tostring(csq) or "--")
    draw_row(88, "网络", 60, net_ready and "READY" or "CONNECTING")
    lcd.drawLine(20, 112, 300, 112, GRAY)

    -- 传感器
    draw_row(132, "温度", 60, d.temp and string.format("%.1f C", d.temp) or "--")
    draw_row(156, "湿度", 60, d.hum and string.format("%.1f %%", d.hum) or "--")
    draw_row(180, "空气质量", 92, d.voc and (tostring(d.voc) .. " ppb") or "--")
    lcd.drawLine(20, 204, 300, 204, GRAY)

    -- 信息
    draw_row(224, "设备", 60, devid and tostring(devid) or "--")
    draw_row(248, "版本", 60, tostring(VERSION))
end

local function ui_main()
    while true do
        draw()
        lcd.flush()

        -- 按键事件触发立即重绘，超时则每 2 秒重绘一次
        sys.waitUntil("KEY_EVENT", 2000)
    end
end

sys.taskInit(ui_main)
