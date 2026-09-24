--[[
@module  relay_ctrl
@summary 继电器控制模块（8301 非隔离口 UART11，Modbus RTU 主站）
@version 1.2
@date    2026.09.24
@usage
本功能模块演示的内容为：
1、在非隔离485（UART11）上以 Modbus RTU 主站模式控制 4 路继电器模块（从站地址1）
2、封装继电器单路开/关/翻转、全量开/关、状态回读命令
3、通道编号 0~3，与 Modbus 线圈地址 0x0000~0x0003 一一对应

Air8301 硬件说明：
- UART11 的 RS485 方向脚（RE/DE）为 GPIO153，供电脚 GPIO147（由 board_init 拉高）
- 采用 uart.setup 内置 RS485 模式（硬件自动换向），故 exmodbus 的 rs485_dir_gpio 直接填 153
  （exmodbus 内部即把该值作为 uart.setup 的 pin485 参数传入，无需手动 pins.setup）

对外接口：
1、relay_ctrl.open(channel)      → 打开指定通道（0~3）
2、relay_ctrl.close(channel)     → 关闭指定通道
3、relay_ctrl.toggle(channel)    → 翻转指定通道
4、relay_ctrl.all_open()         → 全开 4 路
5、relay_ctrl.all_close()        → 全关 4 路
6、relay_ctrl.read_status()      → 回读继电器状态并广播
7、relay_ctrl.get_channel_count()→ 获取当前继电器路数（唯一配置源，供其他模块查询）
8、relay_ctrl.get_state()        → 获取继电器当前缓存状态

读写方式说明（实测踩坑点）：
本工程实测所用继电器模块的 Modbus 应答不符合标准帧格式（写多线圈回显请求帧、
读线圈末字节丢失），故本模块统一改用 comm_core 的"原始帧 + 自校验"接口：
- 单路开/关  → comm_core.write_coil_raw（0x05）
- 单路翻转  → comm_core.write_raw（0x05 + 0x5500，不重试，避免重复翻转）
- 全开/全关 → comm_core.write_coils_raw（0x0F，容忍应答回显）
- 状态回读  → comm_core.read_coils_raw（0x01，容忍末字节丢失）
]]

local exmodbus = require "exmodbus"
local comm_core = require "comm_core"
local M = {}

-- RS485 方向引脚（8301 非隔离口 UART11，RE/DE = GPIO153）
local rs485_dir_gpio = 153

-- 创建 RTU 主站配置参数（UART11 / 非隔离485）
local create_config = {
    mode = exmodbus.RTU_MASTER,      -- 通信模式：RTU主站
    uart_id = 11,                    -- UART 端口号：11（非隔离485）
    baud_rate = 9600,                -- 波特率：9600（继电器模块出厂默认）
    data_bits = 8,                   -- 数据位：8
    stop_bits = 1,                   -- 停止位：1
    parity_bits = uart.None,         -- 校验位：无
    byte_order = uart.LSB,           -- 字节顺序：LSB（低位优先）
    rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚：153（uart 内置 RS485 自动换向）
    rs485_dir_rx_level = 0,          -- RS485 接收方向电平：0
    concat_timeout = 100,            -- 字符拼接超时时间：100 毫秒
}

-- 从站地址（继电器模块，使用 01）
local SLAVE_ID = 1
-- ==================== 唯一配置源：继电器路数 ====================
-- 换硬件时"只改这一处"：4 路模块填 4，8 路模块填 8。
-- 状态缓存、全开/全关数据表、上层状态编码、Modbus 数量字段均按本值动态生成；
-- 其他模块请调用 relay_ctrl.get_channel_count() 获取，不要自行写死路数。
local CH_COUNT = 4
-- 通道基线地址（通道0=0x0000，通道号即地址偏移）
local CH_BASE_ADDR = 0x0000
-- 通道映射：风扇=通道0、LED=通道1
local CHANNEL = { FAN = 0, LED = 1 }

-- 继电器状态缓存（1-based 数组：relay[1] 对应通道0、relay[2] 对应通道1 ……）
-- 按 CH_COUNT 动态构造，换路数时此处无需改动
local relay_state = {}
for i = 1, CH_COUNT do relay_state[i] = 0 end
-- exmodbus 调试开关（默认关闭，排查总线问题时置 true）
exmodbus.debug(false)

-- 创建 RTU 主站实例
local rtu_master = comm_core.create_master(create_config)
if not rtu_master then
    log.error("relay_ctrl", "RTU 主站创建失败（UART11）")
end

-- 构建带 CRC 的标准 Modbus RTU 原始请求帧
-- @param body string 除 CRC 外的帧体字节串
-- @return string 完整帧（含 CRC，低字节在前）
local function build_raw_frame(body)
    local crc = crypto.crc16_modbus(body)
    return body .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

-- 发布继电器通信日志（供 rs485_win 页面显示）
-- @param text string 日志文本
local function publish_log(text)
    sys.publish("MODBUS_MASTER_LOG", text)
end

-- 写单个线圈（开/关用字段参数 0x05；翻转用 raw_request 0x5500）
-- @param channel number 通道号（0~3）
-- @param state string "open" / "close" / "toggle"
-- @return boolean 是否成功
local function write_single_coil(channel, state)
    if not rtu_master then return false end
    -- 通道号即线圈地址偏移（通道0 → 0x0000，通道3 → 0x0003）
    local addr = CH_BASE_ADDR + channel
    local status

    if state == "toggle" then
        -- 翻转：功能码 0x05，数据 0x5500（字段参数方式不支持，必须用原始帧）
        local frame = build_raw_frame(string.char(
            SLAVE_ID,                 -- 从站地址
            0x05,                     -- 功能码：写单个线圈
            (addr >> 8) & 0xFF, addr & 0xFF, -- 线圈地址
            0x55, 0x00                -- 数据：0x5500 翻转
        ))
        -- 走 comm_core.write_raw：自带总线串行 + 应答校验（库的 raw_request 分支本身不校验）
        -- 注意：翻转命令不做重试，避免一次操作被重复执行导致状态错乱
        status, _ = comm_core.write_raw(rtu_master, {
            slave_id = SLAVE_ID,
            func_code = 0x05,
            raw_request = frame,
            timeout = 1000,
        })
        if status == exmodbus.STATUS_SUCCESS then
            -- 更新缓存：翻转即取反（channel+1 为 1-based 数组下标）
            relay_state[channel + 1] = (relay_state[channel + 1] == 0) and 1 or 0
        end
    else
        -- 开/关：原始帧方式（0x05，容忍模块回显应答）
        local value = (state == "open") and 1 or 0
        status, _ = comm_core.write_coil_raw(rtu_master, {
            slave_id = SLAVE_ID,
            start_addr = addr,
            value = value,
            timeout = 1000,
        })
        if status == exmodbus.STATUS_SUCCESS then
            relay_state[channel + 1] = value
        end
    end

    if status == exmodbus.STATUS_SUCCESS then
        log.info("relay_ctrl", "通道" .. channel .. "(" .. state .. ") 成功")
        publish_log("[主站] 通道" .. channel .. " " .. state .. " 成功")
        -- 执行后广播最新状态
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return true
    end
    log.warn("relay_ctrl", "通道" .. channel .. "(" .. state .. ") 失败, 状态=", status)
    publish_log("[主站] 通道" .. channel .. " " .. state .. " 失败(" .. tostring(status) .. ")")
    return false
end

-- 写多个线圈（全开/全关用功能码 0x0F）
-- @param vals table 各通道状态（0/1 数组）
-- @return boolean 是否成功
local function write_multiple_coils(vals)
    if not rtu_master then return false end
    local data = {}
    for i = 1, CH_COUNT do
        data[CH_BASE_ADDR + (i - 1)] = vals[i]
    end
    local status, _ = comm_core.write_coils_raw(rtu_master, {
        slave_id = SLAVE_ID,
        start_addr = CH_BASE_ADDR,
        count = CH_COUNT,
        data = data,
        timeout = 1000,
    })
    if status == exmodbus.STATUS_SUCCESS then
        for i = 1, CH_COUNT do relay_state[i] = vals[i] end
        log.info("relay_ctrl", "多线圈写入成功")
        publish_log("[主站] 多线圈写入成功")
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return true
    end
    log.warn("relay_ctrl", "多线圈写入失败, 状态=", status)
    publish_log("[主站] 多线圈写入失败(" .. tostring(status) .. ")")
    return false
end

-- 打开指定通道（0~3）
function M.open(channel)
    if channel < 0 or channel > CH_COUNT - 1 then
        log.warn("relay_ctrl", "非法通道号", channel)
        return false
    end
    return write_single_coil(channel, "open")
end

-- 关闭指定通道（0~3）
function M.close(channel)
    if channel < 0 or channel > CH_COUNT - 1 then
        log.warn("relay_ctrl", "非法通道号", channel)
        return false
    end
    return write_single_coil(channel, "close")
end

-- 翻转指定通道（0~3）
function M.toggle(channel)
    if channel < 0 or channel > CH_COUNT - 1 then
        log.warn("relay_ctrl", "非法通道号", channel)
        return false
    end
    return write_single_coil(channel, "toggle")
end

-- 全开（按 CH_COUNT 动态生成：4 路模块即 4 路全开，8 路模块即 8 路全开）
function M.all_open()
    local vals = {}
    for i = 1, CH_COUNT do vals[i] = 1 end
    return write_multiple_coils(vals)
end

-- 全关（按 CH_COUNT 动态生成）
function M.all_close()
    local vals = {}
    for i = 1, CH_COUNT do vals[i] = 0 end
    return write_multiple_coils(vals)
end

-- 回读继电器线圈状态（功能码 0x01）并广播
-- @return table 状态数组，nil 表示失败
function M.read_status()
    if not rtu_master then return nil end
    -- 原始帧方式（0x01）：容忍模块应答末字节丢失，避免库因"数据长度不匹配"整体判失败
    local coils = comm_core.read_coils_raw(rtu_master, {
        slave_id = SLAVE_ID,
        start_addr = CH_BASE_ADDR,
        count = CH_COUNT,
        timeout = 1000,
    })
    if coils then
        for i = 1, CH_COUNT do
            relay_state[i] = coils[CH_BASE_ADDR + (i - 1)] or 0
        end
        log.info("relay_ctrl", "回读继电器状态:", table.concat(relay_state, ","))
        publish_log("[主站] 回读状态:" .. table.concat(relay_state, ","))
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return relay_state
    end
    log.warn("relay_ctrl", "回读继电器状态失败")
    publish_log("[主站] 回读状态失败")
    return nil
end

-- 获取当前继电器路数（唯一配置源的对外出口，供 aircloud_data / app_main 等模块查询）
-- @return number 路数（4 路模块返回 4，8 路模块返回 8）
function M.get_channel_count()
    return CH_COUNT
end

-- 获取当前通道映射（供业务/命令层使用）
function M.get_channel_map()
    return { fan = CHANNEL.FAN, led = CHANNEL.LED }
end

-- 获取继电器当前缓存状态
function M.get_state()
    return relay_state
end

-- ==================== 消息接口（非协程上下文防护） ====================
--[[
RELAY_SET_REQ 消费方式说明（重要）：

httpsrv 的 HTTP 回调、Modbus 从站的请求回调、以及 sys.subscribe 注册的消息回调，
三者全部运行在「非协程」上下文（C 层 socket 回调 / sys.run 消息分发循环）中。
在这些上下文里直接调用 M.open / M.all_open 等函数，其内部链路为
    relay_ctrl → comm_core → exmodbus → sys.waitUntil（等待 485 主站应答）
sys.waitUntil 会挂起当前协程，而非协程上下文无法挂起，于是触发
    "attempt to yield from outside a coroutine"
并导致 Lua VM 退出、整机 15 秒后重启。

因此本模块改为「请求入队 + 常驻协程串行执行」：
1、外部任意模块（网页 / 屏幕 / 云端 / Modbus 从站）只需
   sys.publish("RELAY_SET_REQ", channel, action) 投递请求，立即返回；
2、on_relay_set_req 回调仅做入队，绝不调用会 yield 的函数；
3、relay_exec_task 常驻协程按入队顺序串行执行，天然避免多入口并发抢占 485 总线。
]]

-- 请求队列（1-based 数组，元素为 { channel = xxx, action = xxx }）
local request_queue = {}

--[[
RELAY_SET_REQ 订阅回调：仅将请求入队，由常驻协程串行执行

@local
@function on_relay_set_req
@param channel number 通道号（0~3），全量操作为 nil
@param action string 动作 open/close/toggle/all_open/all_close/read
]]
local function on_relay_set_req(channel, action)
    request_queue[#request_queue + 1] = { channel = channel, action = action }
    -- 唤醒消费协程（sys.publish 不挂起，非协程上下文可安全调用）
    sys.publish("RELAY_EXEC_TICK")
end

--[[
执行单个继电器请求（仅允许在协程内被调用）

@local
@function exec_relay_action
@param channel number 通道号（0~3），全量操作为 nil
@param action string 动作 open/close/toggle/all_open/all_close/read
]]
local function exec_relay_action(channel, action)
    if action == "all_open" then
        M.all_open()
    elseif action == "all_close" then
        M.all_close()
    elseif action == "read" then
        M.read_status()
    elseif action == "open" and channel ~= nil then
        M.open(channel)
    elseif action == "close" and channel ~= nil then
        M.close(channel)
    elseif action == "toggle" and channel ~= nil then
        M.toggle(channel)
    else
        log.warn("relay_ctrl", "无效的继电器操作请求:", tostring(channel), tostring(action))
    end
end

--[[
常驻消费协程：循环取出队列中的请求并串行执行

@local
@function relay_exec_task
]]
local function relay_exec_task()
    while true do
        sys.waitUntil("RELAY_EXEC_TICK")
        -- 一次性清空队列：执行期间新入队的请求由本循环继续处理，不丢失
        while #request_queue > 0 do
            local req = table.remove(request_queue, 1)
            exec_relay_action(req.channel, req.action)
        end
    end
end

sys.subscribe("RELAY_SET_REQ", on_relay_set_req)
sys.taskInit(relay_exec_task)

return M
