PROJECT = "ctiot"
VERSION = "1.0.0"
local TAG="ctiot"
-- sys库是标配
_G.sys = require("sys")

local function cb_reg(error, error_code, param)
    log.info(TAG, "reg", error, error_code, param)
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

local funtion task()
    local ep = ctiot.ep()
    log.info(TAG, "old ep", ep)
    ctiot.ep("12345678")
end
ctiot.init()
sys.taskInit(task)
sys.run()