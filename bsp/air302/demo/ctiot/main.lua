-- ctiot库API
-- ctiot.init() 
-- 初始化引擎，开机后只需要一次，没有参数输入输出
-- ctiot.ep(new_ep) 
-- 设置读取用户自定义EP，如果不设置，则使用IMEI，输入新的EP，同时输出当前EP，
-- 输入nil，则为读取，输入""，清除EP
-- ctiot.param(server_ip, server_port, lifetime)
-- 设置读取必要的参数，分别为服务器IP，端口和保活时间
-- 输入nil，则为读取参数
-- ctiot.connect()
-- 启动连接服务器
-- ctiot.disconnect()
-- 断开服务器
-- ctiot.write(data, mode, seq)
-- 发送数据，输入参数为数据，发送模式，发送序号
-- 发送模式为ctiot.CON, ctiot.NON, ctiot.NON_REL, ctiot.CON_REL
-- 发送序号只是一个标识，不会影响发送的数据和模式，在发送结果回调时会返回

PROJECT = "ctiot"
VERSION = "1.0.0"
local TAG="ctiot"
-- sys库是标配
_G.sys = require("sys")

local function cb_rx(data)
    log.info(TAG, "rx", data:toHex())
end

local function cb_dereg(error, error_code, param)
    log.info(TAG, "dereg", error, error_code, param)
end

local function cb_wakeup(error, error_code, param)
    log.info(TAG, "wakeup", error, error_code, param)
end

local function cb_fota(error, error_code, param)
    log.info(TAG, "fota", error, error_code, param)
end

local function cb_other(error, error_code, param)
    log.info(TAG, "other", error, error_code, param)
end

--sys.subscribe("CTIOT_TX", cb_tx)
sys.subscribe("CTIOT_RX", cb_rx)
--sys.subscribe("CTIOT_REG", cb_reg)
--sys.subscribe("CTIOT_DEREG", cb_dereg)
sys.subscribe("CTIOT_WAKEUP", cb_wakeup)
sys.subscribe("CTIOT_OTHER", cb_other)
sys.subscribe("CTIOT_FOTA", cb_fota)

local function send_test()
    log.info(TAG, "test tx")
    --发送的数据请按照自己的profile修改
    --发送数据，并要求服务器应答
    ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.CON, 33)
    --发送数据，并要求服务器应答，序号为11
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.CON, 11)
    --发送数据，不需要服务器应答
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.NON, 0)
    --发送数据，不需要服务器应答，序号为23
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.NON, 23)
    --发送数据，不需要服务器应答，发送完成后立刻释放RRC，加快进入休眠的速度
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.NON_REL, 0)
    --发送数据，不需要服务器应答，发送完成后立刻释放RRC，加快进入休眠的速度，序号为56
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.NON_REL, 56)
    --发送数据，并要求服务器应答，接收到应答后立刻释放RRC，加快进入休眠的速度
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.CON_REL, 0)
    --发送数据，并要求服务器应答，接收到应答后立刻释放RRC，加快进入休眠的速度，序号为255，序号最大255
    --ctiot.write(pack.pack("<bbA", 0x00,0x05, "hello"), ctiot.CON_REL, 255)
    local result, tx_error, error_code, param = sys.waitUntilExt("CTIOT_TX", 20000)
    if result then
        if not tx_error then
            log.info(TAG, "tx ok", param)
        else
            log.info(TAG, "tx fail", error_code, param)
        end
    else
        log.info(TAG, "tx no work")
    end

end

local function task()
    local inSleep = false
    local isConnected = false
    --设置自定义EP，如果不设置，则使用IMEI
    local ep="qweasdzxcrtyfgh"
    if ctiot.ep() ~= ep then
        ctiot.ep(ep)
    end
    --设置服务器IP，端口，保活时间
    ctiot.param("180.101.147.115", 5683, 300)
    local ip, port, keeptime = ctiot.param()
    log.info(TAG, "set param", ip, port, keeptime)
	while not socket.isReady() do 
		log.info("net", "wait for network ready")
		sys.waitUntil("NET_READY", 1000)
    end
    -- 非普通上电/复位上电,那就是唤醒上电咯
    if pm.lastReson() ~= 0 then
        isConnected = true
    else
        --启动连接
        pm.request(pm.IDLE)
        ctiot.connect()
        local result, reg_error, error_code, param
        while true do
            result, reg_error, error_code, param = sys.waitUntilExt("CTIOT_REG", 30000)
            if not result and reg_error==nil then
                log.info(TAG, "reg wait timeout")
                break
            end
            log.info(TAG, result, reg_error, error_code, param)
            if not reg_error and param > 0 then
                log.info(TAG, "reg ok")
                isConnected = true
                break
            end
            if reg_error then
                log.info(TAG, "reg fail")
                break
            end
        end

    end
    if isConnected then
        send_test()
    end
    -- 30秒后唤醒,发个测试数据
    if not inSleep then
        pm.dtimerStart(0, 30000)
        inSleep = true
    end
    -- 我要睡了!!! 事实上还会等几秒, 这时候服务器还能下发数据
    pm.request(pm.DEEP)
    -- 退出CTIOT
    -- ctiot.dereg()
    -- result, dereg_error, error_code, param = sys.waitUntilExt("CTIOT_DEREG", 30000)
end
ctiot.init()
sys.taskInit(task)
sys.run()