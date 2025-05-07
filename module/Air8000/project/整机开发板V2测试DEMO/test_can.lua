
--[[
1.本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2.演示can 的用法。
3.使用了如下管脚:
[37, "CAN_RX", " PIN37脚, 用于CAN 接收"],
[36, "CAN_TX", " PIN36脚, 用于CAN 发射"],
[35, "STB", " PIN35脚, 用于CAN 控制"],
4.本文处理逻辑，需要使用两个整机开发板，CAN_H 和 CAN_H 对接, CAN_L 和 CAN_L 对接，
整机开发板1，使用node_a = 1 ，
整机开发板2，使用node_a = 2
开机后，每个整机开发板，都会间隔2秒给对方发送一个自己的ID数据
]]

local task_name = "can_task"
local node_a = 1     --  不同的整机开发板，使用不同的ID
local can_id = 0
local tx_buf = zbuff.create(8)
local rx_id
local tx_id
if node_a == 1 then          
    rx_id = 0x00000001
    tx_id = 0x00000002
    tx_buf[0]=1
elseif node_a == 2 then
    rx_id = 0x00000002
    tx_id = 0x00000001
    tx_buf[0]=2
end
local test_cnt, test_num

local function can_cb(id, cb_type, param)
    if cb_type == can.CB_MSG then
        log.info("有新的消息")
        local succ, id, id_type, rtr, data = can.rx(id)
        while succ do
            log.info(mcu.x32(id), #data, data:toHex())
            succ, id, id_type, rtr, data = can.rx(id)
        end
    end
    if cb_type == can.CB_TX then
        if param then
            log.info("发送成功")
        else
            log.info("发送失败")
        end
    end
    if cb_type == can.CB_ERR then
        log.info("CAN错误码", mcu.x32(param))
    end
    if cb_type == can.CB_STATE then
        log.info("CAN新状态", param)
    end
end


local function can_setup()
    can.init(can_id, 128)     --- 初始化CAN
end
-- can.debug(true)
local function can_task()   
    can_setup() -- 初始化can
    can.on(can_id, can_cb)    --- 注册回调函数
    can.timing(can_id, 1000000, 5, 4, 3, 2)
    can.node(can_id, rx_id, can.EXT)
    can.mode(can_id, can.MODE_NORMAL)   -- 一旦设置mode就开始正常工作了，此时不能再设置node,timing,filter等
    if node_a == 1  then
        log.info("整机开发板 1  tx")
    elseif node_a == 2  then
        log.info("整机开发板 2  tx")
    end
    while true do
        sys.wait(2000)
        can.tx(can_id, tx_id, can.EXT, false, true, tx_buf)
    end

end


sysplus.taskInitEx(can_task,task_name)   
