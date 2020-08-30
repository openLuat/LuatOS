PROJECT = "ctiot"
VERSION = "1.0.0"
local TAG="ctiot"
-- sys库是标配
_G.sys = require("sys")

local function cb_reg(error, error_code, param)
    log.info(TAG, "reg", error, error_code, param)
    if not error and param > 0 then
        log.info(TAG, "reg ok and done")
    end
end

local function cb_tx(error, error_code, param)
    log.info(TAG, "tx", error, error_code, param)
end

local function cb_rx(data)
    log.info(TAG, "rx", data)
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

sys.subscribe("CTIOT_TX", cb_tx)
sys.subscribe("CTIOT_RX", cb_rx)
sys.subscribe("CTIOT_REG", cb_reg)
sys.subscribe("CTIOT_DEREG", cb_dereg)
sys.subscribe("CTIOT_WAKEUP", cb_wakeup)
sys.subscribe("CTIOT_OTHER", cb_other)
sys.subscribe("CTIOT_FOTA", cb_fota)

local function task()
    
    --设置自定义EP，如果不设置，则使用IMEI
    local ep="000000000000000"
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
    --启动连接
    pm.request(pm.IDLE)
    ctiot.connect()
end
ctiot.init()
sys.taskInit(task)
sys.run()