--[[
@module  uart_controller
@summary 寄存柜 485 锁控板通讯模块
@version 3.0
@date    2026.08.13
@author  王城钧
@usage
支持 "OPEN_BOX" 消息触发开锁，支持 "READ_BOX_STATUS" 读取所有锁状态。
硬件：485 走 UART1（9600 8N1）；收发方向脚 RE/DE = config.rs485.pin（Air8601 为 GPIO72），
      由 uart.setup 的第 8 个参数自动切换，脚本不手动控制该脚。
锁控板协议（485，9600 8N1）：
  开锁：      8A 板地址 锁地址 11 BCC     反馈 8A 板 锁 状态(11成功/00失败) BCC
  读所有状态：80 板地址 00 33 BCC         反馈 80 板 [状态字节...] 33 BCC
  读单锁状态：80 板地址 锁地址 33 BCC     反馈 80 板 锁 状态 BCC
  主动上报：  81 板地址 锁地址 状态 BCC
]]

local config = require "config"

local uartid = config.get("serial.uartid")      -- 485 串口（uart1）
local uart485Pin = config.get("rs485.pin")      -- 485 方向脚 RE/DE（Air8601：GPIO72）
local uart_initialized = false

-- 板地址（锁控板拨码开关，默认 1 号板）
local BOARD_ADDR = 0x01

-- 命令头
local HEAD_OPEN = 0x8A           -- 开锁命令/反馈头
local HEAD_READ = 0x80           -- 读状态命令/反馈头
local HEAD_PUSH = 0x81           -- 主动上报头

-- 功能码
local FUNC_OPEN = 0x11           -- 开锁功能码
local FUNC_READ_STATUS = 0x33    -- 读锁状态功能码

-- 开锁反馈状态（开门反馈的锁：0x11=打开成功，0x00=失败）
local OPEN_OK = 0x11

-- 命令类型定义（对外接口保留）
local COMMAND_TYPES = {
    OPEN_BOX = FUNC_OPEN,        -- 开锁
    READ_STATUS = FUNC_READ_STATUS -- 读锁状态
}

-- 日志开关：true=打印收发帧与命令明细（485 调试用）；
--           false=只打印报错、开锁结果与低频轮询心跳（轮询是每 5 秒一次，逐帧打印会刷屏）
local UART_VERBOSE = false
local status_read_count = 0   -- 读锁状态轮数（供低频心跳使用）

-- 计算 BCC 校验（异或）
local function calculate_bcc(data)
    local bcc = 0
    for i, byte in ipairs(data) do
        bcc = bit.bxor(bcc, byte)
    end
    return bcc
end

-- 发送字节数组
local function send_bytes(data)
    if not uart_initialized then
        log.error("uart_controller", "串口未初始化")
        return false
    end
    local s = ""
    for i, byte in ipairs(data) do
        s = s .. string.char(byte)
    end
    if UART_VERBOSE then
        log.info("uart_controller", "发送命令", s:toHex())
    end
    local result = uart.write(uartid, s)
    if result then
        if UART_VERBOSE then
            log.info("uart_controller", "命令发送成功")
        end
        return true
    else
        log.error("uart_controller", "命令发送失败")
        return false
    end
end

-- 开锁命令：8A 板地址 锁地址 11 BCC
local function send_open_box_command(box_num)
    local data = {HEAD_OPEN, BOARD_ADDR, box_num, FUNC_OPEN}
    table.insert(data, calculate_bcc(data))
    return send_bytes(data)
end

-- 读取所有锁状态：80 板地址 00 33 BCC
local function send_read_status_command()
    local data = {HEAD_READ, BOARD_ADDR, 0x00, FUNC_READ_STATUS}
    table.insert(data, calculate_bcc(data))
    return send_bytes(data)
end

-- 解析响应
local function parse_response(response)
    if #response < 5 then
        log.error("uart_controller", "响应长度不足", #response)
        return nil
    end

    local bytes = {}
    for i = 1, #response do
        bytes[i] = string.byte(response, i)
    end

    -- BCC 校验
    local bcc = 0
    for i = 1, #bytes - 1 do
        bcc = bit.bxor(bcc, bytes[i])
    end
    if bcc ~= bytes[#bytes] then
        log.error("uart_controller", "响应校验失败", response:toHex())
        return nil
    end

    local head = bytes[1]
    if head == HEAD_OPEN then
        -- 开锁反馈：8A 板 锁 状态 BCC
        return { type = "OPEN", box_num = bytes[3], status = bytes[4] }
    elseif head == HEAD_READ then
        -- 读状态反馈
        if #bytes == 5 then
            -- 单锁：80 板 锁 状态 BCC
            return { type = "STATUS_SINGLE", box_num = bytes[3], status = bytes[4] }
        else
            -- 所有锁：80 板 [状态字节...] 33 BCC
            local statuses = {}
            for i = 3, #bytes - 2 do
                statuses[#statuses + 1] = bytes[i]
            end
            return { type = "STATUS_ALL", statuses = statuses }
        end
    elseif head == HEAD_PUSH then
        -- 主动上报：81 板 锁 状态 BCC
        return { type = "PUSH", box_num = bytes[3], status = bytes[4] }
    else
        log.error("uart_controller", "未知响应头", string.format("0x%02X", head))
        return nil
    end
end

-- 处理一个已通过 BCC 校验的完整帧
local function handle_response(response)
    if response.type == "OPEN" then
        -- 仅当锁板明确回失败状态时才覆盖发布
        if response.status ~= OPEN_OK then
            sys.publish("BOX_OPEN_RESULT", {
                box_num = response.box_num,
                success = false,
                error = "开柜失败"
            })
        end
    elseif response.type == "STATUS_ALL" then
        -- 状态字节顺序：第1字节=锁17-24, 第2=锁9-16, 第3=锁1-8
        -- 每个字节 bit0 对应最小锁号，bit=1 表示打开
        local boxes = {}
        local n = #response.statuses
        for idx = 1, n do
            local base = (n - idx) * 8 + 1
            for bit = 0, 7 do
                local box_num = base + bit
                local is_open = bit.band(response.statuses[idx], bit.lshift(1, bit)) ~= 0
                table.insert(boxes, {box = box_num, open = is_open})
            end
        end
        sys.publish("BOX_STATUS_UPDATE", boxes)
    elseif response.type == "STATUS_SINGLE" then
        sys.publish("BOX_STATUS_UPDATE", {
            {box = response.box_num, open = (response.status == OPEN_OK)}
        })
    elseif response.type == "PUSH" then
        -- 主动上报：81 板 锁 状态 BCC（状态=0x11 视为门开，其余视为门关）
        log.info("uart_controller", "主动上报", "锁", response.box_num, "状态", response.status)
        -- 转成统一门状态消息：供 event_reporter 判定"关箱"（open 由 true→false），
        -- 界面（ecboxstatus）也在订阅该消息，可同步刷新
        sys.publish("BOX_STATUS_UPDATE", {
            { box = response.box_num, open = (response.status == OPEN_OK) }
        })
    end
end

-- 串口接收缓冲（帧同步用）：累积分片数据，按帧格式提取完整帧
--   协议没有长度字段，485 半双工下数据可能分片到达
local rx_buf = ""

-- 从接收缓冲中提取一个完整帧（帧同步）
-- 帧格式（同文件头注释）：
--   8A / 81 开头：定长 5 字节
--   80 开头：读单锁 5 字节；读全部状态为变长（80 板 [状态字节...] 33 BCC），按 0x33 定位帧尾
-- @return string 完整帧；nil 表示帧不完整（等后续数据）
local function extract_frame()
    while #rx_buf >= 5 do
        local head = rx_buf:byte(1)
        local need = nil

        if head == HEAD_OPEN or head == HEAD_PUSH then
            need = 5
        elseif head == HEAD_READ then
            if rx_buf:byte(3) == 0x00 then
                -- 读全部状态：以 FUNC_READ_STATUS(0x33) + BCC 结尾
                local pos = rx_buf:find(string.char(FUNC_READ_STATUS), 4, true)
                if not pos then
                    return nil      -- 状态字节还没收全
                end
                need = pos + 1      -- 含 0x33 后紧跟的 BCC
            else
                need = 5            -- 读单锁状态
            end
        else
            -- 非帧头字节：丢弃 1 字节后重新同步
            log.warn("uart_controller", "丢弃非帧头字节", string.format("0x%02X", head))
            rx_buf = rx_buf:sub(2)
        end

        if need then
            if #rx_buf < need then
                return nil          -- 帧不完整，等下一批数据
            end
            local frame = rx_buf:sub(1, need)
            rx_buf = rx_buf:sub(need + 1)
            return frame
        end
    end
    return nil
end

-- 串口接收回调（带帧同步）
local function uart_cb(id, len)
    -- 先把串口缓冲读空，拼成本次收到的数据
    local s = ""
    local chunk
    repeat
        chunk = uart.read(id, 256)
        if chunk and #chunk > 0 then
            s = s .. chunk
        end
    until not chunk or chunk == ""

    if #s == 0 then
        return
    end
    if UART_VERBOSE then
        log.info("uart_controller", "receive", id, #s, s:toHex())
    end

    rx_buf = rx_buf .. s
    -- 缓冲上限保护
    if #rx_buf > 512 then
        log.warn("uart_controller", "接收缓冲溢出，丢弃前 " .. (#rx_buf - 256) .. " 字节")
        rx_buf = rx_buf:sub(-256)
    end

    -- 循环提取完整帧：一次收到多帧（或上次残留的半帧）都能正确拼出来
    while true do
        local frame = extract_frame()
        if not frame then
            break
        end
        -- ★ 逐帧包 pcall：uart 回调里抛未捕获异常同样会让 Lua VM exit → 整机重启，
        --   而 485 是脏数据最容易出现的链路，单帧解析异常不该拖垮整机。
        local pok, perr = pcall(function()
            local response = parse_response(frame)
            if response then
                handle_response(response)
            else
                log.warn("uart_controller", "帧校验失败，丢弃", frame:toHex())
            end
        end)
        if not pok then
            log.error("uart_controller", "帧处理异常:", tostring(perr))
        end
    end
end

-- 串口发送完成回调（每轮命令都会触发）
local function uart_send_cb(id)
    if UART_VERBOSE then
        log.info("uart_controller", id, "数据发送完成回调")
    end
end

-- 初始化串口
local function init_uart()
    uart.setup(uartid, 9600, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 20000)
    uart.on(uartid, "receive", uart_cb)
    uart.on(uartid, "sent", uart_send_cb)
    uart_initialized = true
    log.info("uart_controller", "串口" .. uartid .. "初始化完成（9600 8N1，485 方向脚 GPIO"
             .. tostring(uart485Pin) .. "）")
end

-- 开锁消息处理
local function on_open_box(box_num)
    log.info("uart_controller", "收到开锁请求", box_num)

    local num = tonumber(box_num)
    if not num or num < 1 or num > 30 then
        log.error("uart_controller", "无效的箱子编号:", box_num)
        sys.publish("BOX_OPEN_RESULT", {box_num = box_num, success = false, error = "无效的箱子编号"})
        return
    end

    local success = send_open_box_command(num)
    if success then
        -- 锁板收到开锁命令即动作，不回 0x8A 反馈帧，命令发送成功视为开锁成功
        sys.publish("BOX_OPEN_RESULT", {
            box_num = num,
            success = true
        })
    else
        sys.publish("BOX_OPEN_RESULT", {
            box_num = box_num,
            success = false,
            error = "发送失败"
        })
    end
end

-- 读取所有锁状态消息处理
local function on_read_status()
    -- 心跳：每 12 轮（约 60 秒）打一行
    status_read_count = status_read_count + 1
    if UART_VERBOSE or (status_read_count % 12 == 0) then
        log.info("uart_controller", "读锁状态轮询心跳", status_read_count)
    end
    local success = send_read_status_command()
    if not success then
        sys.publish("BOX_STATUS_UPDATE", {error = "发送失败"})
    end
end

-- 模块初始化
local function init()
    init_uart()
    sys.subscribe("OPEN_BOX", on_open_box)
    sys.subscribe("READ_BOX_STATUS", on_read_status)
    log.info("uart_controller", "模块初始化完成")
end

init()

return {
    init = init,
    send_open_box_command = send_open_box_command,
    send_read_status_command = send_read_status_command,
    COMMAND_TYPES = COMMAND_TYPES,
}
