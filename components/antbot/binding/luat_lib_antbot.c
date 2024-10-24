/*
@module antbot
@summary 蚂蚁链
@catalog 扩展API
@version 1.0
@date    2022.12.18
@demo antbot
@tag LUAT_USE_ANTBOT
@usage
-- Copyright (C) 2015-2023 Ant Group Holding Limited
-- 本模块由蚂蚁链提供实现并开放给用户使用
-- 具体用法请查阅demo,并联系蚂蚁链获取技术支持
 */
#include "luat_base.h"
#include "rotable2.h"
#include "luat_zbuff.h"
#include "luat_lib_antbot.h"
#include "bot_api.h"

#define LUAT_LOG_TAG "antbot"
#include "luat_log.h"

#define BOT_DATA_PAC_OUT_MAX_SIZE   1024

bot_msg_type_e g_bot_status = BOT_MSG_UNAVAILABLE;

static const char *bot_app_sta_notify_str[] = {
    "BOT_MSG_UNAVAILABLE",
    "BOT_MSG_INIT_FAILED",
    "BOT_MSG_INIT_SUCESS",
    "BOT_MSG_REG_FAILED",
    "BOT_MSG_REG_SUCESS",
    "BOT_MSG_PUB_FAILED",
    "BOT_MSG_PUB_SUCESS",
    "BOT_MSG_DATA_VERIFY_FAILED"
};

static void bot_msg_notify_cb(bot_msg_type_e notify_type, void *args)
{
    if (g_bot_status != notify_type) {
        LLOGI("----------------------------------------------------------------------------------");
        LLOGI("state change: %s ---> %s", bot_app_sta_notify_str[g_bot_status], bot_app_sta_notify_str[notify_type]);
        LLOGI("----------------------------------------------------------------------------------");
        g_bot_status = notify_type;
    }
}

/*
初始化
@api antbot.init()
@return int 0:成功 其他值为失败
@usage

-- 初始化蚂蚁链的底层适配
antbot.init()
*/
static int luat_bot_init(lua_State *L)
{
    bot_msg_notify_callback_register(bot_msg_notify_cb, NULL);
    int ret = bot_init();
    lua_pushinteger(L, ret);
    return 1;
}

/*
获取客户端状态
@api antbot.app_sta_get()
@return int 状态码
*/
static int luat_bot_app_sta_get(lua_State *L)
{
    LLOGD("bot_app_sta_get lua: %d", g_bot_status);
    lua_pushinteger(L, g_bot_status);
    return 1;
}

/*
获取SDK版本号
@api antbot.version_get()
@return string 版本号,如果获取失败返回nil
*/
static int luat_bot_version_get(lua_State *L)
{
    const char *version = bot_version_get();

    if (!version)
        return 0;
    else
        lua_pushstring(L, version);

    //LLOGD("version: %s", version);
    return 1;
}

/*
asset资源注册
@api antbot.asset_register(asset_id, asset_type, asset_dataver)
@string asset_id 资源ID
@string asset_type 资源类型
@string asset_dataver 资源数据版本
@return int 0:成功 其他值为失败
*/
static int luat_bot_asset_register(lua_State *L)
{
    int ret = -1;
    size_t size = 0;

    int num_args = lua_gettop(L);
    if (num_args != 3) {
        goto exit;
    }

    if (!lua_isstring(L, 1) || !lua_isstring(L, 2) || !lua_isstring(L, 3)) {
        LLOGE("asset_register parameters are invalid type, shoule be string.");
        goto exit;
    }

    const char *asset_id = luaL_checklstring(L, 1, &size);
    const char *asset_type = luaL_checklstring(L, 2, &size);
    const char *asset_dataver = luaL_checklstring(L, 3, &size);
    ret = bot_asset_register(asset_id, asset_type, asset_dataver);

exit:
    lua_pushinteger(L, ret);
    return 1;
}

/*
asset资源发布
@api antbot.asset_data_publish(data)
@string data 资源数据
@return int 0:成功 其他值为失败
*/
static int luat_bot_data_publish(lua_State *L)
{
    int ret = -1;
    uint8_t *data;
    size_t data_len;
    int len;

    data = luaL_checklstring(L, 1, &data_len);
    ret = bot_data_publish(data, data_len);

exit:
    lua_pushinteger(L, ret);
    return 1;
}

/*
获取设备状态
@api antbot.device_status_get()
@return int 设备状态
*/
static int luat_bot_device_status_get(lua_State *L)
{
    lua_pushinteger(L, bot_device_status_get());
    return 1;
}

/*
获取assset状态
@api antbot.asset_status_get(asset_id)
@string asset_id 资源ID
@return int 资源状态
*/
static luat_bot_asset_status_get(lua_State *L)
{
    int ret = -1;
    if (!lua_isstring(L, 1)) {
        LLOGE("asset_status_get parameter is invalid type, shoule be string.");
        goto exit;
    }

    size_t size = 0;
    const char *asset_id = luaL_checklstring(L, 1, &size);
    ret = bot_asset_status_get(asset_id);

exit:
    lua_pushinteger(L, ret);
    return 1;
}

/*
切换channel
@api antbot.channel_switch(cmd)
@int 0 - 关闭, 1 - 开启
@return int 0:成功 其他值为失败
*/
static int luat_bot_channel_switch(lua_State *L)
{
    int ret = -1;
    if (!lua_isinteger(L, 1)) {
        LLOGE("channel_switch parameter is invalid type, shoule be int.");
        goto exit;
    }

    size_t size = 0;
    int cmd = luaL_checkinteger(L, 1);
    ret = bot_channel_switch(cmd);

exit:
    lua_pushinteger(L, ret);
    return 1;
}

/*
配置设备
@api antbot.config_set(config)
@string config 配置内容
@return int 0:成功 其他值为失败
*/
static int luat_bot_config_set(lua_State *L)
{
    int ret = -1;
    if (!lua_isstring(L, 1)) {
        LLOGE("config_set parameter is invalid type, shoule be string.");
        goto exit;
    }

    size_t size = 0;
    const char *config = luaL_checklstring(L, 1, &size);
    ret = bot_config_set(config);

exit:
    lua_pushinteger(L, ret);
    return 1;
}

/*
获取设备配置
@api antbot.config_get()
@return string 配置内容
*/
static int luat_bot_config_get(lua_State *L)
{
    int ret = -1;

    if (!lua_isinteger(L, 1)) {
        LLOGE("config_get parameter are invalid type!");
        goto exit;
    }

    int len = luaL_checkinteger(L, 1);
    if (len < BOT_CONFIG_BUF_MIN_LEN) {
        LLOGE("config_get len must be greater than BOT_CONFIG_BUF_MIN_LEN");
        goto exit;
    }

    char *config = luat_heap_malloc(len);
    if (!config) {
        LLOGE("config_get out of memory");
        goto exit;
    }

    ret = bot_config_get(config, len);
    lua_pushinteger(L, ret);
    lua_pushlstring(L, config, len);
    luat_heap_free(config);
    return 2;

exit:
    lua_pushinteger(L, ret);
    return 1;
}

static int luat_bot_data_pac(lua_State *L)
{
    int ret = -1;
    int num_args = lua_gettop(L);
    if (num_args != 2) {
        goto exit;
    }

    if (!lua_isinteger(L, 1) || !lua_isstring(L, 2)) {
        LLOGE("data_pac parameters are invalid type!");
        goto exit;
    }

    int format = luaL_checkinteger(L, 1);
    size_t data_len;
    uint8_t *data_in = luaL_checklstring(L, 2, &data_len);

    int outlen = BOT_DATA_PAC_OUT_MAX_SIZE;
    uint8_t *data_out = luat_heap_malloc(outlen); // TODO 改成 lua_Buff
    if (!data_out) {
        LLOGE("data_pack out of memory");
        goto exit;
    }

    ret = bot_data_pac(format, data_in, data_len, data_out, &outlen);
    lua_pushinteger(L, ret);
    lua_pushlstring(L, (const char *)data_out, outlen);
    lua_pushinteger(L, outlen);
    luat_heap_free(data_out);
    return 3;

exit:
    lua_pushinteger(L, ret);
    return 1;
}

static const rotable_Reg_t reg_antbot[] = {
    { "version_get",        ROREG_FUNC(luat_bot_version_get)},
    { "init",               ROREG_FUNC(luat_bot_init)},
    { "app_sta_get",        ROREG_FUNC(luat_bot_app_sta_get)},
    { "asset_register",     ROREG_FUNC(luat_bot_asset_register)},
    { "data_publish",       ROREG_FUNC(luat_bot_data_publish)},
    { "device_status_get",  ROREG_FUNC(luat_bot_device_status_get)},
    { "asset_status_get",   ROREG_FUNC(luat_bot_asset_status_get)},
    { "channel_switch",     ROREG_FUNC(luat_bot_channel_switch)},
    { "config_set",         ROREG_FUNC(luat_bot_config_set)},
    { "config_get",         ROREG_FUNC(luat_bot_config_get)},
    { "data_pac",           ROREG_FUNC(luat_bot_data_pac)},
    { NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_antbot(lua_State *L)
{
    luat_newlib2(L, reg_antbot);
    return 1;
}
