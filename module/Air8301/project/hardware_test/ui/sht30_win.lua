--[[
@module  sht30_win
@summary SHT30 MODBUS-RTU 温湿度监测页面
@version 4.0.0
@date    2026.09.03
@author  江访
@usage
通过 RS485 Port2(UART11) 使用 MODBUS-RTU 协议连接亿佰特 EID041-G01S 温湿度变送器。
不直接操作 UART，通过 rs485_app 的 RS485_SEND_REQUEST 消息机制收发数据，
避免 Air8000W airlink RPC 路径下 pin485/tx_delay 缺失导致 uart.write 返回 -1。
]]

local win_id = nil
local main_container, content
local temp_label, humid_label, status_label, error_label
local running = false

-- 温湿度变送器 MODBUS 配置（亿佰特 EID041-G01S）
local SHT30_SLAVE_ID   = 0x01       -- 默认从机地址 1
local SHT30_BAUD       = 9600       -- 波特率
local SHT30_PORT       = 2          -- RS485 Port2 = UART11
local SHT30_REG_COUNT  = 2          -- 温度 + 湿度
local POLL_INTERVAL    = 2000       -- 轮询间隔 ms
local READ_TIMEOUT     = 1000       -- 响应超时 ms

-- CRC16-MODBUS 查表法
local CRC16_TAB = {}
do
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if crc % 2 == 1 then
                crc = bit.rshift(crc, 1) % 65536
                crc = bit.bxor(crc, 0xA001)
            else
                crc = bit.rshift(crc, 1) % 65536
            end
        end
        CRC16_TAB[i] = crc
    end
end

local function crc16_modbus(data)
    local crc = 0xFFFF
    for i = 1, #data do
        local idx = bit.bxor(crc % 256, data:byte(i))
        crc = bit.bxor(CRC16_TAB[idx], bit.rshift(crc, 8) % 65536)
    end
    return crc
end

--[[
读取 SHT30 温湿度（通过 rs485_app 消息机制）
@return number|nil temperature, number|nil humidity, string|nil error
]]
local function sht30_read()
    -- 构建 MODBUS-RTU 请求帧: FC 0x04 读 Input Register
    local req = string.char(
        SHT30_SLAVE_ID,         -- 从机地址
        0x04,                   -- 功能码: Read Input Registers
        0x00, 0x00,             -- 起始地址 0x0000 (温度)
        0x00, SHT30_REG_COUNT   -- 寄存器数量 2
    )
    local crc = crc16_modbus(req)
    req = req .. string.char(crc % 256, bit.rshift(crc, 8) % 256)

    log.info("sht30_win", "发送 MODBUS 请求 " .. #req .. "字节: " .. req:toHex())

    -- 通过 rs485_app 发送，指定自定义波特率 9600，等待响应
    sys.publish("RS485_SEND_REQUEST", SHT30_PORT, req, READ_TIMEOUT, SHT30_BAUD)

    -- 等待 rs485_app 返回结果
    local ok, port, resp_data, err = sys.waitUntil("RS485_SEND_RESULT", READ_TIMEOUT + 2000)

    if not ok then
        return nil, nil, "发送超时"
    end

    if err then
        return nil, nil, err
    end

    if not resp_data or #resp_data == 0 then
        return nil, nil, "无响应（检查接线/从机地址/波特率）"
    end

    log.info("sht30_win", "接收 " .. #resp_data .. "字节: " .. resp_data:toHex())

    -- 校验 CRC
    if #resp_data < 5 then
        return nil, nil, "响应太短: " .. #resp_data .. "字节"
    end
    local resp_crc = crc16_modbus(resp_data:sub(1, -3))
    local recv_crc = resp_data:byte(-2) + resp_data:byte(-1) * 256
    if resp_crc ~= recv_crc then
        return nil, nil, string.format("CRC错误 calc=%04X recv=%04X", resp_crc, recv_crc)
    end

    -- 校验功能码
    local fc = resp_data:byte(2)
    if fc == bit.bor(0x04, 0x80) then
        return nil, nil, "异常响应 FC=" .. string.format("0x%02X", fc)
    end
    if fc ~= 0x04 then
        return nil, nil, "FC不匹配: " .. string.format("0x%02X", fc)
    end

    -- 解析数据: byte3=数据长度, byte4-5=温度, byte6-7=湿度
    local data_len = resp_data:byte(3)
    if data_len ~= 4 then
        return nil, nil, "数据长度异常: " .. tostring(data_len)
    end

    local raw_temp = resp_data:byte(4) * 256 + resp_data:byte(5)
    local raw_humid = resp_data:byte(6) * 256 + resp_data:byte(7)

    -- 温度补码处理：>0x7FFF 为负数
    local temp
    if raw_temp > 0x7FFF then
        temp = (raw_temp - 0x10000) * 0.1
    else
        temp = raw_temp * 0.1
    end
    local humid = raw_humid * 0.1

    return temp, humid, nil
end

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function sht30_poll_task()
    log.info("sht30_win", "轮询开始, 从机=0x" .. string.format("%02X", SHT30_SLAVE_ID)
        .. " Port" .. SHT30_PORT .. " " .. SHT30_BAUD .. "bps")

    local poll_count = 0
    while running do
        poll_count = poll_count + 1

        local ok, temp, humid, err = pcall(sht30_read)

        if not running then break end

        if not ok then
            log.error("sht30_win", "第" .. poll_count .. "次 pcall异常: " .. tostring(temp))
            if status_label then
                status_label:set_text("异常")
                status_label:set_color(T.COLOR_DANGER)
            end
            if error_label then error_label:set_text(tostring(temp)) end
        elseif err then
            log.warn("sht30_win", "第" .. poll_count .. "次失败: " .. err)
            if status_label then
                status_label:set_text("通信异常")
                status_label:set_color(T.COLOR_DANGER)
            end
            if error_label then error_label:set_text(err) end
            if temp_label then temp_label:set_text("-- °C") end
            if humid_label then humid_label:set_text("-- %RH") end
        else
            log.info("sht30_win", "第" .. poll_count .. "次成功: " .. string.format("%.1f°C %.1f%%RH", temp, humid))
            if status_label then
                status_label:set_text("已连接")
                status_label:set_color(T.COLOR_GREEN)
            end
            if temp_label then temp_label:set_text(string.format("%.1f °C", temp)) end
            if humid_label then humid_label:set_text(string.format("%.1f %%RH", humid)) end
            if error_label then error_label:set_text("") end
        end

        sys.wait(POLL_INTERVAL)
    end
    log.info("sht30_win", "轮询结束")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "SHT30 温湿度", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 连接状态
    local _, _, status_content = T.info_card(content, 6, 44, "连接状态", "初始化中...")
    status_label = status_content

    -- 温度卡片
    local temp_card = airui.container({ parent = content, x = T.MARGIN, y = 58, w = 220, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = temp_card, x = 10, y = 6, w = 200, h = 20, text = "温度", font_size = T.FONT_CARD_TITLE, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    temp_label = airui.label({ parent = temp_card, x = 10, y = 28, w = 200, h = 36, text = "-- °C", font_size = 28, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 湿度卡片
    local humid_card = airui.container({ parent = content, x = T.MARGIN + 232, y = 58, w = 220, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = humid_card, x = 10, y = 6, w = 200, h = 20, text = "湿度", font_size = T.FONT_CARD_TITLE, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    humid_label = airui.label({ parent = humid_card, x = 10, y = 28, w = 200, h = 36, text = "-- %RH", font_size = 28, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 错误信息
    error_label = airui.label({ parent = content, x = T.MARGIN, y = 136, w = T.CARD_W, h = 20, text = "", font_size = T.FONT_SMALL, color = T.COLOR_DANGER, align = airui.TEXT_ALIGN_LEFT })

    -- 配置信息
    local cfg_card = airui.container({ parent = content, x = T.MARGIN, y = 160, w = T.CARD_W, h = 56, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = cfg_card, x = 10, y = 4, w = T.CARD_W - 20, h = 20, text = "配置信息", font_size = T.FONT_CARD_TITLE, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = cfg_card, x = 10, y = 26, w = T.CARD_W - 20, h = 24, text = string.format("从机:0x%02X Port%d %dbps FC:0x04", SHT30_SLAVE_ID, SHT30_PORT, SHT30_BAUD), font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
end

local function on_create()
    running = true
    create_ui()
    sys.taskInit(sht30_poll_task)
end

local function on_destroy()
    running = false
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    temp_label = nil
    humid_label = nil
    status_label = nil
    error_label = nil
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_lose_focus = on_lose_focus,
            on_get_focus = on_get_focus,
        })
    end
end

sys.subscribe("OPEN_SHT30_WIN", open_handler)
