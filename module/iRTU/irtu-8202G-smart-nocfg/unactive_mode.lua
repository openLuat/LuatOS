--[[
@module unactive_mode
@summary 未激活模式 - 绑定窗口版本（无蓝牙，仅云命令绑定）
@version 4.4
@date    2026.07.23
@usage
设备开机后自动进入绑定窗口流程：
1. LED "三长一短" 指示可绑定状态
2. 连接云平台并上报 bind_ready
3. 等待服务端通过 REMOTE_COMMAND 下发 change_mode 完成绑定
4. 超时未绑定则自动关机

本硬件无蓝牙（Air5101）模块，绑定仅支持云命令方式。
]]

local config = require("config")
local kvstore = require("kvstore")
local tools = require("tools")
local create = require("create")

-- LED "三长一短" 指示（绿灯，可绑定状态）
local function led_bind_pattern()
    for _ = 1, 3 do
        tools.greenLed_ON()
        sys.wait(1000)
        tools.allLed_OFF()
        sys.wait(500)
    end
    tools.greenLed_ON()
    sys.wait(300)
    tools.allLed_OFF()
    log.info("unactive_mode", "LED 三长一短 完成")
end

-- 构建消息框架
local function build_msg(msg_type)
    local imei = mobile.imei() or "000000000000000"
    local ts = os.time()
    return {
        msg_id = imei .. "-" .. ts,
        imei = imei,
        product_key = "Air8201-v2",
        ts = ts,
        type = msg_type,
        data = {}
    }
end

-- 上报 bind_ready 事件
local function report_bind_ready()
    local imei = mobile.imei() or "000000000000000"
    local msg = build_msg("bind_ready")
    msg.data = {
        bind_window = 300,
        bluetooth_name = ""
    }
    local payload = json.encode(msg)
    create.send(payload)
    log.info("unactive_mode", "已上报 bind_ready")
end

-- 绑定窗口主任务
local function task()
    local boot_tick = mcu.ticks()
    local tick_hz = mcu.hz()
    -- 绑定窗口超时(秒)
    local BIND_TIMEOUT = 300

    log.info("unactive_mode", "===== 进入绑定窗口（无蓝牙，仅云命令） =====")

    -- 1. 初始化 LED
    tools.init_led()

    -- 2. LED 闪烁放到独立协程
    sys.taskInit(led_bind_pattern)

    -- 3. 等待网络就绪（与 create.lua 一致）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("unactive_mode", "网络已就绪")

    -- 4. 等待云平台连接
    sys.waitUntil("CLOUD_CONNECTED", 30000)

    -- 5. 上报 bind_ready
    report_bind_ready()

    -- 6. 等待一小段时间确保消息发送完成
    sys.wait(3000)

    -- 7. 等待绑定完成或超时（监听云命令）
    log.info("unactive_mode", "开始监听绑定命令（云命令），超时", BIND_TIMEOUT, "秒")
    while (mcu.ticks() - boot_tick) / tick_hz < BIND_TIMEOUT do
        -- 检查是否已被云命令修改工作模式
        local work_mode = kvstore.get_work_mode()
        if work_mode ~= config.DEVICE_MODE.UNACTIVATED then
            log.info("unactive_mode", "云命令绑定成功, 工作模式已变更:", work_mode)
            sys.wait(5000)
            pm.reboot()
        end

        -- 每 1 秒检查一次
        sys.wait(1000)
    end

    -- 超时：自动关机
    local timeout_action = "shutdown"
    log.info("unactive_mode", "绑定窗口超时，执行动作:", timeout_action)
    pm.shutdown()
end

log.info("unactive_mode", "启动绑定窗口模式")
sys.taskInit(task)
