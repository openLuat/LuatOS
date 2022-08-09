
/*
@module  mobile
@summary 蜂窝网络
@version 1.0
@date    2022.8.9
*/
#include "luat_base.h"
#include "luat_malloc.h"

#include "luat_mobile.h"

#define LUAT_LOG_TAG "mobile"
#include "luat_log.h"

/**
获取或设置IMEI
@api mobile.imei(index, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@string 新的IMEI. 不填就是获取IMEI, 填了就是设置IMEI, 是否支持设置取决于底层实现.
@return string 当前的IMEI值
 */
static int l_mobile_imei(lua_State* L) {
    char buff[24] = {0};
    size_t len = 0;
    size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    luat_mobile_get_imei(index, buff, &len);
    if (lua_isstring(L, 2)) {
        const char* wbuff = luaL_checklstring(L, 2, &wlen);
        if (wlen >= 15) {
            ret = luat_mobile_set_imei(index, wbuff, wlen);
            LLOGI("IMEI write %d %s ret %d", index, wbuff, ret);
        }
    }
    if (len > 0)
        lua_pushlstring(L, buff, len);
    else
        lua_pushnil(L);
    return 1;
}

/**
获取或设置IMSI
@api mobile.imsi(index, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@string 新的IMSI. 不填就是获取IMSI, 填了就是设置IMSI, 是否支持设置取决于底层实现.
@return string 当前的IMSI值
 */
static int l_mobile_imsi(lua_State* L) {
    char buff[24] = {0};
    size_t len = 0;
    size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    luat_mobile_get_imsi(index, buff, &len);
    if (lua_isstring(L, 2)) {
        const char* wbuff = luaL_checklstring(L, 2, &wlen);
        if (wlen >= 15) {
            ret = luat_mobile_set_imsi(index, wbuff, wlen);
            LLOGI("IMSI write %d %s ret %d", index, wbuff, ret);
        }
    }
    if (len > 0)
        lua_pushlstring(L, buff, len);
    else
        lua_pushnil(L);
    return 1;
}


/**
获取或设置APN
@api mobile.apn(index, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@string 新的APN. 不填就是获取APN, 填了就是设置IMSI, 是否支持设置取决于底层实现.
@return string 当前的APN值
 */
static int l_mobile_apn(lua_State* L) {
    char buff[24] = {0};
    size_t len = 0;
    size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    luat_mobile_get_apn(index, buff, &len);
    if (lua_isstring(L, 2)) {
        const char* wbuff = luaL_checklstring(L, 2, &wlen);
        if (wlen >= 15) {
            ret = luat_mobile_set_apn(index, wbuff, wlen);
            LLOGI("APN write %d %s ret %d", index, wbuff, ret);
        }
    }
    if (len > 0)
        lua_pushlstring(L, buff, len);
    else
        lua_pushnil(L);
    return 1;
}

/**
获取csq
@api mobile.csq(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return int 当前CSQ值
 */
static int l_mobile_csq(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int ret = luat_mobile_get_csq(index);
    lua_pushinteger(L, ret);
    return 1;
}

/**
获取rssi
@api mobile.rssi(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return int 当前rssi值
 */
static int l_mobile_rssi(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int ret = luat_mobile_get_rssi(index);
    lua_pushinteger(L, ret);
    return 1;
}

/**
获取rsrp
@api mobile.rsrp(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return int 当前rsrp值
 */
static int l_mobile_rsrp(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int ret = luat_mobile_get_rsrp(index);
    lua_pushinteger(L, ret);
    return 1;
}

/**
获取rsrq
@api mobile.rsrq(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return int 当前rsrq值
 */
static int l_mobile_rsrq(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int ret = luat_mobile_get_rsrp(index);
    lua_pushinteger(L, ret);
    return 1;
}

/**
获取snq
@api mobile.snq(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return int 当前snq值
 */
static int l_mobile_snq(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int ret = luat_mobile_get_snq(index);
    lua_pushinteger(L, ret);
    return 1;
}

/**
进出飞行模式
@api mobile.flymode(index, enable)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@bool 是否设置为飞行模式,true为设置, false为退出
@return bool 原飞行模式的状态
 */
static int l_mobile_flymode(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int flymode = luat_mobile_get_flymode(index);
    int mode = lua_toboolean(L, 2);
    LLOGW("set flymode %s", mode == 0 ? "exit" : "entry");
    luat_mobile_set_flymode(index, mode);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mobile[] = {
    {"imei", ROREG_FUNC(l_mobile_imei)},
    {"imsi", ROREG_FUNC(l_mobile_imsi)},
    {"apn", ROREG_FUNC(l_mobile_apn)},
    {"csq", ROREG_FUNC(l_mobile_csq)},
    {"rssi", ROREG_FUNC(l_mobile_rssi)},
    {"rsrq", ROREG_FUNC(l_mobile_rsrq)},
    {"rsrp", ROREG_FUNC(l_mobile_rsrp)},
    {"snq", ROREG_FUNC(l_mobile_snq)},
    {"flymode", ROREG_FUNC(l_mobile_flymode)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_mobile( lua_State *L ) {
    luat_newlib2(L, reg_mobile);
    return 1;
}
