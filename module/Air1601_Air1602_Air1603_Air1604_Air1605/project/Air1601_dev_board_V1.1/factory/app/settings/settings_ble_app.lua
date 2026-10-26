--[[
@module  settings_ble_app
@summary 蓝牙(BLE)测试业务层（设置页入口 · Air5101S 串口蓝牙模块）
@version 1.0
@date    2026.10.26
@author  江访
@usage
本模块是蓝牙测试页的业务层，只做「开串口 / 切 AT 模式 / 发一包 / 收一包」，不保存历史。

底层用的是扩展库 script/libs/exril_5101.lua（Air5101S 串口 BLE 模块的 AT 封装）。

消息协议:
订阅: BLE_OPEN_REQ                 → 打开蓝牙（切 AT 模式 + 配置设备名 + 查设备信息）
订阅: BLE_CLOSE_REQ                → 关闭（退出页面时释放串口）
订阅: BLE_SEND_REQ(data)           → 发送一包（不带参数时发配置里的 test_data，纯字符串，不转 HEX）
订阅: BLE_DISCONNECT_REQ           → 主动断开当前手机连接
发布: BLE_OPEN_RESULT(ok, err, info)  info = { name, uart_id, baud, dev_name, mac, ver, test_data, connected, running }
发布: BLE_SEND_RESULT(ok, err, body)  body = 实际发出去的文本（AT 模式有长度上限，会被截断）
发布: BLE_STATUS(connected)        手机连接 / 断开
发布: BLE_RX(data)                 收到的一包原文（原样字符串，不做 HEX 转换）
发布: BLE_NOTE(text)               附加提示（断开结果 / 模块错误码 / 模块重启）

=== 串口占用（重要）===
Air5101S 挂在这块板子的 UART3 上，和 4G / WiFi / GNSS 是同一条线（底板靠硬件切换选路）。
net_manager 在启动时就会按 2Mbps 把 UART3 开给 4G，所以这里打开前必须先 uart.close
把口抢回来，再按 9600 重开，否则 uart.setup 会被 C 层直接跳过（日志 "uart3 is opened!"），
表现就是发指令没有任何回包。GNSS 测试页是同一套做法（见 settings_gnss_app.lua）。

退出页面会 uart.close 释放串口，但**不会**把 UART3 还给 4G：需要 4G 联网就重启设备。
]]

-- 缺省测试内容（config 里写了 test_data 以配置为准）
local DEFAULT_TEST_DATA = "BLE test"
-- 缺省蓝牙设备名（手机搜到的名字，不超过 20 字符）
local DEFAULT_DEV_NAME = "Air1601_Test"
-- 未配置 peripherals 时的兜底硬件参数（开发板 V1.1：UART3 / 9600）
local FALLBACK_PARAMS = {
    id = "ble_1", name = "蓝牙", uart_id = 3, baud = 9600,
    dev_name = DEFAULT_DEV_NAME, test_data = DEFAULT_TEST_DATA,
}

-- AT 模式下单包最多 80 字节；留点余量给 AT+BS= 之后的空格/CRLF
local MAX_AT_SEND_LEN = 60

local lib = nil             -- exril_5101，用到时才 require
local lib_tried = false
local params = nil
local running = false       -- 蓝牙是否已打开（串口已就绪）
local connected = false     -- 手机是否已连上
local dev = { name = nil, mac = nil, ver = nil }  -- 模块自报的名称 / MAC / 版本

-- ==================== 参数 ====================

--[[取本机型声明的 ble 配置条目（取第一条）]]
local function find_params()
    local list = _G.project_config and _G.project_config.peripherals
    if type(list) ~= "table" then return nil end
    for _, p in ipairs(list) do
        if p and p.type == "ble" then return p end
    end
    return nil
end

local function get_params()
    if params then return params end
    params = find_params() or FALLBACK_PARAMS
    return params
end

local function uart_id()
    return get_params().uart_id or 3
end

local function baudrate()
    return get_params().baud or 9600
end

local function dev_name()
    local p = get_params()
    return tostring(p.dev_name or p.name or DEFAULT_DEV_NAME)
end

local function test_data()
    return tostring(get_params().test_data or DEFAULT_TEST_DATA)
end

--[[端口描述，给 UI 显示]]
local function port_info()
    local p = get_params()
    return {
        name      = p.name or "蓝牙",
        uart_id   = uart_id(),
        baud      = baudrate(),
        dev_name  = dev.name or dev_name(),
        mac       = dev.mac,
        ver       = dev.ver,
        test_data = test_data(),
        connected = connected,
        running   = running,
    }
end

--[[取扩展库：
exril_5101 在 require 的那一刻就会 uart.setup(UART_ID=1, 9600) 并挂 AT 接收回调，
这里用 pcall 兜一层，库没打进包里时只在页面上报错，不至于把整个 app 带崩。
（platform_loader 里已登记打包，并紧接着 uart.close(1) 把那个默认槽位释放掉。）]]
local function get_lib()
    if lib_tried then return lib end
    lib_tried = true
    local ok, m = pcall(require, "exril_5101")
    if ok and type(m) == "table" then
        lib = m
    else
        log.error("settings_ble", "加载扩展库 exril_5101 失败", tostring(m))
    end
    return lib
end

-- ==================== 事件回调 ====================

local function ble_event_cb(event, payload)
    payload = payload or {}
    if event == "connected" then
        connected = true
        log.info("settings_ble", "手机已连接")
        sys.publish("BLE_STATUS", true)

    elseif event == "disconnected" then
        connected = false
        log.info("settings_ble", "手机已断开")
        sys.publish("BLE_STATUS", false)

    elseif event == "data" then
        local data = payload.data
        if type(data) == "string" and #data > 0 then
            sys.publish("BLE_RX", data)
        end

    elseif event == "error" then
        log.warn("settings_ble", "模块错误码", tostring(payload.error_type), tostring(payload.error_code))
        sys.publish("BLE_NOTE", "模块返回错误码 " .. tostring(payload.error_code))

    elseif event == "system" then
        -- 模块自己重启了（掉电/看门狗），此时之前配置与连接状态都失效
        if payload.type == "mac" then
            connected = false
            running = false
            log.warn("settings_ble", "蓝牙模块已重启")
            sys.publish("BLE_STATUS", false)
            sys.publish("BLE_NOTE", "蓝牙模块已重启，请退出重进本页")
        end
    end
end

-- ==================== 打开 / 关闭 ====================
--[[打开、发送都要放进 sys.taskInit 里跑：
exril_5101 的同步接口内部靠 sys.wait 轮询等回包，
在 sys.subscribe 的派发上下文（非协程）里会被整段跳过，表现就是「点了没反应」。]]

local function do_open()
    local l = get_lib()
    if not l then
        sys.publish("BLE_OPEN_RESULT", false, "扩展库 exril_5101 加载失败", port_info())
        return
    end
    if running then
        sys.publish("BLE_OPEN_RESULT", true, nil, port_info())
        return
    end

    -- UART3 口复用校验：当前通道不是「蓝牙」时禁止抢这条串口。
    -- 否则通道选 4G / WiFi 的板子进本页会把正在联网的模组直接踢下线。
    local ch = require "settings_channel_app"
    local ch_mode = ch.get()
    if ch_mode ~= "ble" then
        sys.publish("BLE_OPEN_RESULT", false,
            "当前 UART3 通道为 " .. ch.label(ch_mode) .. "，请先在「设置 → UART3口复用」切到蓝牙", port_info())
        return
    end

    local uid = uart_id()
    local baud = baudrate()

    -- 把 UART3 从 4G / GNSS 手里抢回来（不 close 的话后面 setup 会被 C 层跳过）
    pcall(uart.close, uid)
    l.config_uart(uid, baud)
    -- 首次 config_uart 里已经 setup 过；再次进入本页时串口被 close 过，这里重新打开。
    -- 已经开着时 C 层会跳过这次 setup，返回 false 属正常，不当作错误。
    pcall(uart.setup, uid, baud)
    -- require 时库把 UART1 按 9600 打开了，不是本次要用的口，随手释放掉
    if uid ~= 1 then pcall(uart.close, 1) end

    -- 先接管事件（初始化过程中模块重启发来的 Mac: 也能收到）
    l.on(ble_event_cb)

    -- 1. 切 AT 指令模式：能配置参数，收到的数据带 AT: 前缀，便于页面直接显示
    local ok_mode, mode_err = l.mode(l.MODE_AT)
    if not ok_mode then
        log.error("settings_ble", "切换 AT 模式失败", tostring(mode_err))
        pcall(uart.close, uid)
        sys.publish("BLE_OPEN_RESULT", false,
            "模块无响应：" .. tostring(mode_err or "未知原因") .. "（串口被占用或模块未接）", port_info())
        return
    end

    -- 2. 配置设备名（手机搜到的名字），失败不致命，继续查信息
    --    这里只写 name：mtu_len / conn_interval 属于连接后才能设的参数，
    --    未连接时库会告警跳过，别在这里一起下发
    local name = dev_name()
    local ok_set, set_err = l.set({ name = name })
    if not ok_set then
        log.warn("settings_ble", "配置设备参数失败", tostring(set_err))
    end

    -- 3. 查设备信息（名称 / MAC / 固件版本）
    local info, get_err = l.get({ "name", "mac", "ver" })
    if type(info) == "table" then
        dev.name = info.name
        dev.mac = info.mac
        dev.ver = info.ver
    else
        log.warn("settings_ble", "查询设备信息失败", tostring(get_err))
    end

    -- 4. 同步一次连接状态（模块可能在上次退出时仍连着手机）
    local ok_st, st = l.status()
    if ok_st then
        if type(st) == "table" then
            connected = st.connected == true
        elseif type(st) == "boolean" then
            connected = st
        end
    end

    running = true
    log.info("settings_ble", "蓝牙已打开", "UART" .. tostring(uid), tostring(baud), name)
    sys.publish("BLE_OPEN_RESULT", true, nil, port_info())
end

local function do_close()
    if lib then pcall(uart.close, uart_id()) end
    running = false
    connected = false
    log.info("settings_ble", "蓝牙已关闭", "UART" .. tostring(uart_id()))
    sys.publish("BLE_OPEN_RESULT", false, "已关闭", port_info())
end

sys.subscribe("BLE_OPEN_REQ", function()
    sys.taskInit(do_open)
end)

sys.subscribe("BLE_CLOSE_REQ", function()
    if not lib then
        running = false
        connected = false
        return
    end
    do_close()
end)

-- ==================== 发送 / 断开 ====================

sys.subscribe("BLE_SEND_REQ", function(data)
    sys.taskInit(function()
        local l = get_lib()
        if not l then
            sys.publish("BLE_SEND_RESULT", false, "扩展库 exril_5101 加载失败")
            return
        end
        if not running then
            sys.publish("BLE_SEND_RESULT", false, "蓝牙未打开")
            return
        end

        local body = tostring(data or test_data())
        -- AT+BS= 是一行指令，数据里不能带 CR/LF，否则指令被截断
        body = body:gsub("[\r\n]+", " ")
        if #body > MAX_AT_SEND_LEN then
            body = string.sub(body, 1, MAX_AT_SEND_LEN)
        end

        local ok, err = l.send(body)
        log.info("settings_ble", "发送", body, tostring(ok), tostring(err))
        sys.publish("BLE_SEND_RESULT", ok and true or false, ok and nil or tostring(err), body)
    end)
end)

sys.subscribe("BLE_DISCONNECT_REQ", function()
    sys.taskInit(function()
        local l = get_lib()
        if not l or not running then
            sys.publish("BLE_NOTE", "蓝牙未打开")
            return
        end
        if not connected then
            sys.publish("BLE_NOTE", "当前没有已连接的手机")
            return
        end
        local ok, err = l.disconnect()
        if ok then
            connected = false
            sys.publish("BLE_STATUS", false)
            sys.publish("BLE_NOTE", "已断开连接")
        else
            sys.publish("BLE_NOTE", "断开失败：" .. tostring(err or "未知原因"))
        end
    end)
end)
