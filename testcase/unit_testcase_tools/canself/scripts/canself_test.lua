local canself_test = {}

local device_name = rtos.bsp()

local node_a = true -- A节点写true, B节点写false
local can_id = 0
local rx_id
local tx_id

if node_a then -- A/B节点区分，互相传输测试
    rx_id = 0x12345677
    tx_id = 0x12345677
else
    rx_id = 0x12345677
    tx_id = 0x12345678
end
local test_cnt = 0
local tx_buf = zbuff.create(8)
local total_tests = 5 -- 总测试次数
local test_timer = nil -- 定时器句柄
local current_test_count = 0 -- 当前测试次数

local function can_configuration()
    if device_name == "Air780EPM" then
        gpio.setup(1, 1) -- 打开5v电源
        gpio.setup(32, 1) -- 打开12v电源
        -- 配置电源电压
        -- 780EPM v1.4开发板需要去掉can对应三极管后的两颗电容(位号为c4,c5)
        -- 打开can使能,v1.4开发板才需要配置
        -- gpio.setup(28, 0)
        pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
        stb_pin = 28 -- can使能引脚，根据实际开发板修改
    elseif device_name == "Air8000" then
        stb_pin = 27 -- can使能引脚，根据实际开发板修改
    elseif device_name == "Air8101" then
        stb_pin = 46
    else
        log.info("未知的设备名称")
    end
end

local function can_cb(id, cb_type, param)
    if cb_type == can.CB_MSG then
        log.info("有新的消息")
        local succ, id, id_type, rtr, data = can.rx(id)
        while succ do
            log.info("CAN接收", string.format("ID:%08X 长度:%d 数据:%s", id, #data, data:toHex()))
            local data_message = data:toHex()
            assert(data_message == can_tx_message,
                string.format("CAN接收消息第" .. current_test_count .. "次测试失败: 预期 %s, 实际 %s",
                    can_tx_message, data_message))
            log.info("canself_test", "CAN接收消息测试第" .. current_test_count .. "通过")

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
    current_test_count = current_test_count + 1
    if current_test_count > total_tests then
        log.info("CAN测试", "已达到" .. total_tests .. "次测试，停止定时器")
        if test_timer then
            sys.timerStop(test_timer)
            test_timer = nil
        end
        return
    end
    log.info("CAN测试", "第" .. current_test_count .. "次测试")

    if node_a then
        log.info("node a tx---------------")
    else
        log.info("node b tx")
    end
    test_cnt = test_cnt + 1
    if test_cnt > 8 then
        test_cnt = 1
    end

    tx_buf:clear()
    for i = 0, test_cnt - 1 do
        tx_buf:set(i, test_cnt)
    end
    tx_buf:seek(0)
    local buff_message = tx_buf:read(test_cnt)
    local hex_string = buff_message:toHex()
    can_tx_message = hex_string:match("^(%S+)")

    local tx_message = can.tx(can_id, tx_id, can.EXT, false, true, tx_buf)

    assert(tx_message == 0, string.format(
        "CAN发送消息第" .. current_test_count .. "次测试失败: 预期 %s, 实际 %s", 0, tx_message))
    log.info("canself_test", "CAN发送消息测试第" .. current_test_count .. "通过")
end

function canself_test.test_init_demo()
    can_configuration()
    local caninit_result = can.init(can_id, 128)
    local expectation = true
    assert(caninit_result == expectation,
        string.format("CAN初始化测试失败: 预期 %s, 实际 %s", expectation, caninit_result))
    log.info("canself_test", "CAN初始化测试通过")

    -- can.debug(true)

    can.on(can_id, can_cb)

    local can_timing_result = can.timing(can_id, 1000000, 6, 6, 4, 2)
    assert(can_timing_result == expectation,
        string.format("CAN时序测试失败: 预期 %s, 实际 %s", expectation, can_timing_result))
    log.info("canself_test", "CAN 总线配置时序测试通过")

    local can_node_result = can.node(can_id, rx_id, can.EXT)
    assert(can_node_result == expectation,
        string.format("CAN 总线设置节点ID测试失败: 预期 %s, 实际 %s", expectation, can_node_result))
    log.info("canself_test", "CAN 总线配置节点ID测试通过")

    local can_mode_result = can.mode(can_id, can.MODE_TEST)
    assert(can_mode_result == expectation, string.format(
        "CAN 总线设置自测工作模式测试失败: 预期 %s, 实际 %s", expectation, can_mode_result))
    log.info("canself_test", "CAN 总线配置自测工作模式测试通过")

    -- 如果开发板上STB信号有逻辑取反，则要配置成输出高电平
    gpio.setup(stb_pin, 0)
    -- gpio.setup(stb_pin,1)

    -- 启动定时器
    log.info("CAN测试", "开始定时测试,将在" .. total_tests .. "次后自动停止")
    test_timer = sys.timerLoopStart(can_tx_test, 1000)

end

return canself_test
