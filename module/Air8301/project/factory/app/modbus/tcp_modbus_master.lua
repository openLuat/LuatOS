--[[
@module  tcp_modbus_master
@summary 建大仁科 TCP Modbus 温湿度读取模块（8301出厂固件 · 项目内自实现）
@version 4.1
@date    2026.10.13
@author  江访
@usage
本模块将设备配置为 Modbus TCP 主站，读取建大仁科 TCP 温湿度变送器
（192.168.1.100:500，TCP Server 模式）的数据，固定绑定网口1（socket.LWIP_ETH）。

▌为什么不再使用 exmodbus 的 TCP 主站
现场实测：传感器「最大连接数」有限（配置里为 5），而扩展库 exmodbus_tcp 的连接
生命周期由其内部主循环掌控（长连接 + 断开后固定 5 秒重建），一旦异常断开导致
传感器侧连接槽位被残留连接占住，后续重连会被对端持续 RST（日志表现为
「socket N not closing, but error -14」→「连接服务器失败」），且库内日志无法关闭。

▌连接策略（v4.1）
经多轮实测，传感器对「短时间内重复建连」非常敏感，且**长连接表现优于短连接**
（早期长连接可连续读 6 次；改短连接后第 2 次建连即被 RST）。故本版：

  1、保持长连接：建连成功后复用，周期（默认 5 秒）读取，不再每次重连；
  2、**失败后不再立即重连重试**（v4.0 曾 500ms 内重试，实测反而加快耗尽对端
     连接槽位），改为断开后"耐心等待"：15s→30s→60s→120s 封顶 + ±20% 抖动；
  3、读取成功后立即回到 5 秒节拍；
  4、断开时严格 close + release，不留半开连接；
  5、**不使用激进的 TCP keepalive**（keep_idle=5 秒过短，可能被对端视为异常），
     采用宽松值（空闲 60 秒才起探测）。

▌通信参数
  网卡     网口1（socket.LWIP_ETH）
  目标     192.168.1.100:500
  从站号   1
  功能码   0x03（读保持寄存器）
  起始地址 0x0000
  寄存器数 2（0x0000=湿度，0x0001=温度，均为 INT16、大端、放大 10 倍）

▌Modbus TCP 请求/响应帧结构（MBAP 7 字节 + PDU）
  请求： [事务ID 2][协议ID 0x0000 2][长度 2][单元ID 1] + [0x03][起始地址 2][寄存器数 2]  = 12 字节
  响应： [事务ID 2][协议ID 0x0000 2][长度 2][单元ID 1] + [0x03][字节数 1][数据 4]        = 13 字节

本文件没有对外接口，直接在 main.lua 中 require "tcp_modbus_master" 即可加载运行；

对外接口：
1、sys.publish("TEMP_HUMIDITY_UPDATE", temperature, humidity)
    temperature: 温度值（浮点数℃，如 25.3）
    humidity:    湿度值（浮点数%RH，如 60.5）
]]

local libnet = require "libnet"

-- 本任务名：socket.create / libnet 系列接口都要用到
local TASK_NAME = "tcp_modbus_master"

-- ==================== 传感器通信参数 ====================
local SENSOR_IP   = "192.168.1.100"      -- 温湿度变送器 IP
local SENSOR_PORT = 500                  -- Modbus TCP 端口
local ADAPTER     = socket.LWIP_ETH      -- 网卡：网口1（与内置网页同网段）
local SLAVE_ID    = 1                    -- 从站地址
local START_ADDR  = 0x0000               -- 起始地址：0x0000 湿度、0x0001 温度
local REG_COUNT   = 2                    -- 读取 2 个保持寄存器

-- ==================== TCP keepalive（宽松值，避免打扰对端）====================
local KEEP_IDLE     = 60                 -- 空闲 60 秒后才开始探测
local KEEP_INTERVAL = 10                 -- 探测间隔 10 秒
local KEEP_CNT      = 3                  -- 3 次无应答判定断开

-- ==================== 超时与间隔参数 ====================
local CONNECT_TIMEOUT  = 3000            -- 建立连接超时（毫秒）
local TX_TIMEOUT       = 2000            -- 发送超时（毫秒）
local RESP_TIMEOUT     = 1000            -- 单轮等待响应超时（毫秒）
local CLOSE_TIMEOUT    = 2000            -- 关闭连接超时（毫秒）
local READ_INTERVAL_OK = 5000            -- 正常读取间隔（毫秒，长连接复用，仅是读取节拍）
local RECONNECT_MIN    = 15000           -- 断线后首次重连等待（毫秒）
local READ_INTERVAL_MAX= 120000          -- 重连退避上限（毫秒）
local BACKOFF_STEP     = 4               -- 指数退避最多翻倍次数（2^4 = 16 倍）
local JITTER_PERCENT   = 20              -- 退避抖动幅度（±20%）

-- Modbus TCP 响应帧期望长度：MBAP 7 + 功能码 1 + 字节数 1 + 数据 4 = 13 字节
local EXPECT_FRAME_LEN = 13

-- ==================== 模块内状态 ====================
local recv_buff = nil                    -- socket 接收缓冲（zbuff，懒加载并复用）
local txn_id = 0                         -- Modbus TCP 事务 ID（自增，16 位回绕）
local cur_sock = nil                     -- 当前长连接 socket（nil 表示未连接）

-- 传感器数据缓存
local sensor_data = {
    temperature = 0,
    humidity = 0
}

--[[
构建读保持寄存器（0x03）请求帧

@local
@function build_read_frame
@return string 完整的 Modbus TCP 请求帧（12 字节）
]]
local function build_read_frame()
    txn_id = (txn_id + 1) & 0xFFFF
    -- PDU：功能码 + 起始地址 + 寄存器数量
    local pdu = string.char(
        0x03,
        (START_ADDR >> 8) & 0xFF, START_ADDR & 0xFF,
        (REG_COUNT >> 8) & 0xFF, REG_COUNT & 0xFF
    )
    -- MBAP：事务ID + 协议ID + 长度（单元ID + PDU）+ 单元ID
    local mbap = string.char(
        (txn_id >> 8) & 0xFF, txn_id & 0xFF,
        0x00, 0x00,
        0x00, #pdu + 1,
        SLAVE_ID
    )
    return mbap .. pdu
end

--[[
解析读保持寄存器响应帧，转换为温度/湿度

校验项：协议 ID=0、单元 ID 匹配、功能码=0x03（或异常码 0x83）、字节数=4、长度足够。

@local
@function parse_response
@param resp string 原始响应帧
@return number|nil temperature 温度（℃，失败为 nil）
@return number|nil humidity    湿度（%RH，失败为 nil）
]]
local function parse_response(resp)
    if type(resp) ~= "string" or #resp < EXPECT_FRAME_LEN then
        return nil, nil
    end

    -- 协议 ID 必须为 0x0000
    if string.byte(resp, 3) ~= 0x00 or string.byte(resp, 4) ~= 0x00 then
        return nil, nil
    end

    -- 单元 ID（从站地址）必须匹配
    if string.byte(resp, 7) ~= SLAVE_ID then
        return nil, nil
    end

    local func = string.byte(resp, 8)

    -- 异常响应：功能码最高位置 1（0x83），第 9 字节为异常码
    if func == 0x83 then
        log.warn("tcp_modbus_master", "传感器返回异常响应，异常码", string.byte(resp, 9))
        return nil, nil
    end

    if func ~= 0x03 then
        return nil, nil
    end

    -- 数据区字节数必须为 4（2 个寄存器 × 2 字节）
    if string.byte(resp, 9) ~= 4 then
        return nil, nil
    end

    -- 大端解析：0x0000 湿度、0x0001 温度
    local humi_raw = string.byte(resp, 10) * 256 + string.byte(resp, 11)
    local temp_raw = string.byte(resp, 12) * 256 + string.byte(resp, 13)
    -- 温度支持负值（INT16 补码）
    if temp_raw > 0x7FFF then
        temp_raw = temp_raw - 0x10000
    end

    return temp_raw / 10.0, humi_raw / 10.0
end

--[[
关闭并释放 socket（保证连接生命周期干净，不留半开连接）

libnet.close 内部即执行 socket.close（TCP 先四次挥手、超时后强制断开），
随后 socket.release 释放 socket 资源。两者配合是 LuatOS 标准做法。

@local
@function close_socket
@param sock userdata socket 对象
]]
local function close_socket(sock)
    if not sock then return end
    libnet.close(TASK_NAME, CLOSE_TIMEOUT, sock)
    socket.release(sock)
end

--[[
断开当前长连接（并把引用置空，下次读取会重新建连）

@local
@function drop_connection
]]
local function drop_connection()
    if cur_sock then
        close_socket(cur_sock)
        cur_sock = nil
    end
end

--[[
确保当前存在可用长连接；无连接时建立

@local
@function ensure_connected
@return boolean 是否已连接
@return string|nil 失败原因（成功时为 nil）
]]
local function ensure_connected()
    if cur_sock then
        return true
    end

    local sock = socket.create(ADAPTER, TASK_NAME)
    if not sock then
        return false, "创建 socket 失败"
    end

    -- 配置 TCP keepalive（宽松值，避免打扰对端；不设置 is_udp/is_tls）
    if not socket.config(sock, nil, nil, nil, KEEP_IDLE, KEEP_INTERVAL, KEEP_CNT) then
        close_socket(sock)
        return false, "socket 配置失败"
    end

    if not libnet.connect(TASK_NAME, CONNECT_TIMEOUT, sock, SENSOR_IP, SENSOR_PORT) then
        close_socket(sock)
        return false, "连接传感器失败"
    end

    cur_sock = sock
    return true
end

--[[
接收一帧响应数据

先读净内核缓冲区，数据不足时再用 libnet.wait 等待新数据，最多等待 3 轮。
注意：socket.rx 返回 false 表示连接异常（不可再读），返回 true 时通过
      zbuff 已用长度判断本次是否读到数据。

@local
@function recv_frame
@param sock userdata socket 对象
@return string|nil 响应数据（达到期望长度返回，否则返回 nil）
]]
local function recv_frame(sock)
    if not recv_buff then
        recv_buff = zbuff.create(512)
    end
    recv_buff:del()

    local data = ""
    for _ = 1, 3 do
        -- 读净当前缓冲区内的所有数据
        while true do
            local ok = socket.rx(sock, recv_buff)
            if not ok then
                -- 连接异常（对端关闭/复位）
                return nil
            end
            if recv_buff:used() > 0 then
                data = data .. recv_buff:query()
                recv_buff:del()
            else
                break
            end
        end

        -- 已收齐一帧，直接返回
        if #data >= EXPECT_FRAME_LEN then
            return data
        end

        -- 等待更多数据；返回 false 表示超时或连接断开
        if not libnet.wait(TASK_NAME, RESP_TIMEOUT, sock) then
            break
        end
    end

    if #data >= EXPECT_FRAME_LEN then
        return data
    end
    return nil
end

--[[
单次尝试：确保连接 → 发送请求 → 接收响应 → 解析

任一步失败都会断开连接（下次调用会重新建连），不留半开连接。

@local
@function attempt
@return boolean 是否成功
@return string|nil 失败原因（成功时为 nil）
]]
local function attempt()
    -- 1、确保连接（首次或断线后才会真正建连）
    local ok, reason = ensure_connected()
    if not ok then
        return false, reason
    end

    -- 2、发送读请求
    if not libnet.tx(TASK_NAME, TX_TIMEOUT, cur_sock, build_read_frame()) then
        drop_connection()
        return false, "发送请求失败"
    end

    -- 3、接收响应
    local resp = recv_frame(cur_sock)
    if not resp then
        drop_connection()
        return false, "等待响应超时"
    end

    -- 4、解析数据
    local temp, humi = parse_response(resp)
    if not temp then
        drop_connection()
        return false, "响应数据无效"
    end

    sensor_data.temperature = temp
    sensor_data.humidity = humi
    return true
end

--[[
读取一轮（单次尝试，失败即交由主任务做「耐心退避」）

说明：早期版本曾在失败后 500ms 内立即重连重试，实测反而有害——
传感器是「最大连接数」有限的 TCP Server，短时间内的重复建连会更快耗尽它的
连接槽位（表现为持续 RST / error -14）。故本版取消激进重试，
改为失败后先等待一段较长时间（默认 15 秒起、指数增长）再重连。

@local
@function read_once
@return boolean 是否成功
@return string|nil 失败原因（成功时为 nil）
]]
local function read_once()
    local ok, reason = attempt()
    if ok then
        return true, nil
    end
    return false, reason
end

--[[
主任务：周期性读取温湿度（长连接复用）

连接正常 → 每 5 秒读一次（复用同一连接）；
读取失败 → 立即断开，并按指数退避重连
           （15s→30s→60s→120s 封顶，叠加 ±20% 抖动）。

⚠️ 为什么失败后要等这么久才重连：
传感器是「最大连接数」有限的 TCP Server（现场配置为 5）。实测发现，
高频重连（每 5 秒）会让它的连接槽位迅速被占满，之后所有新连接一律被 RST
（error -14）。因此失败后必须"耐心等待"，而不是立刻重连。

读取成功 → 立即回到 5 秒节拍。
日志做降噪：仅首次失败与每 5 次失败各提示一次。

@local
@function task
]]
local function task()
    sys.wait(6000)                        -- 等待网口1 网络就绪
    -- 初始化随机数种子（退避抖动使用），并先抽两次打散序列
    math.randomseed(os.time())
    math.random(); math.random()

    local fail_count = 0

    while true do
        local ok, reason = read_once()
        local wait_ms

        if ok then
            if fail_count > 0 then
                log.info("tcp_modbus_master", "温湿度通讯恢复正常，此前连续失败", fail_count, "次")
            end
            fail_count = 0

            log.info("tcp_modbus_master", "读取成功，温度为",
                string.format("%.1f", sensor_data.temperature), "℃，湿度为",
                string.format("%.1f", sensor_data.humidity), "%RH")

            sys.publish("TEMP_HUMIDITY_UPDATE", sensor_data.temperature, sensor_data.humidity)
            wait_ms = READ_INTERVAL_OK
        else
            fail_count = fail_count + 1
            -- 失败即断开，确保下次是"全新"的连接，不留半开连接
            drop_connection()

            -- 失败降噪：仅首次失败与每 5 次失败各提示一次，避免刷屏
            if fail_count == 1 then
                log.warn("tcp_modbus_master", "温湿度通讯失败（" .. tostring(reason) .. "），进入耐心重连")
            elseif fail_count % 5 == 0 then
                log.warn("tcp_modbus_master", "温湿度通讯持续失败，已连续失败", fail_count,
                    "次（" .. tostring(reason) .. "）")
            end

            -- 指数退避 + 抖动：给传感器的连接槽位留出足够的回收时间
            local base = RECONNECT_MIN * (2 ^ math.min(fail_count - 1, BACKOFF_STEP))
            if base > READ_INTERVAL_MAX then base = READ_INTERVAL_MAX end
            local jitter = math.random(-JITTER_PERCENT, JITTER_PERCENT)
            wait_ms = math.floor(base * (100 + jitter) / 100)
        end

        sys.wait(wait_ms)
    end
end

sys.taskInitEx(task, TASK_NAME)
