--[[
@module  can_sleep
@summary CAN总线休眠模式使用示例
@version 1.0
@date    2025.11.25
@author  魏健强
@usage
本文件为CAN总线休眠模式使用示例，核心业务逻辑为：
1. 初始化CAN总线
2. 空闲时间进入休眠模式，定时唤醒发送数据

本文件没有对外接口，直接在main.lua模块中require "can_self_test"就可以加载运行；
]]
local can_id = 0
local stb_pin = 28 -- 780EPM V1.3开发板上STB引脚为GPIO28
local rx_id = 0x12345678
local tx_id = 0x12345677

local test_cnt = 0
local tx_buf = zbuff.create(8)  --创建zbuff

gpio.setup(23, 1) -- 要手动打开，开发板can电路需要使用gpio23引脚作为参考电平。

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
        else
            log.info("发送失败")
        end
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

local function can_tx_test()
    log.info("can tx")
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
gpio.setup(stb_pin, 1) -- 780EPM V1.3开发板STB信号有逻辑取反，要配置成输出高电 
can.init(can_id, 128)            -- 初始化CAN，参数为CAN ID，接收缓存消息数的最大值
can.on(can_id, can_cb)            -- 注册CAN的回调函数
can.timing(can_id, 1000000, 6, 6, 4, 2)     --CAN总线配置时序
can.node(can_id, rx_id, can.EXT)	-- 设置过滤，只接收消息id为rx_id的扩展帧数据
can.mode(can_id, can.MODE_SLEEP)     -- 设置sleep模式

local function CAN_MODE_SLEEP()
    while true do
        sys.wait(1000)
        log.info("can_state", can.state(can_id))
        if can.state(can_id) == can.STATE_ACTIVE then
            can.mode(can_id, can.MODE_SLEEP)
        end
    end
end
sys.taskInit(CAN_MODE_SLEEP)
sys.timerLoopStart(can_tx_test, 10000)