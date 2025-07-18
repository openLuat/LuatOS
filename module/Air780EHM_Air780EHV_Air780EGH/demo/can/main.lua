PROJECT = "candemo"
VERSION = "1.0.0"
sys = require("sys")
log.style(1)
local SELF_TEST_FLAG = false --自测模式标识，写true就进行自收自发模式，写false就进行正常收发模式
local node_a = true   -- A节点写true, B节点写false
local can_id = 0
local rx_id
local tx_id
local stb_pin = 28		-- stb引脚根据实际情况写，不用的话，也可以不写
if node_a then          -- A/B节点区分，互相传输测试
    rx_id = 0x12345678
    tx_id = 0x12345677
else
    rx_id = 0x12345677
    tx_id = 0x12345678
end
local test_cnt = 0
local tx_buf = zbuff.create(8)  --创建zbuff
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
	test_cnt = test_cnt + 1
	if test_cnt > 8 then
		test_cnt = 1
	end
	tx_buf:set(0,test_cnt)  --zbuff的类似于memset操作，类似于memset(&buff[start], num, len)
	tx_buf:seek(test_cnt)   --zbuff设置光标位置（可能与当前指针位置有关；执行后指针会被设置到指定位置）
    can.tx(can_id, tx_id, can.EXT, false, true, tx_buf)
end
-- can.debug(true)
-- gpio.setup(stb_pin,0)   -- 配置STB引脚为输出低电平
gpio.setup(stb_pin,1)	-- 如果开发板上STB信号有逻辑取反，则要配置成输出高电平
can.init(can_id, 128)            -- 初始化CAN，参数为CAN ID，接收缓存消息数的最大值
can.on(can_id, can_cb)            -- 注册CAN的回调函数
can.timing(can_id, 1000000, 5, 4, 3, 2)     --CAN总线配置时序
if SELF_TEST_FLAG then
	can.node(can_id, tx_id, can.EXT)	-- 测试模式下，允许接收的ID和发送ID一致才会有新数据提醒
	can.mode(can_id, can.MODE_TEST)     -- 如果只是自身测试硬件好坏，可以用测试模式来验证，如果发送成功就OK
else
	can.node(can_id, rx_id, can.EXT)
	can.mode(can_id, can.MODE_NORMAL)   -- 一旦设置mode就开始正常工作了，此时不能再设置node,timing,filter等
end

sys.timerLoopStart(can_tx_test, 2000)
sys.run()