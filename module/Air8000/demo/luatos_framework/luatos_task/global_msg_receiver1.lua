


local function init_subscribe_cbfunc(tag, count)
    log.info("init_subscribe_cbfunc", tag, count)
end

local function delay_subscribe_cbfunc(tag, count)
    log.info("delay_subscribe_cbfunc", tag, count)
end


sys.subscribe("SEND_DATA_REQ", init_subscribe_cbfunc)
sys.timerStart(sys.subscribe, 5000, "SEND_DATA_REQ", delay_subscribe_cbfunc)


sys.timerStart(sys.unsubscribe, 10000, "SEND_DATA_REQ", init_subscribe_cbfunc)
sys.timerStart(sys.unsubscribe, 10000, "SEND_DATA_REQ", delay_subscribe_cbfunc)