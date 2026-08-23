--[[
AirLink nanopb GPIO RPC loopback 测试

测试条件: PC 模拟器, LUAT_USE_AIRLINK_LOOPBACK 已启用
测试内容:
  1. airlink 模块可加载且包含 testNanopbGpio / MODE_LOOPBACK
  2. loopback 模式可正常启动
  3. 端到端 GPIO write/read 流程 (nanopb encode → 队列传输 → decode → handler → response)
  4. 未知 rpc_id 调用正确触发超时
--]]

local nanopb_tests = {}

local TAG = "nanopb_test"

-- LuatOS 的 luaL_requiref 只设置全局变量而不写入 package.loaded,
-- 因此 C 内置模块必须通过全局变量访问，不能用 require()。
local airlink = _G.airlink

-- 测试: airlink 模块有 testNanopbGpio 和 MODE_LOOPBACK 常量
function nanopb_tests.test_01_module_has_nanopb_api()
    assert(airlink ~= nil, "airlink 全局变量不存在 (C 模块未编译?)")
    assert(type(airlink.testNanopbGpio) == "function",
        "airlink.testNanopbGpio 不存在")
    assert(type(airlink.testNanopbUart) == "function",
        "airlink.testNanopbUart 不存在")
    assert(type(airlink.testNanopbWlan) == "function",
        "airlink.testNanopbWlan 不存在")
    assert(type(airlink.testNanopbPm) == "function",
        "airlink.testNanopbPm 不存在")
    assert(type(airlink.MODE_LOOPBACK) == "number",
        "airlink.MODE_LOOPBACK 不存在")
    log.info(TAG, "模块 API 检查通过")
end

-- 测试: loopback 启动 + 端到端 GPIO RPC (write/read/timeout)
function nanopb_tests.test_02_loopback_gpio_rpc()
    if airlink == nil then
        log.info(TAG, "airlink 模块不可用, 跳过")
        assert(true)
        return
    end

    -- 启动 loopback 模式 (内部同时启动 airlink task 和 slave task)
    log.info(TAG, "启动 loopback 模式 ...")
    airlink.start(airlink.MODE_LOOPBACK)

    -- 稍等任务初始化
    sys.wait(200)

    -- 执行 C 层 nanopb GPIO RPC 测试
    log.info(TAG, "执行 testNanopbGpio ...")
    local rc = airlink.testNanopbGpio()
    log.info(TAG, "testNanopbGpio 返回", rc)

    assert(rc == 0,
        string.format("nanopb GPIO RPC 测试失败, 步骤错误码=%d", rc))
    log.info(TAG, "nanopb GPIO RPC 端到端测试通过")
end

-- 测试: UART nanopb RPC (setup/write/close)
function nanopb_tests.test_03_uart_rpc()
    if airlink == nil then
        log.info(TAG, "airlink 模块不可用, 跳过")
        assert(true)
        return
    end
    local rc = airlink.testNanopbUart()
    log.info(TAG, "testNanopbUart 返回", rc)
    assert(rc == 0,
        string.format("nanopb UART RPC 测试失败, 步骤错误码=%d", rc))
    log.info(TAG, "nanopb UART RPC 端到端测试通过")
end

-- 测试: WLAN nanopb RPC (init/scan/ap_start/ap_stop)
function nanopb_tests.test_04_wlan_rpc()
    if airlink == nil then
        log.info(TAG, "airlink 模块不可用, 跳过")
        assert(true)
        return
    end
    local rc = airlink.testNanopbWlan()
    log.info(TAG, "testNanopbWlan 返回", rc)
    assert(rc == 0,
        string.format("nanopb WLAN RPC 测试失败, 步骤错误码=%d", rc))
    log.info(TAG, "nanopb WLAN RPC 端到端测试通过")
end

-- 测试: PM nanopb RPC (power_ctrl/wakeup_pin/pm_request)
function nanopb_tests.test_05_pm_rpc()
    if airlink == nil then
        log.info(TAG, "airlink 模块不可用, 跳过")
        assert(true)
        return
    end
    local rc = airlink.testNanopbPm()
    log.info(TAG, "testNanopbPm 返回", rc)
    assert(rc == 0,
        string.format("nanopb PM RPC 测试失败, 步骤错误码=%d", rc))
    log.info(TAG, "nanopb PM RPC 端到端测试通过")
end

return nanopb_tests
