--[[
@module  uart_controller
@summary 寄存柜 485 锁控板通讯模块
@version 3.0
@date    2026.08.13
@author  王城钧
@usage
支持 "OPEN_BOX" 消息触发开锁，支持 "READ_BOX_STATUS" 读取所有锁状态。
锁控板协议（485，9600 8N1）：
  开锁：      8A 板地址 锁地址 11 BCC     反馈 8A 板 锁 状态(11成功/00失败) BCC
  读所有状态：80 板地址 00 33 BCC         反馈 80 板 [状态字节...] 33 BCC
  读单锁状态：80 板地址 锁地址 33 BCC     反馈 80 板 锁 状态 BCC
  主动上报：  81 板地址 锁地址 状态 BCC
]]

local config = require "config"

local uartid = config.get("serial.uartid")      -- 485 串口（uart1）
local uart485Pin = config.get("rs485.pin")      -- 485 使能引脚 GPIO8
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
    log.info("uart_controller", "发送命令", s:toHex())
    local result = uart.write(uartid, s)
    if result then
        log.info("uart_controller", "命令发送成功")
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

-- 串口接收回调
local function uart_cb(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then
            log.info("uart_controller", "receive", id, #s, s:toHex())
            local response = parse_response(s)
            if response then
                if response.type == "OPEN" then
                    -- 命令发送成功已即时发布成功，仅当锁板明确回失败状态才覆盖发布
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
                    log.info("uart_controller", "主动上报", "锁", response.box_num, "状态", response.status)
                end
            end
        end
    until s == ""
end

-- 串口发送完成回调
local function uart_send_cb(id)
    log.info("uart_controller", id, "数据发送完成回调")
end

-- 初始化串口
local function init_uart()
    uart.setup(uartid, 9600, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 20000)
    uart.on(uartid, "receive", uart_cb)
    uart.on(uartid, "sent", uart_send_cb)
    uart_initialized = true
    log.info("uart_controller", "串口" .. uartid .. "初始化完成")
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
    log.info("uart_controller", "收到读取锁状态请求")
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
