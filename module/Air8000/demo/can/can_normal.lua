--[[
@module  can_normal
@summary CAN总线正常工作模式使用示例
@version 1.0
@date    2025.11.25
@author  魏健强
@usage
本文件为CAN总线正常工作模式使用示例，核心业务逻辑为：
1. 初始化CAN总线
2. 发送和接收CAN总线数据

本文件没有对外接口，直接在main.lua模块中require "can_normal"就可以加载运行；
]] 
local can_id = 0
local stb_pin = 27 -- Air8000开发板上STB引脚为GPIO27
local rx_id = 0x12345677
local tx_id = 0x12345678
local test_cnt = 0
local tx_buf = zbuff.create(8) -- 创建zbuff
local send_queue = {} -- 发送队列
local MAX_SEND_QUEUE_LEN = 50 -- 发送队列最大长度
local send_res = false

-- 数据插入发送队列
local function can_send_data(id, msg_id, id_type, RTR, need_ack, data)
    if #send_queue >= MAX_SEND_QUEUE_LEN then
        log.error("can_send_data", "send queue full")
    end
    table.insert(send_queue, {
        id = id,
        msg_id = msg_id,
        id_type = id_type,
        RTR = RTR,
        need_ack = need_ack,
        data = data
    })
    sys.publish("CAN_SEND_DATA_EVENT")
end

local function can_cb(id, cb_type, param)
    if cb_type == can.CB_MSG then
        log.info("有新的消息")
        local succ, msg_id, id_type, rtr, data = can.rx(id)
        while succ do
            log.info(mcu.x32(msg_id), #data, data:toHex())
            succ, msg_id, id_type, rtr, data = can.rx(id)
        end
    end
    if cb_type == can.CB_TX then
        if param then
            log.info("发送成功")
            send_res = true
        else
            log.info("发送失败")
            send_res = false
        end
        sys.publish("CAN_SEND_DATA_RES")
    end
    if cb_type == can.CB_ERR then
        -- param参数就是4字节错误码
        log.error("CAN错误", "错误码:", string.format("0x%08X", param))

        -- 解析错误码
        local direction = (param >> 16) & 0xFF -- byte2: 方向
        local error_type = (param >> 8) & 0xFF -- byte1: 错误类型  
        local position = param & 0xFF -- byte0: 错误位置

        -- 判断错误方向
        if direction == 0 then
            log.info("错误方向", "发送错误")
        else
            log.info("错误方向", "接收错误")
        end

        -- 判断错误类型
        if error_type == 0 then
            log.info("错误类型", "位错误")
        elseif error_type == 1 then
            log.info("错误类型", "格式错误")
        elseif error_type == 2 then
            log.info("错误类型", "填充错误")
        end

        -- 输出错误位置
        log.info("错误位置", string.format("0x%02X", position))
    end
    if cb_type == can.CB_STATE then
        -- 获取总线状态
        local state = can.state(can_id)
        log.info("can.state", "当前状态", state)
        -- 根据状态处理
        if state == can.STATE_ACTIVE then
            log.info("can.state", "总线正常")
        elseif state == can.STATE_PASSIVE then
            log.warn("can.state", "被动错误状态")
        elseif state == can.STATE_BUSOFF then
            log.error("can.state", "总线离线")
            -- 需要手动恢复
            can.reset(can_id)
        end
    end
end

local function can_tx_test(data)
    while true do
        sys.wait(10000)
        test_cnt = test_cnt + 1
        if test_cnt > 8 then
            test_cnt = 1
        end
        tx_buf:set(0, test_cnt) -- zbuff的类似于memset操作，类似于memset(&buff[start], num, len)
        tx_buf:seek(test_cnt) -- zbuff设置光标位置（可能与当前指针位置有关；执行后指针会被设置到指定位置）
        can_send_data(can_id, 0x123, can.STD, false, true, "Hello") -- 发送标准帧数据
        can_send_data(can_id, 0x123, can.STD, true, true, "") -- 发送遥控帧数据
        can_send_data(can_id, tx_id, can.EXT, false, true, tx_buf)--发送扩展帧数据
    end
end

-- can.debug(true)
gpio.setup(stb_pin,0)   -- 配置STB引脚为输出低电平
can.init(can_id, 128) -- 初始化CAN，参数为CAN ID，接收缓存消息数的最大值
can.on(can_id, can_cb) -- 注册CAN的回调函数
can.timing(can_id, 1000000, 6, 6, 4, 2) -- CAN总线配置时序

-- 接收消息过滤（以下四行代码四选一使用）
can.node(can_id, rx_id, can.EXT) -- 只接收消息id为rx_id的扩展帧数据
-- can.filter(can_id, false, 0x123 << 21, 0x07ffffff) -- 接收消息id为0x12开头的标准帧数据，0x120~0x12f
-- can.filter(can_id, false, 0x12345678 << 3, 0x07ffff) -- 接收消息id为0x1234开头的扩展帧数据，0x12340000~0x1234ffff
-- can.filter(can_id, false, 0, 0xFFFFFFFF) -- 接收所有消息

-- 模式
can.mode(can_id, can.MODE_NORMAL) -- 一旦设置mode就开始正常工作了，此时不能再设置node,timing,filter等

local resend_num = 5 -- 发送失败重发次数

local function send_task()
    local send_item
    local result, buff_full
    -- 遍历数据发送队列send_queue
    while true do
        sys.waitUntil("CAN_SEND_DATA_EVENT",1000)
        while #send_queue > 0 do
            send_res = false
            -- 取数据发送
            send_item = table.remove(send_queue, 1)
            local resend_cnt = 0
            while not send_res do
                can.tx(send_item.id, send_item.msg_id, send_item.id_type, send_item.RTR, send_item.need_ack,
                    send_item.data)
                sys.waitUntil("CAN_SEND_DATA_RES",500)
                sys.wait(10)
                resend_cnt = resend_cnt + 1
                if resend_cnt >= resend_num then
                    log.warn("can send", "重发次数到达上限，停止重发")
                    -- 默认直接丢弃数据
                    -- table.insert(send_queue, send_item) -- 重新插入发送队列
                    break
                end
            end
        end
    end
end
sys.taskInit(send_task)
sys.taskInit(can_tx_test)
