-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "antbot_lua"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

_G.sys = require("sys")

-- 引入 ebike 应用示例模块
local bot_app_ebike = require("bot_app_ebike")

-- antbot.app_sta_get 固定返回值类型
local bot_msg_type = {
    BOT_MSG_UNAVAILABLE = 0,
    BOT_MSG_INIT_FAILED = 1,
    BOT_MSG_INIT_SUCESS = 2,
    BOT_MSG_REG_FAILED = 3,
    BOT_MSG_REG_SUCESS = 4,
    BOT_MSG_PUB_FAILED = 5,
    BOT_MSG_PUB_SUCESS = 6,
    BOT_MSG_DATA_VERIFY_FAILED = 7
}
-- 用户资产数据上报
function bot_app_asset_data_report()
    local bot_user_data = bot_app_ebike.user_asset_data_get()
    if #bot_user_data > BOT_USER_DATA_STRING_MAX_SIZE then
        log.error("bot_user_data length out of range")
        return
    end

    log.debug("bot start publishing bot data")

    local ret = antbot.data_publish(bot_user_data, #bot_user_data)
    if ret < 0 then
        log.error("It was fail to publish bot data, ret: -0x", string.format("%x", -ret))
        return
    end

    log.info("successfully published bot data, cnt:", ret)
end

sys.taskInit(function()
    sys.wait(3000)

    local version = antbot.version_get();
    log.debug("antbot.version_get: ", version)

    log.debug("antbot initialization")
    local ret = antbot.init()
    if ret ~= 0 then
        log.error("antbot initialization failed.")
        return
    end

    log.debug("antbot config_set")
    ret = antbot.config_set(BOT_CONFIG_TOKEN)
    if ret ~= 0 then
        log.error("antbot config_set failed.")
        return
    end

    local asset_config = bot_app_ebike.user_asset_config_get()
    local reg_retry_count = 0;
    local bot_sta = bot_msg_type.BOT_MSG_UNAVAILABLE
    local bot_msg = bot_msg_type.BOT_MSG_UNAVAILABLE
    local count = 1
    while 1 do
        log.debug("antbot app_sta_get")
        if bot_sta ~= antbot.app_sta_get() then
            bot_sta = antbot.app_sta_get()
            bot_msg = bot_sta
        end

        log.info("luatos", "hi", count, os.date())
        log.info("lua", rtos.meminfo())         -- lua内存
        log.info("sys", rtos.meminfo("sys"))    -- sys内存
        count = count + 1

        if bot_msg == bot_msg_type.BOT_MSG_INIT_SUCESS then
            log.debug("bot init success")
            if antbot.asset_status_get(asset_config.id) == 1 then
                log.info("asset already register")
                bot_msg = bot_msg_type.BOT_MSG_REG_SUCESS
            else
                reg_retry_count = 0
                antbot.asset_register(asset_config.id, asset_config.type, asset_config.adv)
                bot_msg = bot_msg_type.BOT_MSG_UNAVAILABLE;
                -- 注册间隔需要大于2s
                -- sys.wait(2 * 1000)
            end
        elseif bot_msg == bot_msg_type.BOT_MSG_REG_FAILED then
            log.debug("bot register fail")
            sys.wait(10 * 1000)
            if reg_retry_count < BOT_REG_RETRY_COUNT_MAX then
                reg_retry_count = reg_retry_count + 1
                antbot.asset_register(asset_config.id, asset_config.type, asset_config.adv)
                log.info("msg notify BOT_MSG_REG_FAILED retry_count: ", reg_retry_count)
            end
        elseif bot_msg == bot_msg_type.BOT_MSG_REG_SUCESS or
            bot_msg == bot_msg_type.BOT_MSG_PUB_SUCESS or
            bot_msg == bot_msg_type.BOT_MSG_PUB_FAILED then
            log.debug("bot register success or pub success or pub failed")

            bot_app_asset_data_report();

            sys.wait(20 * 1000);
        else
            sys.wait(1 * 1000)
        end
    end
    
end)

sys.run()
