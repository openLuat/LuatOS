--[[
@module  settings_rs485_app
@summary RS485 测试业务层（设置页入口 · UART2 + GPIO64 方向脚 + GPIO46 收发器使能）
@version 1.0
@date    2026.10.26
@author  江访
@usage
本模块是 RS485 测试页的业务层，只做「开串口 / 发一帧 / 收一帧」，不保存历史。

消息协议:
订阅: RS485_OPEN_REQ              → 打开串口（DE 置接收态）
订阅: RS485_CLOSE_REQ             → 关闭串口（退出页面时释放 UART2）
订阅: RS485_SEND_REQ(data)        → 发送一帧（缺省发 TEST_DATA，纯字符串，不转 HEX）
发布: RS485_OPEN_RESULT(ok, err, info)  info = { uart_id, de_pin, baud, test_data, name }
发布: RS485_SEND_RESULT(ok, err)
发布: RS485_RX(data)              收到的一帧原文（原样字符串，不做 HEX 转换）

硬件来自 config.peripherals 里 type="rs485" 的条目（本板 UART2 / DE=GPIO64 / 485_EN=GPIO46）；
驱动是 drv/periph/periph_rs485.lua，由 periph_loader 在可选批登记，
本模块取用时才查表（get 不到就自己 init，保证「页面先开、外设后登记」也能用）。
]]

local drv = require "periph_rs485"

-- 固定测试内容（config 里写了 test_data 以配置为准）
local DEFAULT_TEST_DATA = "RS485 test"
-- 未配置 peripherals 时的兜底硬件参数（EVB_Air1602 V1.2：UART2 + DE=GPIO64 + 485_EN=GPIO46）
local FALLBACK_PARAMS = {
    id = "rs485_1", name = "RS485", uart_id = 2,
    de_pin = 64, power_pin = 46, power_hold = true, baud = 9600,
}

local handle = nil
local params = nil

--[[取本机型声明的 rs485 配置条目（取第一条）]]
local function find_params()
    local list = _G.project_config and _G.project_config.peripherals
    if type(list) ~= "table" then return nil end
    for _, p in ipairs(list) do
        if p and p.type == "rs485" then return p end
    end
    return nil
end

--[[取得并缓存配置（含固定发送内容）]]
local function get_params()
    if params then return params end
    params = find_params() or FALLBACK_PARAMS
    return params
end

local function test_data()
    return tostring(get_params().test_data or DEFAULT_TEST_DATA)
end

--[[端口描述，给 UI 显示]]
local function port_info()
    local p = get_params()
    return {
        name     = p.name or "RS485",
        uart_id  = p.uart_id or 0,
        de_pin   = p.de_pin,
        baud     = handle and handle.baud or p.baud or 9600,
        test_data = test_data(),
    }
end

--[[取驱动 handle：periph_loader 已登记的直接用，没登记就补登记一次]]
local function get_handle()
    if handle then return handle end
    local p = get_params()
    handle = drv.get(p.id)
    if not handle then
        local ok, h = pcall(drv.init, p)
        if ok and h then
            handle = h
        else
            log.warn("settings_rs485", "RS485 驱动登记失败", tostring(h))
        end
    end
    return handle
end

-- ==================== 打开 / 关闭 ====================
--[[打开 / 发送都放进 sys.taskInit 里跑：
sys.subscribe 的派发上下文不是协程，驱动里的 sys.wait（DE 方向切换等待、自检保持时长）
在非协程里会被整段跳过 —— 表现为「发出去了但对端收不全」或「DE 拉高一闪而过」。]]

sys.subscribe("RS485_OPEN_REQ", function()
    sys.taskInit(function()
        local h = get_handle()
        if not h then
            sys.publish("RS485_OPEN_RESULT", false, "未找到 RS485 驱动", port_info())
            return
        end
        if h.enabled then
            sys.publish("RS485_OPEN_RESULT", true, nil, port_info())
            return
        end
        local ok, err = pcall(h.start, h)
        if not ok then ok, err = false, tostring(err) end
        log.info("settings_rs485", "打开串口", tostring(ok), tostring(err))
        sys.publish("RS485_OPEN_RESULT", ok and true or false, err, port_info())
    end)
end)

sys.subscribe("RS485_CLOSE_REQ", function()
    if not handle then return end
    pcall(handle.stop, handle)
    sys.publish("RS485_OPEN_RESULT", false, "已关闭", port_info())
end)

-- ==================== 发送 ====================

sys.subscribe("RS485_SEND_REQ", function(data)
    sys.taskInit(function()
        local h = get_handle()
        if not h then
            sys.publish("RS485_SEND_RESULT", false, "未找到 RS485 驱动")
            return
        end
        if not h.enabled then
            local ok, err = pcall(h.start, h)
            if not ok then ok, err = false, tostring(err) end
            if not ok then
                sys.publish("RS485_SEND_RESULT", false, "串口打开失败：" .. tostring(err))
                return
            end
            sys.publish("RS485_OPEN_RESULT", true, nil, port_info())
        end
        local body = (type(data) == "string" and #data > 0) and data or test_data()
        local ok, err = pcall(h.send, h, body)
        if not ok then ok, err = false, tostring(err) end
        log.info("settings_rs485", "发送", body, tostring(ok), tostring(err))
        sys.publish("RS485_SEND_RESULT", ok and true or false, err)
    end)
end)

-- ==================== 接收 ====================

-- 驱动按 handle.id 广播，这里过滤成本路的 RS485_RX 给 UI
sys.subscribe("PERIPH_RX", function(id, data)
    local p = get_params()
    if id ~= p.id then return end
    if type(data) ~= "string" or #data == 0 then return end
    sys.publish("RS485_RX", data)
end)
