--[[
@module unactive_mode
@summary 未激活模式 - 绑定窗口版本
@version 4.4
@date    2026.07.23
@usage
设备开机后自动进入绑定窗口流程：
1. LED "三长一短" 指示可绑定状态
2. 蓝牙广播（名称由服务端 BLE_CONFIG 配置）
3. 连接云平台并上报 bind_ready
4. 进入透传模式，等待手机 BLE 连接发送命令
5. 等待服务端通过 REMOTE_COMMAND 下发 change_mode 完成绑定
6. 超时未绑定则自动关机

手机 BLE 发送格式（JSON 字符串）：
  {"command":"change_mode","data":{"params":{"mode":0}}}
  {"command":"change_mode","data":{"params":{"mode":1}}}
  {"command":"change_mode","data":{"params":{"mode":2}}}
]]

local config = require("config")
local kvstore = require("kvstore")
local tools = require("tools")
local ble_bind = require("ble_bind")
local air5101_uart = require("air5101_uart")
local create = require("create")

-- BLE 数据队列（回调写入，主循环读取）
local ble_data_queue = {}

-- 获取蓝牙设备名称（与服务端配置一致）
local function get_ble_name()
    local imei = mobile.imei() or "000000000000000"
    local ble_cfg = config.BLE_CONFIG or {}
    local prefix = ble_cfg.adv_name_prefix or "irtu-"
    local suffix_rule = ble_cfg.adv_name_suffix or "imei_last6"
    local suffix
    if suffix_rule == "imei_last6" then
        suffix = string.sub(imei, -6)
    elseif suffix_rule == "imei_last4" then
        suffix = string.sub(imei, -4)
    elseif suffix_rule == "imei_all" then
        suffix = imei
    else
        suffix = string.sub(imei, -6)
    end
    return prefix .. suffix
end

-- LED "三长一短" 指示（蓝灯）
local function led_bind_pattern()
    for _ = 1, 3 do
        tools.blueLed_ON()
        sys.wait(1000)
        tools.allLed_OFF()
        sys.wait(500)
    end
    tools.blueLed_ON()
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
        bluetooth_name = get_ble_name()
    }
    local payload = json.encode(msg)
    create.send(payload)
    log.info("unactive_mode", "已上报 bind_ready, bt_name:", msg.data.bluetooth_name)
end

-- 处理收到的 BLE 命令
-- 支持三种格式：
--   云平台格式: {"command":"change_mode","data":{"params":{"mode":0}}}
--   BLE 直连格式: {"cmd":"change_mode","mode":1}
--   系统消息（忽略）: UT:CONNECTED / UT:DISCONNECTED
local function handle_ble_cmd(data)
    log.info("unactive_mode", "收到 BLE 数据:", data)
    -- 过滤非 JSON 系统消息（如 UT:CONNECTED）
    if type(data) ~= "string" or #data == 0 or string.byte(data, 1) ~= 0x7B then
        log.info("unactive_mode", "忽略非 JSON 系统消息:", data)
        return false
    end
    local ok, cmd = pcall(json.decode, data)
    if not ok or not cmd then
        log.warn("unactive_mode", "BLE 数据不是有效 JSON:", data)
        return false
    end
    -- 兼容两种命令名: command / cmd
    local cmd_name = cmd.command or cmd.cmd
    if cmd_name ~= "change_mode" then
        log.warn("unactive_mode", "未知 BLE 命令:", cmd_name)
        return false
    end
    -- 兼容两种格式: data.params.mode / 直接 mode
    local mode = (cmd.data and cmd.data.params and cmd.data.params.mode) or cmd.mode
    if mode == nil then
        log.warn("unactive_mode", "change_mode 缺少 mode 参数")
        return false
    end
    log.info("unactive_mode", "BLE 收到 change_mode:", mode)
    kvstore.set_work_mode(mode)
    return true
end

-- 绑定窗口主任务
local function task()
    local boot_tick = mcu.ticks()
    local tick_hz = mcu.hz()
    local ble_cfg = config.BLE_CONFIG or {}
    -- 绑定窗口超时(秒)，优先使用服务端配置，默认 300 秒
    local BIND_TIMEOUT = ble_cfg.bind_window_timeout or 300

    log.info("unactive_mode", "===== 进入绑定窗口 =====")

    -- 1. 初始化 LED 和蓝牙
    tools.init_led()
    if ble_bind.open() then
        ble_bind.start_bind_mode()
        log.info("unactive_mode", "蓝牙广播已开启, 名称:", get_ble_name())
    else
        log.error("unactive_mode", "蓝牙电源打开失败")
    end

    -- 2. LED 闪烁放到独立协程
    sys.taskInit(led_bind_pattern)

    -- 3. 注册 BLE 数据回调（写入队列，不发布事件）
    air5101_uart.set_ble_data_callback(function(data)
        table.insert(ble_data_queue, data)
    end)
    if not air5101_uart.enter_transparent_mode() then
        log.warn("unactive_mode", "进入透传模式失败，将仅支持云命令绑定")
    end

    -- 4. 等待网络就绪（与 create.lua 一致）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("unactive_mode", "网络已就绪")

    -- 5. 等待云平台连接
    sys.waitUntil("CLOUD_CONNECTED", 30000)

    -- 6. 上报 bind_ready
    report_bind_ready()

    -- 7. 等待一小段时间确保消息发送完成
    sys.wait(3000)

    -- 8. 等待绑定完成或超时（同时监听 BLE 和云命令）
    log.info("unactive_mode", "开始监听绑定命令（BLE 透传 / 云命令），超时", BIND_TIMEOUT, "秒")
    while (mcu.ticks() - boot_tick) / tick_hz < BIND_TIMEOUT do
        -- 检查 BLE 数据队列（exril_5101 回调写入）
        local ble_data = table.remove(ble_data_queue, 1)
        if ble_data then
            if handle_ble_cmd(ble_data) then
                log.info("unactive_mode", "BLE 绑定成功，即将重启")
                sys.wait(3000)
                pm.reboot()
            end
        end

        -- 检查是否已被云命令修改
        local work_mode = kvstore.get_work_mode()
        if work_mode ~= config.DEVICE_MODE.UNACTIVATED then
            log.info("unactive_mode", "云命令绑定成功, 工作模式已变更:", work_mode)
            sys.wait(5000)
            pm.reboot()
        end

        -- 每 1 秒检查一次
        sys.wait(1000)
    end

    -- 超时：根据服务端配置执行动作
    local timeout_action = ble_cfg.timeout_action or "shutdown"
    log.info("unactive_mode", "绑定窗口超时，执行动作:", timeout_action)
    air5101_uart.exit_transparent_mode()
    ble_bind.stop()
    ble_bind.close()
    sys.wait(1000)
    if timeout_action == "low_power" then
        -- 低功耗模式：进入 PSM 超低功耗，等待下次唤醒
        log.info("unactive_mode", "进入低功耗模式")
        -- 使用 WORK_MODE 方式进入 PSM，再用 dtimer 定时唤醒
        if pm.ACTIVE and pm.PS then
            pm.power(pm.ACTIVE, false)
            pm.wakeup(pm.PS, 300000)
        else
            pm.power(pm.WORK_MODE, 3)
            pm.dtimerStart(3, 300000)
        end
        sys.wait(1000)
    elseif timeout_action == "reboot" then
        pm.reboot()
    else
        pm.shutdown()
    end
end

log.info("unactive_mode", "启动绑定窗口模式")
sys.taskInit(task)