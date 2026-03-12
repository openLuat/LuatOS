-- local canself_test = {}

-- local device_name = rtos.bsp()

-- local node_a = true -- A节点写true, B节点写false
-- local can_id = 0
-- local rx_id_ext
-- local tx_id_ext
-- local rx_id_std
-- local tx_id_std
-- local can_tx_message
-- local current_frame_type -- 当前测试的帧类型

-- if node_a then -- A/B节点区分，互相传输测试
--     rx_id_ext = 0x12345677
--     tx_id_ext = 0x12345677
--     rx_id_std = 0x123
--     tx_id_std = 0x123
-- else
--     rx_id_ext = 0x12345677
--     tx_id_ext = 0x12345678
--     rx_id_std = 0x123
--     tx_id_std = 0x124
-- end

-- -- 常用波特率配置列表
-- local baud_rates = {{
--     name = "1Mbps",
--     value = 1000000,
--     pts = 6,
--     pbs1 = 6,
--     pbs2 = 4,
--     sjw = 2
-- }, -- 800Kbps在很多平台上不支持，移除或调整参数
-- -- {name = "800Kbps",  value = 800000, pts = 6, pbs1 = 6, pbs2 = 5, sjw = 2},
-- {
--     name = "500Kbps",
--     value = 500000,
--     pts = 6,
--     pbs1 = 6,
--     pbs2 = 4,
--     sjw = 2
-- }, -- 400Kbps不是标准波特率，移除
-- -- {name = "400Kbps",  value = 400000, pts = 6, pbs1 = 6, pbs2 = 3, sjw = 2},
-- {
--     name = "250Kbps",
--     value = 250000,
--     pts = 6,
--     pbs1 = 6,
--     pbs2 = 4,
--     sjw = 2
-- }, -- 200Kbps不是标准波特率，移除
-- -- {name = "200Kbps",  value = 200000, pts = 6, pbs1 = 6, pbs2 = 3, sjw = 2},
-- {
--     name = "125Kbps",
--     value = 125000,
--     pts = 6,
--     pbs1 = 6,
--     pbs2 = 4,
--     sjw = 2
-- }, {
--     name = "100Kbps",
--     value = 100000,
--     pts = 6,
--     pbs1 = 6,
--     pbs2 = 3,
--     sjw = 2
-- }, {
--     name = "50Kbps",
--     value = 50000,
--     pts = 6,
--     pbs1 = 6,
--     pbs2 = 3,
--     sjw = 2
-- }}

-- local test_cnt = 0
-- local tx_buf = zbuff.create(8)
-- local per_baud_tests = 5 -- 每个波特率每种帧类型的测试次数
-- local current_baud_index = 0
-- local current_test_count = 0
-- local tx_success_count = 0
-- local rx_success_count = 0
-- local baud_test_results = {} -- 保存各波特率测试结果

-- local function can_configuration()
--     if device_name == "Air780EPM" then
--         gpio.setup(1, 1) -- 打开5v电源
--         gpio.setup(32, 1) -- 打开12v电源
--         pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
--         stb_pin = 28
--     elseif device_name == "Air780EHM" or device_name == "Air780EHV" or device_name == "Air780EGG" or device_name ==
--         "Air780EGP" or device_name == "Air780EGH" then
--         stb_pin = 28
--     elseif device_name == "Air8000" then
--         stb_pin = 27
--     elseif device_name == "Air8101" then
--         stb_pin = 46
--     else
--         log.info("未知的设备名称")
--     end
-- end

-- local function can_cb(id, cb_type, param)
--     if cb_type == can.CB_MSG then
--         log.info("有新的消息")
--         local succ, id, id_type, rtr, data = can.rx(id)
--         while succ do
--             local frame_type_str = (id_type == can.STD) and "标准帧" or "扩展帧"
--             log.info("CAN接收",
--                 string.format("[%s] ID:%08X 长度:%d 数据:%s", frame_type_str, id, #data, data:toHex()))
--             local data_message = data:toHex()
--             assert(data_message == can_tx_message,
--                 string.format("CAN接收消息第%d次测试失败: 预期 %s, 实际 %s", current_test_count,
--                     can_tx_message, data_message))
--             log.info("canself_test", "CAN接收消息测试第" .. current_test_count .. "通过")

--             rx_success_count = rx_success_count + 1

--             succ, id, id_type, rtr, data = can.rx(id)
--         end
--     end
--     if cb_type == can.CB_TX then
--         if param then
--             log.info("发送成功")
--             tx_success_count = tx_success_count + 1
--         else
--             log.info("发送失败")
--         end
--     end
--     if cb_type == can.CB_ERR then
--         log.info("CAN错误码", mcu.x32(param))
--     end
--     if cb_type == can.CB_STATE then
--         log.info("CAN新状态", param)
--     end
-- end

-- local function can_tx_test()
--     current_test_count = current_test_count + 1
--     if current_test_count > per_baud_tests then
--         return
--     end

--     log.info("CAN测试", string.format("第%d次测试 [%s]", current_test_count,
--         (current_frame_type == "std") and "标准帧" or "扩展帧"))

--     if node_a then
--         log.info("node a tx---------------")
--     else
--         log.info("node b tx")
--     end

--     test_cnt = test_cnt + 1
--     if test_cnt > 8 then
--         test_cnt = 1
--     end

--     tx_buf:clear()
--     for i = 0, test_cnt - 1 do
--         tx_buf:set(i, test_cnt)
--     end
--     tx_buf:seek(0)
--     local buff_message = tx_buf:read(test_cnt)
--     local hex_string = buff_message:toHex()
--     can_tx_message = hex_string:match("^(%S+)")

--     -- 根据当前帧类型选择ID
--     local tx_id
--     local id_type
--     if current_frame_type == "std" then
--         tx_id = tx_id_std
--         id_type = can.STD
--     else
--         tx_id = tx_id_ext
--         id_type = can.EXT
--     end

--     local tx_message = can.tx(can_id, tx_id, id_type, false, true, tx_buf)

--     assert(tx_message == 0,
--         string.format("CAN发送消息第%d次测试失败: 预期 0, 实际 %s", current_test_count, tx_message))
--     log.info("canself_test", "CAN发送消息测试第" .. current_test_count .. "通过")
-- end

-- -- 测试指定波特率和帧类型
-- local function test_baud_rate_frame(baud_config, frame_type)
--     log.info("canself_test", "")
--     log.info("canself_test",
--         string.format("========== 测试 %s - %s ==========", baud_config.name, (frame_type == "std")))

--     -- 重置状态
--     test_cnt = 0
--     current_test_count = 0
--     tx_success_count = 0
--     rx_success_count = 0
--     current_frame_type = frame_type

--     -- 初始化CAN
--     local caninit_result = can.init(can_id, 128)
--     assert(caninit_result == true, string.format("[%s-%s] CAN初始化测试失败", baud_config.name, frame_type))
--     log.info("canself_test", "CAN初始化测试通过")

--     -- 注册回调
--     can.on(can_id, can_cb)

--     -- 配置时序
--     local can_timing_result = can.timing(can_id, baud_config.value, baud_config.pts, baud_config.pbs1, baud_config.pbs2,
--         baud_config.sjw)
--     assert(can_timing_result == true, string.format("[%s-%s] CAN时序测试失败", baud_config.name, frame_type))
--     log.info("canself_test", string.format("CAN总线配置时序测试通过 (%s)", baud_config.name))

--     -- 配置节点ID
--     local rx_id
--     local id_type
--     if frame_type == "std" then
--         rx_id = rx_id_std
--         id_type = can.STD
--     else
--         rx_id = rx_id_ext
--         id_type = can.EXT
--     end

--     local can_node_result = can.node(can_id, rx_id, id_type)
--     assert(can_node_result == true, string.format("[%s-%s] CAN设置节点ID测试失败", baud_config.name, frame_type))
--     log.info("canself_test", string.format("CAN总线配置节点ID测试通过 (%s)",
--         (frame_type == "std") and "标准帧" or "扩展帧"))

--     -- 设置自测模式
--     local can_mode_result = can.mode(can_id, can.MODE_TEST)
--     assert(can_mode_result == true,
--         string.format("[%s-%s] CAN设置自测模式测试失败", baud_config.name, frame_type))
--     log.info("canself_test", "CAN总线配置自测工作模式测试通过")

--     -- 配置STB引脚
--     gpio.setup(stb_pin, 0)

--     -- 循环执行测试
--     log.info("canself_test", string.format("开始测试，共%d次", per_baud_tests))

--     for i = 1, per_baud_tests do
--         -- 执行一次发送测试
--         can_tx_test()

--         -- 等待接收完成
--         sys.wait(100)

--         -- 验证本次测试的发送和接收
--         if tx_success_count < i or rx_success_count < i then
--             sys.wait(200)
--         end

--         assert(tx_success_count >= i,
--             string.format("[%s-%s] 第%d次发送失败，发送成功次数：%d", baud_config.name, frame_type, i,
--                 tx_success_count))
--         assert(rx_success_count >= i,
--             string.format("[%s-%s] 第%d次接收失败，接收成功次数：%d", baud_config.name, frame_type, i,
--                 rx_success_count))

--         -- 等待500ms再进行下一次
--         if i < per_baud_tests then
--             sys.wait(500)
--         end
--     end

--     -- 最终验证
--     log.info("canself_test", string.format("测试完成统计：发送成功 %d 次，接收成功 %d 次",
--         tx_success_count, rx_success_count))

--     assert(tx_success_count == rx_success_count,
--         string.format("[%s-%s] CAN自测失败: 发送成功 %d 次但接收成功 %d 次", baud_config.name,
--             frame_type, tx_success_count, rx_success_count))
--     assert(tx_success_count == per_baud_tests,
--         string.format("[%s-%s] CAN自测失败: 只发送成功 %d 次，期望 %d 次", baud_config.name, frame_type,
--             tx_success_count, per_baud_tests))

--     log.info("canself_test", string.format("✓ %s - %s 测试通过", baud_config.name, (frame_type == "std")))

--     -- 关闭CAN总线
--     local deinit_result = can.deinit(can_id)
--     assert(deinit_result == true, string.format("[%s-%s] 关闭CAN总线测试失败", baud_config.name, frame_type))

--     sys.wait(200) -- 等待一下，准备下一次测试

--     return true
-- end

-- function canself_test.test_all_baudrates()
--     log.info("canself_test", "")
--     log.info("canself_test", "=========================================")
--     log.info("canself_test", "      CAN自测 - 多波特率测试")
--     log.info("canself_test", "=========================================")

--     -- 硬件配置
--     can_configuration()

--     -- 显示测试计划
--     log.info("canself_test", "")
--     log.info("canself_test", "测试计划:")
--     log.info("canself_test", string.format("- 波特率数量: %d种", #baud_rates))
--     log.info("canself_test", "- 每种波特率测试: 标准帧(%d次) + 扩展帧(%d次)", per_baud_tests,
--         per_baud_tests)
--     log.info("canself_test", "- 总测试次数: %d次", #baud_rates * 2 * per_baud_tests)

--     -- 记录测试结果
--     local pass_count = 0
--     local fail_count = 0
--     local fail_details = {}

--     -- 遍历所有波特率
--     for idx, baud in ipairs(baud_rates) do
--         log.info("canself_test", "")
--         log.info("canself_test",
--             string.format("========== [%d/%d] 测试波特率: %s ==========", idx, #baud_rates, baud.name))

--         -- 测试标准帧
--         local success, err = pcall(function()
--             return test_baud_rate_frame(baud, "std")
--         end)

--         if success then
--             pass_count = pass_count + 1
--         else
--             fail_count = fail_count + 1
--             table.insert(fail_details, string.format("%s-标准帧", baud.name))
--             log.error("canself_test", string.format("✗ %s-标准帧 测试失败: %s", baud.name, err))
--         end

--         -- 测试扩展帧
--         local success, err = pcall(function()
--             return test_baud_rate_frame(baud, "ext")
--         end)

--         if success then
--             pass_count = pass_count + 1
--         else
--             fail_count = fail_count + 1
--             table.insert(fail_details, string.format("%s-扩展帧", baud.name))
--             log.error("canself_test", string.format("✗ %s-扩展帧 测试失败: %s", baud.name, err))
--         end
--     end

--     -- 输出最终测试报告
--     log.info("canself_test", "")
--     log.info("canself_test", "=========================================")
--     log.info("canself_test", "           测试报告")
--     log.info("canself_test", "=========================================")
--     log.info("canself_test", string.format("总测试项: %d", #baud_rates * 2))
--     log.info("canself_test", string.format("通过: %d", pass_count))
--     log.info("canself_test", string.format("失败: %d", fail_count))

--     if fail_count > 0 then
--         log.info("canself_test", "")
--         log.info("canself_test", "失败项:")
--         for i, item in ipairs(fail_details) do
--             log.info("canself_test", string.format("  %d. %s", i, item))
--         end
--     end

--     log.info("canself_test", "")
--     if fail_count == 0 then
--         log.info("canself_test", "✓✓✓ 所有测试全部通过！✓✓✓")
--         log.info("canself_test", "=========================================")
--         return true
--     else
--         log.error("canself_test", "✗✗✗ 部分测试失败 ✗✗✗")
--         log.info("canself_test", "=========================================")
--         return false
--     end
-- end

-- return canself_test


local canself_test = {}

local device_name = rtos.bsp()

local node_a = true -- A节点写true, B节点写false
local can_id = 0
local rx_id_ext
local tx_id_ext
local rx_id_std
local tx_id_std
local can_tx_message
local current_frame_type -- 当前测试的帧类型

if node_a then -- A/B节点区分，互相传输测试
    rx_id_ext = 0x12345677
    tx_id_ext = 0x12345677
    rx_id_std = 0x123
    tx_id_std = 0x123
else
    rx_id_ext = 0x12345677
    tx_id_ext = 0x12345678
    rx_id_std = 0x123
    tx_id_std = 0x124
end

-- 常用波特率配置列表（只保留支持的波特率）
local baud_rates = {
    {name = "1Mbps",   value = 1000000, pts = 6, pbs1 = 6, pbs2 = 4, sjw = 2},
    {name = "500Kbps",  value = 500000, pts = 6, pbs1 = 6, pbs2 = 4, sjw = 2},
    {name = "250Kbps",  value = 250000, pts = 6, pbs1 = 6, pbs2 = 4, sjw = 2},
    {name = "125Kbps",  value = 125000, pts = 6, pbs1 = 6, pbs2 = 4, sjw = 2},
    {name = "100Kbps",  value = 100000, pts = 6, pbs1 = 6, pbs2 = 3, sjw = 2},
    {name = "50Kbps",   value = 50000,  pts = 6, pbs1 = 6, pbs2 = 3, sjw = 2},
}

local test_cnt = 0
local tx_buf = zbuff.create(8)
local per_baud_tests = 3 -- 每个波特率每种帧类型的测试次数（减少次数加快测试）
local current_baud_index = 0
local current_test_count = 0
local tx_success_count = 0
local rx_success_count = 0
local baud_test_results = {} -- 保存各波特率测试结果

-- API测试结果统计
local api_test_results = {
    filter = {pass = 0, fail = 0},
    state = {pass = 0, fail = 0},
    reset = {pass = 0, fail = 0},
    busOff = {pass = 0, fail = 0},
    capacity = {pass = 0, fail = 0},
    deinit = {pass = 0, fail = 0},
    stop = {pass = 0, fail = 0},
}

local function can_configuration()
    if device_name == "Air780EPM" then
        gpio.setup(1, 1) -- 打开5v电源
        gpio.setup(32, 1) -- 打开12v电源
        pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
        stb_pin = 28
    elseif device_name == "Air780EHM" or device_name == "Air780EHV" or device_name == "Air780EGG" or device_name ==
        "Air780EGP" or device_name == "Air780EGH" then
        stb_pin = 28
    elseif device_name == "Air8000" then
        stb_pin = 27
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
            local frame_type_str = (id_type == can.STD) and "标准帧" or "扩展帧"
            log.info("CAN接收", string.format("[%s] ID:%08X 长度:%d 数据:%s", 
                frame_type_str, id, #data, data:toHex()))
            local data_message = data:toHex()
            assert(data_message == can_tx_message,
                string.format("CAN接收消息第%d次测试失败: 预期 %s, 实际 %s", current_test_count,
                    can_tx_message, data_message))
            log.info("canself_test", "CAN接收消息测试第" .. current_test_count .. "通过")

            rx_success_count = rx_success_count + 1

            succ, id, id_type, rtr, data = can.rx(id)
        end
    end
    if cb_type == can.CB_TX then
        if param then
            log.info("发送成功")
            tx_success_count = tx_success_count + 1
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

local function can_tx_test()
    current_test_count = current_test_count + 1
    if current_test_count > per_baud_tests then
        return
    end

    log.info("CAN测试", string.format("第%d次测试 [%s]", current_test_count, 
        (current_frame_type == "std") and "标准帧" or "扩展帧"))

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

    -- 根据当前帧类型选择ID
    local tx_id
    local id_type
    if current_frame_type == "std" then
        tx_id = tx_id_std
        id_type = can.STD
    else
        tx_id = tx_id_ext
        id_type = can.EXT
    end

    local tx_message = can.tx(can_id, tx_id, id_type, false, true, tx_buf)

    assert(tx_message == 0,
        string.format("CAN发送消息第%d次测试失败: 预期 0, 实际 %s", current_test_count, tx_message))
    log.info("canself_test", "CAN发送消息测试第" .. current_test_count .. "通过")
end

-- 测试filter函数（单过滤模式）
local function test_filter_api(baud_config, frame_type)
    log.info("canself_test", "----- 测试 can.filter API -----")
    
    -- 初始化CAN
    local init_result = can.init(can_id, 128)
    assert(init_result == true, "filter测试: CAN初始化失败")
    
    -- 配置波特率
    local timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(timing_result == true, "filter测试: 时序配置失败")
    
    -- 测试filter函数（不使用node）
    local filter_result
    if frame_type == "std" then
        -- 标准帧过滤：接收ID 0x123~0x12F
        -- 标准帧需要左移21位
        filter_result = can.filter(can_id, false, 0x123 << 21, 0x007FFFFF)
    else
        -- 扩展帧过滤：接收ID 0x12345670~0x1234567F
        -- 扩展帧需要左移3位
        filter_result = can.filter(can_id, false, 0x12345670 << 3, 0x0000000F)
    end
    assert(filter_result == true, "filter测试: can.filter配置失败")
    log.info("canself_test", "✓ can.filter配置成功")
    api_test_results.filter.pass = api_test_results.filter.pass + 1
    
    -- 设置自测模式
    local mode_result = can.mode(can_id, can.MODE_TEST)
    assert(mode_result == true, "filter测试: 自测模式设置失败")
    
    -- 配置STB引脚
    gpio.setup(stb_pin, 0)
    
    -- 执行一次发送测试验证filter是否工作
    current_frame_type = frame_type
    current_test_count = 0
    tx_success_count = 0
    rx_success_count = 0
    
    can_tx_test()
    sys.wait(100)
    
    assert(tx_success_count == 1 and rx_success_count == 1, 
        "filter测试: 发送/接收验证失败")
    log.info("canself_test", "✓ filter功能验证通过")
    
    -- 关闭CAN
    can.deinit(can_id)
    sys.wait(200)
end

-- 测试state函数
local function test_state_api(baud_config)
    log.info("canself_test", "----- 测试 can.state API -----")
    
    -- 初始状态应该是停止
    local state = can.state(can_id)
    assert(state == can.STATE_STOP, string.format("state测试: 初始状态应为STOP, 实际为%d", state))
    log.info("canself_test", "✓ 初始状态正确")
    
    -- 初始化CAN
    local init_result = can.init(can_id, 128)
    assert(init_result == true, "state测试: CAN初始化失败")
    
    -- 配置波特率
    local timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(timing_result == true, "state测试: 时序配置失败")
    
    -- 配置节点ID
    local node_result = can.node(can_id, rx_id_std, can.STD)
    assert(node_result == true, "state测试: 节点配置失败")
    
    -- 设置自测模式后状态应该是TEST
    local mode_result = can.mode(can_id, can.MODE_TEST)
    assert(mode_result == true, "state测试: 自测模式设置失败")
    
    sys.wait(100)
    state = can.state(can_id)
    assert(state == can.STATE_TEST, string.format("state测试: 自测模式状态应为TEST, 实际为%d", state))
    log.info("canself_test", "✓ 自测模式状态正确")
    
    -- 关闭CAN
    can.deinit(can_id)
    sys.wait(200)
    
    state = can.state(can_id)
    assert(state == can.STATE_STOP, string.format("state测试: 关闭后状态应为STOP, 实际为%d", state))
    log.info("canself_test", "✓ 关闭后状态正确")
    
    api_test_results.state.pass = api_test_results.state.pass + 1
end

-- 测试reset和busOff函数
local function test_reset_busoff_api(baud_config)
    log.info("canself_test", "----- 测试 can.reset 和 can.busOff API -----")
    
    -- 初始化CAN
    local init_result = can.init(can_id, 128)
    assert(init_result == true, "reset/busOff测试: CAN初始化失败")
    
    -- 配置波特率
    local timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(timing_result == true, "reset/busOff测试: 时序配置失败")
    
    -- 测试busOff
    log.info("canself_test", "测试 can.busOff...")
    local busoff_result = can.busOff(can_id)
    assert(busoff_result == true, "busOff测试失败")
    log.info("canself_test", "✓ can.busOff成功")
    
    -- busOff后状态应该是STOP
    sys.wait(100)
    local state = can.state(can_id)
    assert(state == can.STATE_STOP, string.format("busOff后状态应为STOP, 实际为%d", state))
    log.info("canself_test", "✓ busOff后状态正确")
    
    -- 测试reset
    log.info("canself_test", "测试 can.reset...")
    local reset_result = can.reset(can_id)
    assert(reset_result == true, "reset测试失败")
    log.info("canself_test", "✓ can.reset成功")
    
    -- reset后需要重新配置才能工作
    timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(timing_result == true, "reset后时序配置失败")
    
    local node_result = can.node(can_id, rx_id_std, can.STD)
    assert(node_result == true, "reset后节点配置失败")
    
    local mode_result = can.mode(can_id, can.MODE_TEST)
    assert(mode_result == true, "reset后自测模式设置失败")
    
    gpio.setup(stb_pin, 0)
    
    -- 验证reset后能否正常工作
    current_frame_type = "std"
    current_test_count = 0
    tx_success_count = 0
    rx_success_count = 0
    
    can_tx_test()
    sys.wait(100)
    
    assert(tx_success_count == 1 and rx_success_count == 1, "reset后功能验证失败")
    log.info("canself_test", "✓ reset后功能正常")
    
    api_test_results.reset.pass = api_test_results.reset.pass + 1
    api_test_results.busOff.pass = api_test_results.busOff.pass + 1
    
    -- 关闭CAN
    can.deinit(can_id)
    sys.wait(200)
end

-- 测试capacity函数
local function test_capacity_api()
    log.info("canself_test", "----- 测试 can.capacity API -----")
    
    local result, clk, div_min, div_max, div_step = can.capacity(can_id)
    assert(result == true, "capacity测试失败")
    assert(clk > 0, string.format("capacity: 时钟频率应为正数, 实际%d", clk))
    assert(div_min >= 1, string.format("capacity: 最小分频系数应≥1, 实际%d", div_min))
    assert(div_max >= div_min, string.format("capacity: 最大分频系数应≥最小分频系数, 实际%d≥%d", div_max, div_min))
    assert(div_step >= 1, string.format("capacity: 分频步进应≥1, 实际%d", div_step))
    
    log.info("canself_test", string.format("基础时钟: %.2f MHz", clk / 1000000))
    log.info("canself_test", string.format("分频范围: %d - %d 步进:%d", div_min, div_max, div_step))
    log.info("canself_test", "✓ can.capacity测试通过")
    
    api_test_results.capacity.pass = api_test_results.capacity.pass + 1
end

-- 测试deinit函数
local function test_deinit_api(baud_config)
    log.info("canself_test", "----- 测试 can.deinit API -----")
    
    -- 初始化CAN
    local init_result = can.init(can_id, 128)
    assert(init_result == true, "deinit测试: CAN初始化失败")
    
    -- 配置并启动
    local timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(timing_result == true, "deinit测试: 时序配置失败")
    
    local node_result = can.node(can_id, rx_id_std, can.STD)
    assert(node_result == true, "deinit测试: 节点配置失败")
    
    local mode_result = can.mode(can_id, can.MODE_TEST)
    assert(mode_result == true, "deinit测试: 自测模式设置失败")
    
    gpio.setup(stb_pin, 0)
    
    -- 测试deinit
    log.info("canself_test", "测试 can.deinit...")
    local deinit_result = can.deinit(can_id)
    assert(deinit_result == true, "deinit测试失败")
    log.info("canself_test", "✓ can.deinit成功")
    
    -- deinit后状态应该是STOP
    sys.wait(100)
    local state = can.state(can_id)
    assert(state == can.STATE_STOP, string.format("deinit后状态应为STOP, 实际为%d", state))
    log.info("canself_test", "✓ deinit后状态正确")
    
    -- 验证deinit后不能工作（应该会失败）
    local tx_result = can.tx(can_id, tx_id_std, can.STD, false, true, tx_buf)
    assert(tx_result ~= 0, "deinit后发送应该失败")
    log.info("canself_test", "✓ deinit后无法发送（符合预期）")
    
    api_test_results.deinit.pass = api_test_results.deinit.pass + 1
end

-- 测试stop函数
local function test_stop_api(baud_config)
    log.info("canself_test", "----- 测试 can.stop API -----")
    
    -- 初始化CAN
    local init_result = can.init(can_id, 128)
    assert(init_result == true, "stop测试: CAN初始化失败")
    
    -- 配置
    local timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(timing_result == true, "stop测试: 时序配置失败")
    
    local node_result = can.node(can_id, rx_id_std, can.STD)
    assert(node_result == true, "stop测试: 节点配置失败")
    
    local mode_result = can.mode(can_id, can.MODE_TEST)
    assert(mode_result == true, "stop测试: 自测模式设置失败")
    
    gpio.setup(stb_pin, 0)
    
    -- 测试stop（在自测模式下可能没有正在发送的数据，但API应该返回成功）
    log.info("canself_test", "测试 can.stop...")
    local stop_result = can.stop(can_id)
    assert(stop_result == true, "stop测试失败")
    log.info("canself_test", "✓ can.stop成功")
    
    -- stop后应该还能继续发送
    current_frame_type = "std"
    current_test_count = 0
    tx_success_count = 0
    rx_success_count = 0
    
    can_tx_test()
    sys.wait(100)
    
    assert(tx_success_count == 1 and rx_success_count == 1, "stop后功能验证失败")
    log.info("canself_test", "✓ stop后功能正常")
    
    api_test_results.stop.pass = api_test_results.stop.pass + 1
    
    -- 关闭CAN
    can.deinit(can_id)
    sys.wait(200)
end

-- 测试指定波特率和帧类型
local function test_baud_rate_frame(baud_config, frame_type)
    log.info("canself_test", "")
    log.info("canself_test", string.format("========== 测试 %s - %s ==========", 
        baud_config.name, (frame_type == "std")))

    -- 重置状态
    test_cnt = 0
    current_test_count = 0
    tx_success_count = 0
    rx_success_count = 0
    current_frame_type = frame_type

    -- 初始化CAN
    local caninit_result = can.init(can_id, 128)
    assert(caninit_result == true, string.format("[%s-%s] CAN初始化测试失败", 
        baud_config.name, frame_type))
    log.info("canself_test", "CAN初始化测试通过")

    -- 注册回调
    can.on(can_id, can_cb)

    -- 配置时序
    local can_timing_result = can.timing(can_id, baud_config.value, 
        baud_config.pts, baud_config.pbs1, baud_config.pbs2, baud_config.sjw)
    assert(can_timing_result == true, string.format("[%s-%s] CAN时序测试失败", 
        baud_config.name, frame_type))
    log.info("canself_test", string.format("CAN总线配置时序测试通过 (%s)", baud_config.name))

    -- 配置节点ID
    local rx_id
    local id_type
    if frame_type == "std" then
        rx_id = rx_id_std
        id_type = can.STD
    else
        rx_id = rx_id_ext
        id_type = can.EXT
    end
    
    local can_node_result = can.node(can_id, rx_id, id_type)
    assert(can_node_result == true, string.format("[%s-%s] CAN设置节点ID测试失败", 
        baud_config.name, frame_type))
    log.info("canself_test", string.format("CAN总线配置节点ID测试通过 (%s)", 
        (frame_type == "std") and "标准帧" or "扩展帧"))

    -- 设置自测模式
    local can_mode_result = can.mode(can_id, can.MODE_TEST)
    assert(can_mode_result == true, string.format("[%s-%s] CAN设置自测模式测试失败", 
        baud_config.name, frame_type))
    log.info("canself_test", "CAN总线配置自测工作模式测试通过")

    -- 配置STB引脚
    gpio.setup(stb_pin, 0)

    -- 循环执行测试
    log.info("canself_test", string.format("开始测试，共%d次", per_baud_tests))

    for i = 1, per_baud_tests do
        -- 执行一次发送测试
        can_tx_test()

        -- 等待接收完成
        sys.wait(100)

        -- 验证本次测试的发送和接收
        if tx_success_count < i or rx_success_count < i then
            sys.wait(200)
        end

        assert(tx_success_count >= i,
            string.format("[%s-%s] 第%d次发送失败，发送成功次数：%d", 
                baud_config.name, frame_type, i, tx_success_count))
        assert(rx_success_count >= i,
            string.format("[%s-%s] 第%d次接收失败，接收成功次数：%d", 
                baud_config.name, frame_type, i, rx_success_count))

        -- 等待再进行下一次
        if i < per_baud_tests then
            sys.wait(300)
        end
    end

    -- 最终验证
    log.info("canself_test", string.format("测试完成统计：发送成功 %d 次，接收成功 %d 次",
        tx_success_count, rx_success_count))

    assert(tx_success_count == rx_success_count, 
        string.format("[%s-%s] CAN自测失败: 发送成功 %d 次但接收成功 %d 次", 
            baud_config.name, frame_type, tx_success_count, rx_success_count))
    assert(tx_success_count == per_baud_tests,
        string.format("[%s-%s] CAN自测失败: 只发送成功 %d 次，期望 %d 次",
            baud_config.name, frame_type, tx_success_count, per_baud_tests))

    log.info("canself_test", string.format("✓ %s - %s 测试通过", 
        baud_config.name, (frame_type == "std")))

    -- 关闭CAN总线
    local deinit_result = can.deinit(can_id)
    assert(deinit_result == true, string.format("[%s-%s] 关闭CAN总线测试失败", 
        baud_config.name, frame_type))
    
    sys.wait(200)
    
    return true
end

function canself_test.test_all_baudrates()
    log.info("canself_test", "")
    log.info("canself_test", "=========================================")
    log.info("canself_test", "      CAN自测 - 多波特率测试 + API测试")
    log.info("canself_test", "=========================================")

    -- 硬件配置
    can_configuration()

    -- 显示测试计划
    log.info("canself_test", "")
    log.info("canself_test", "测试计划:")
    log.info("canself_test", string.format("- 波特率数量: %d种", #baud_rates))
    log.info("canself_test", "- 每种波特率测试: 标准帧(%d次) + 扩展帧(%d次)", per_baud_tests, per_baud_tests)
    log.info("canself_test", "- 总测试次数: %d次", #baud_rates * 2 * per_baud_tests)
    log.info("canself_test", "- API测试: filter/state/reset/busOff/capacity/deinit/stop")

    -- 记录测试结果
    local pass_count = 0
    local fail_count = 0
    local fail_details = {}

    -- 先测试capacity（不依赖CAN初始化）
    local success, err = pcall(function()
        test_capacity_api()
    end)
    if not success then
        fail_count = fail_count + 1
        table.insert(fail_details, string.format("capacity测试失败: %s", err))
        api_test_results.capacity.fail = api_test_results.capacity.fail + 1
    end

    -- 遍历所有波特率
    for idx, baud in ipairs(baud_rates) do
        log.info("canself_test", "")
        log.info("canself_test", string.format("========== [%d/%d] 测试波特率: %s ==========", 
            idx, #baud_rates, baud.name))

        -- 测试标准帧
        local success, err = pcall(function()
            return test_baud_rate_frame(baud, "std")
        end)
        
        if success then
            pass_count = pass_count + 1
        else
            fail_count = fail_count + 1
            table.insert(fail_details, string.format("%s-标准帧", baud.name))
            log.error("canself_test", string.format("✗ %s-标准帧 测试失败: %s", baud.name, err))
        end

        -- 测试扩展帧
        local success, err = pcall(function()
            return test_baud_rate_frame(baud, "ext")
        end)
        
        if success then
            pass_count = pass_count + 1
        else
            fail_count = fail_count + 1
            table.insert(fail_details, string.format("%s-扩展帧", baud.name))
            log.error("canself_test", string.format("✗ %s-扩展帧 测试失败: %s", baud.name, err))
        end
    end

    -- 使用第一个波特率进行API测试
    if #baud_rates > 0 then
        local test_baud = baud_rates[1]
        
        -- 测试filter
        local success, err = pcall(function()
            test_filter_api(test_baud, "std")
            test_filter_api(test_baud, "ext")
        end)
        if not success then
            api_test_results.filter.fail = api_test_results.filter.fail + 2
            table.insert(fail_details, string.format("filter测试失败: %s", err))
        end
        
        -- 测试state
        success, err = pcall(function()
            test_state_api(test_baud)
        end)
        if not success then
            api_test_results.state.fail = api_test_results.state.fail + 1
            table.insert(fail_details, string.format("state测试失败: %s", err))
        end
        
        -- 测试reset和busOff
        success, err = pcall(function()
            test_reset_busoff_api(test_baud)
        end)
        if not success then
            api_test_results.reset.fail = api_test_results.reset.fail + 1
            api_test_results.busOff.fail = api_test_results.busOff.fail + 1
            table.insert(fail_details, string.format("reset/busOff测试失败: %s", err))
        end
        
        -- 测试deinit
        success, err = pcall(function()
            test_deinit_api(test_baud)
        end)
        if not success then
            api_test_results.deinit.fail = api_test_results.deinit.fail + 1
            table.insert(fail_details, string.format("deinit测试失败: %s", err))
        end
        
        -- 测试stop
        success, err = pcall(function()
            test_stop_api(test_baud)
        end)
        if not success then
            api_test_results.stop.fail = api_test_results.stop.fail + 1
            table.insert(fail_details, string.format("stop测试失败: %s", err))
        end
    end

    -- 输出最终测试报告
    log.info("canself_test", "")
    log.info("canself_test", "=========================================")
    log.info("canself_test", "           测试报告")
    log.info("canself_test", "=========================================")
    log.info("canself_test", string.format("波特率测试项: %d", #baud_rates * 2))
    log.info("canself_test", string.format("通过: %d", pass_count))
    log.info("canself_test", string.format("失败: %d", fail_count))
    
    log.info("canself_test", "")
    log.info("canself_test", "API测试结果:")
    log.info("canself_test", string.format("  filter  : 通过%d, 失败%d", 
        api_test_results.filter.pass, api_test_results.filter.fail))
    log.info("canself_test", string.format("  state   : 通过%d, 失败%d", 
        api_test_results.state.pass, api_test_results.state.fail))
    log.info("canself_test", string.format("  reset   : 通过%d, 失败%d", 
        api_test_results.reset.pass, api_test_results.reset.fail))
    log.info("canself_test", string.format("  busOff  : 通过%d, 失败%d", 
        api_test_results.busOff.pass, api_test_results.busOff.fail))
    log.info("canself_test", string.format("  capacity: 通过%d, 失败%d", 
        api_test_results.capacity.pass, api_test_results.capacity.fail))
    log.info("canself_test", string.format("  deinit  : 通过%d, 失败%d", 
        api_test_results.deinit.pass, api_test_results.deinit.fail))
    log.info("canself_test", string.format("  stop    : 通过%d, 失败%d", 
        api_test_results.stop.pass, api_test_results.stop.fail))

    if fail_count > 0 or 
       api_test_results.filter.fail > 0 or
       api_test_results.state.fail > 0 or
       api_test_results.reset.fail > 0 or
       api_test_results.busOff.fail > 0 or
       api_test_results.capacity.fail > 0 or
       api_test_results.deinit.fail > 0 or
       api_test_results.stop.fail > 0 then
        log.info("canself_test", "")
        log.info("canself_test", "失败项:")
        for i, item in ipairs(fail_details) do
            log.info("canself_test", string.format("  %d. %s", i, item))
        end
        log.info("canself_test", "")
        log.error("canself_test", "✗✗✗ 部分测试失败 ✗✗✗")
        log.info("canself_test", "=========================================")
        return false
    else
        log.info("canself_test", "")
        log.info("canself_test", "✓✓✓ 所有测试全部通过！✓✓✓")
        log.info("canself_test", "=========================================")
        return true
    end
end

return canself_test