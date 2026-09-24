--[[
@module  relay_ctrl
@summary 485继电器控制模块（隔离口 UART1）
@version 1.0
@date    2026.09.24
@usage
本功能模块演示的内容为：
1、在隔离485（UART1）上以 Modbus RTU 主站模式控制 4 路继电器模块（从站地址1）
2、封装继电器单路开/关/翻转、全量开/关、状态回读命令
3、通道编号 0~3，与 Modbus 线圈地址 0x0000~0x0003 一一对应，业务上命名为"继电器1~继电器4"
4、周期性（默认 5 秒）自动回读 4 路线圈状态并广播，保证 Web 页面 / Modbus 从站寄存器 /
   AirCloud 云端显示的状态与继电器实际状态一致（避免只依赖本地缓存造成状态漂移）
5、本模块是 4 路继电器状态的唯一数据源（零重复采集）


对外接口：
1、relay_ctrl.open(channel)       → 打开指定通道（0~3）
2、relay_ctrl.close(channel)      → 关闭指定通道（0~3）
3、relay_ctrl.toggle(channel)     → 翻转指定通道（0~3）
4、relay_ctrl.all_open()          → 全开 4 路
5、relay_ctrl.all_close()         → 全关 4 路
6、relay_ctrl.read_status()       → 回读继电器状态并广播
7、relay_ctrl.get_channel_count() → 获取当前继电器路数（唯一配置源，供其他模块查询）
8、relay_ctrl.get_state()         → 获取继电器当前缓存状态（1-based 数组）

对外发布的消息（供 httpsrv_web / rtu_slave_regmap / aircloud_data 订阅）：
1、sys.publish("RELAY_STATUS_UPDATE", relay_state)   -- 4 路状态数组（1-based，元素 0/1）
2、sys.publish("RELAY_OP_LOG", msg)                  -- 继电器操作日志（字符串，供 Web 页面显示）
]]

local exmodbus = require "exmodbus"
local comm_core = require "comm_core"
local M = {}

-- 隔离485对应 UART1，管脚方向脚 GPIO37
pins.setup(28, "GPIO37")        -- 隔离485 方向脚复用（UART1）
-- 说明：RS485 芯片电源脚（GPIO29）的引脚复用与拉高已统一由 net_drv / rtu_slave_regmap 初始化，避免多处重复 setup

-- RS485 方向引脚（隔离口）
local rs485_dir_gpio = 37

-- 创建 RTU 主站配置参数（UART1 / 隔离485）
local create_config = {
    mode = exmodbus.RTU_MASTER,      -- 通信模式：RTU主站
    uart_id = 1,                     -- UART 端口号：1（隔离485）
    baud_rate = 9600,                -- 波特率：9600
    data_bits = 8,                   -- 数据位：8
    stop_bits = 1,                   -- 停止位：1
    parity_bits = uart.None,         -- 校验位：无
    byte_order = uart.LSB,           -- 字节顺序：LSB（低位优先）
    rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚：37
    rs485_dir_rx_level = 0,          -- RS485 接收方向电平：0
    concat_timeout = 100,            -- 字符拼接超时时间：100 毫秒
}

-- 从站地址（继电器模块，按用户确认使用 01）
local SLAVE_ID = 1
-- ==================== 唯一配置源：继电器路数 ====================
-- 换硬件时"只改这一处"：4 路模块填 4，8 路模块填 8。
-- 状态缓存、全开/全关数据表、上层状态编码、Modbus 数量字段均按本值动态生成；
-- 其他模块请调用 relay_ctrl.get_channel_count() 获取，不要自行写死路数。
local CH_COUNT = 4
-- 通道基线地址（通道0=0x0000，通道号即地址偏移）
local CH_BASE_ADDR = 0x0000
-- 继电器状态回读周期（毫秒）：保证页面/寄存器/云端状态与设备实际状态一致
-- 说明：由 5000 缩短为 2000，提升"外部改变继电器状态"时 Web 页面 / Modbus 寄存器 / 云端的同步实时性
local POLL_INTERVAL = 2000

-- 继电器状态缓存（1-based 数组：relay_state[1] 对应通道0（继电器1）、relay_state[2] 对应通道1（继电器2）……）
-- 按 CH_COUNT 动态构造，换路数时此处无需改动
local relay_state = {}
for i = 1, CH_COUNT do relay_state[i] = 0 end
-- 回读日志节流：连续失败计数（成功即归零）+ 上次状态字符串（状态未变化时不重复打印 info）
local read_fail_streak = 0
local last_state_str = nil
-- 485 原始帧调试开关：需要抓取 Modbus 收发原始字节时置为 true，
-- 日志 TAG 为 exmodbus.debug（打印接收到的原始数据），用于定位丢字节/帧不完整问题。
-- 【临时开启】当前现场需抓取库层原始帧以判定"丢末字节"发生在 UART 层还是库层，
--           抓取完成后请改回 false（该开关会打印全部收发原始字节，比较占日志）。
local DEBUG_RAW = true
exmodbus.debug(DEBUG_RAW)

-- 创建 RTU 主站实例
local rtu_master = comm_core.create_master(create_config)
if not rtu_master then
    log.error("relay_ctrl", "RTU 主站创建失败（UART1）")
end

-- 构建带 CRC 的标准 Modbus RTU 原始请求帧
-- @param body string 除 CRC 外的帧体字节串
-- @return string 完整帧（含 CRC，低字节在前）
local function build_raw_frame(body)
    local crc = crypto.crc16_modbus(body)
    return body .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
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
        -- 开/关：字段参数方式（0x05，库自动转 0xFF00/0x0000）
        local value = (state == "open") and 1 or 0
        status, _ = comm_core.write_coil(rtu_master, {
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
        log.info("relay_ctrl", "继电器" .. (channel + 1) .. "(" .. state .. ") 成功")
        -- 执行后广播最新状态与操作日志
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        sys.publish("RELAY_OP_LOG", "继电器" .. (channel + 1) .. " " .. state .. " 成功")
        return true
    end
    log.warn("relay_ctrl", "继电器" .. (channel + 1) .. "(" .. state .. ") 失败, 状态=", status)
    sys.publish("RELAY_OP_LOG", "继电器" .. (channel + 1) .. " " .. state .. " 失败")
    return false
end

-- 写多个线圈（全开/全关用功能码 0x0F）
-- @param vals table 各通道状态（0/1 数组）
-- @param op string 操作名（"全开" / "全关"，用于日志）
-- @return boolean 是否成功
local function write_multiple_coils(vals, op)
    if not rtu_master then return false end
    local data = {}
    for i = 1, CH_COUNT do
        data[CH_BASE_ADDR + (i - 1)] = vals[i]
    end
    local status, _ = comm_core.write_coils(rtu_master, {
        slave_id = SLAVE_ID,
        start_addr = CH_BASE_ADDR,
        count = CH_COUNT,
        data = data,
        timeout = 1000,
    })
    if status == exmodbus.STATUS_SUCCESS then
        for i = 1, CH_COUNT do relay_state[i] = vals[i] end
        log.info("relay_ctrl", "多线圈写入成功(" .. op .. ")")
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        sys.publish("RELAY_OP_LOG", op .. " 成功")
        return true
    end
    log.warn("relay_ctrl", "多线圈写入失败(" .. op .. "), 状态=", status)
    sys.publish("RELAY_OP_LOG", op .. " 失败")
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
    return write_multiple_coils(vals, "全开")
end

-- 全关（按 CH_COUNT 动态生成）
function M.all_close()
    local vals = {}
    for i = 1, CH_COUNT do vals[i] = 0 end
    return write_multiple_coils(vals, "全关")
end

-- 回读继电器线圈状态（功能码 0x01）并广播
-- @return table 状态数组，nil 表示失败
function M.read_status()
    if not rtu_master then return nil end
    local coils = comm_core.read_coils(rtu_master, {
        slave_id = SLAVE_ID,
        start_addr = CH_BASE_ADDR,
        count = CH_COUNT,
        timeout = 1000,
    })
    if coils then
        -- 成功：清零连续失败计数
        read_fail_streak = 0
        for i = 1, CH_COUNT do
            relay_state[i] = coils[CH_BASE_ADDR + (i - 1)] or 0
        end
        -- 仅当状态发生变化时才打印 info，避免 2 秒周期回读刷屏
        local state_str = table.concat(relay_state, ",")
        if state_str ~= last_state_str then
            last_state_str = state_str
            log.info("relay_ctrl", "回读继电器状态变化:", state_str)
        end
        sys.publish("RELAY_STATUS_UPDATE", relay_state)
        return relay_state
    end
    -- 失败降噪：连续失败每达到 3 次才打印一条 warn（2 秒周期回读时不刷屏）
    read_fail_streak = read_fail_streak + 1
    if read_fail_streak % 3 == 0 then
        log.warn("relay_ctrl", "回读继电器状态失败, 连续失败", read_fail_streak, "次")
    end
    return nil
end

-- 获取当前继电器路数（唯一配置源的对外出口，供 aircloud_data / httpsrv_web 等模块查询）
-- @return number 路数（4 路模块返回 4，8 路模块返回 8）
function M.get_channel_count()
    return CH_COUNT
end

-- 获取继电器当前缓存状态
function M.get_state()
    return relay_state
end

-- ==================== 异步命令接口（非协程环境专用） ====================
-- 背景：exmodbus 的读写接口内部会 sys.waitUntil 等待应答，必须在协程中调用。
--       HTTP 请求回调、excloud 消息回调均由 C 层直接调用，不在协程中，
--       若在其中直接调用 open/close/read_status，会触发
--       "attempt to yield from outside a coroutine" 导致 Lua VM 退出并重启设备。
-- 方案：非协程侧只投递命令（立即返回，不阻塞、不 yield），
--       由本模块常驻工作协程串行执行，执行结果通过 RELAY_STATUS_UPDATE / RELAY_OP_LOG 广播。
local cmd_queue = {}

-- 投递一条命令到队列并唤醒工作协程（sys.publish 不 yield，可在任意回调中安全调用）
local function post_cmd(cmd)
    cmd_queue[#cmd_queue + 1] = cmd
    sys.publish("RELAY_CMD_POSTED")
    return true
end

-- 异步：打开指定通道（0~3）
function M.post_open(channel)     return post_cmd({ op = "open", ch = channel }) end
-- 异步：关闭指定通道（0~3）
function M.post_close(channel)    return post_cmd({ op = "close", ch = channel }) end
-- 异步：翻转指定通道（0~3）
function M.post_toggle(channel)   return post_cmd({ op = "toggle", ch = channel }) end
-- 异步：全开
function M.post_all_open()        return post_cmd({ op = "all_open" }) end
-- 异步：全关
function M.post_all_close()       return post_cmd({ op = "all_close" }) end
-- 异步：触发一次状态回读
function M.post_read()            return post_cmd({ op = "read" }) end

-- 继电器常驻工作协程：串行执行"异步命令队列" + 周期状态回读
-- 1) 命令执行：所有 Modbus 事务都在本协程内完成，天然可 sys.wait；
--    由 comm_core 的总线互斥锁保证同一时刻只有一笔事务，避免多路总线串扰。
-- 2) 周期回读：每 POLL_INTERVAL 毫秒回读一次 4 路线圈状态，
--    保证 Web 页面 / Modbus 从站寄存器 / AirCloud 云端显示的状态与继电器实际状态一致。
local function relay_work_task()
    local last_poll = os.time()
    while true do
        -- 等待命令通知；最长 500ms 超时，兼作周期回读的节拍与队列兜底
        sys.waitUntil("RELAY_CMD_POSTED", 500)

        -- 1) 串行执行队列中的全部命令
        while #cmd_queue > 0 do
            local cmd = table.remove(cmd_queue, 1)
            if cmd.op == "open" then
                M.open(cmd.ch)
            elseif cmd.op == "close" then
                M.close(cmd.ch)
            elseif cmd.op == "toggle" then
                M.toggle(cmd.ch)
            elseif cmd.op == "all_open" then
                M.all_open()
            elseif cmd.op == "all_close" then
                M.all_close()
            elseif cmd.op == "read" then
                M.read_status()
            end
        end

        -- 2) 周期状态回读
        if rtu_master and (os.time() - last_poll) >= (POLL_INTERVAL / 1000) then
            last_poll = os.time()
            M.read_status()
        end
    end
end

sys.taskInit(relay_work_task)

log.info("relay_ctrl", "继电器控制模块加载完成, 路数:", CH_COUNT, "从站地址:", SLAVE_ID)

return M
