PROJECT = "candemo"
VERSION = "1.0.0"
sys = require("sys")
log.style(1)
local node_a = true   -- A节点写true, B节点写false
local can_id = 0
local rx_id
local tx_id
if node_a then          -- A/B节点区分，互相传输测试
    rx_id = 0x12345678
    tx_id = 0x12345677
else
    rx_id = 0x12345677
    tx_id = 0x12345678
end
local test_cnt, test_num
local tx_buf = zbuff.create(8)
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

local function can_tx_test(data)
    if node_a then
        log.info("node a tx")
    else
        log.info("node b tx")
    end
    can.tx(can_id, tx_id, can.EXT, false, true, tx_buf)
end
-- can.debug(true)
can.init(can_id, 128)
can.on(can_id, can_cb)
can.timing(can_id, 1000000, 5, 4, 3, 2)
can.node(can_id, rx_id, can.EXT)
can.mode(can_id, can.MODE_NORMAL)   -- 一旦设置mode就开始正常工作了，此时不能再设置node,timing,filter等
-- can.mode(can_id, can.MODE_TEST)     -- 如果只是自身测试硬件好坏，可以用测试模式来验证，如果发送成功就OK
sys.timerLoopStart(can_tx_test, 1000)
sys.run()