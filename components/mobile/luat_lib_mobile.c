
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
获取IMEI
@api mobile.imei(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return string 当前的IMEI值,若失败返回nil
 */
static int l_mobile_imei(lua_State* L) {
    char buff[24] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    ret = luat_mobile_get_imei(index, buff, 24);
    // if (lua_isstring(L, 2)) {
    //     const char* wbuff = luaL_checklstring(L, 2, &wlen);
    //     if (wlen >= 15) {
    //         ret = luat_mobile_set_imei(index, wbuff, wlen);
    //         LLOGI("IMEI write %d %s ret %d", index, wbuff, ret);
    //     }
    // }
    if (ret > 0)
        lua_pushlstring(L, buff, ret);
    else
        lua_pushnil(L);
    return 1;
}

/**
获取IMSI
@api mobile.imsi(index)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@return string 当前的IMSI值,若失败返回nil
 */
static int l_mobile_imsi(lua_State* L) {
    char buff[24] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    ret = luat_mobile_get_imsi(index, buff, 24);
    // if (lua_isstring(L, 2)) {
    //     const char* wbuff = luaL_checklstring(L, 2, &wlen);
    //     if (wlen >= 1) {
    //         ret = luat_mobile_set_imsi(index, wbuff, wlen);
    //         LLOGI("IMSI write %d %s ret %d", index, wbuff, ret);
    //     }
    // }
    if (ret > 0)
        lua_pushlstring(L, buff, ret);
    else
        lua_pushnil(L);
    return 1;
}



/**
获取SN
@api mobile.sn()
@return string 当前的SN值,若失败返回nil
 */
static int l_mobile_sn(lua_State* L) {
    char buff[24] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    ret = luat_mobile_get_sn(buff, 24);
    // if (lua_isstring(L, 1)) {
    //     const char* wbuff = luaL_checklstring(L, 1, &wlen);
    //     if (wlen >= 1) {
    //         ret = luat_mobile_set_sn(wbuff, wlen);
    //         LLOGI("SN write %d %s ret %d", index, wbuff, ret);
    //     }
    // }
    if (ret > 0)
        lua_pushlstring(L, buff, ret);
    else
        lua_pushnil(L);
    return 1;
}


/**
获取MUID
@api mobile.muid()
@return string 当前的MUID值,若失败返回nil
 */
static int l_mobile_muid(lua_State* L) {
    char buff[24] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    ret = luat_mobile_get_muid(buff, 24);
    if (lua_isstring(L, 1)) {
        // const char* wbuff = luaL_checklstring(L, 1, &wlen);
        // if (wlen >= 15) {
        //     ret = luat_mobile_set_muid(index, wbuff, wlen);
        //     LLOGI("SN write %d %s ret %d", index, wbuff, ret);
        // }
    }
    if (ret > 0)
        lua_pushlstring(L, buff, ret);
    else
        lua_pushnil(L);
    return 1;
}


/**
获取或设置ICCID
@api mobile.iccid(id)
@int SIM卡的编号, 例如0, 1, 默认0
@return string ICCID值,若失败返回nil
 */
static int l_mobile_iccid(lua_State* L) {
    char buff[24] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    ret = luat_mobile_get_iccid(index, buff, 24);
    if (ret > 0)
        lua_pushlstring(L, buff, ret);
    else
        lua_pushnil(L);
    return 1;
}


/**
获取当前SIM卡槽,或者切换卡槽
@api mobile.simid(id)
@int SIM卡的编号, 例如0, 1. 可选
@return int 当前sim卡槽编号,若失败返回-1
 */
static int l_mobile_simid(lua_State* L) {
    // char buff[24] = {0};
    int ret = 0;
    int id = 0;
    if (lua_isinteger(L, 1)) {
        ret = luat_mobile_set_sim_id(lua_tointeger(L, 1));
        LLOGI("sim set to %d , ret %d", id, ret);
    }
    ret = luat_mobile_get_sim_id(&id);
    if (ret == 0) {
        lua_pushinteger(L, id);
    }
    else {
        lua_pushinteger(L, -1);
    }
    return 1;
}

/**
获取或设置APN
@api mobile.apn(index, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@int cid, 默认0
@string 新的APN. 不填就是获取APN, 填了就是设置APN, 是否支持设置取决于底层实现.
@return string 当前的APN值,若失败返回nil
 */
static int l_mobile_apn(lua_State* L) {
    char buff[36] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    int cid = luaL_optinteger(L, 2, 0);
    ret = luat_mobile_get_apn(index, cid, buff, 36);
    // if (lua_isstring(L, 3)) {
    //     const char* wbuff = luaL_checklstring(L, 3, &wlen);
    //     if (wlen >= 15) {
    //         ret = luat_mobile_set_apn(index, wbuff, wlen);
    //         LLOGI("APN write %d %s ret %d", index, wbuff, ret);
    //     }
    // }
    if (ret > 0)
        lua_pushlstring(L, buff, ret);
    else
        lua_pushnil(L);
    return 1;
}

/**
获取csq
@return int 当前CSQ值, 若失败返回0
 */
static int l_mobile_csq(lua_State* L) {
    // luat_mobile_signal_strength_info_t info = {0};
    uint8_t csq = 0;
    if (luat_mobile_get_signal_strength(&csq) == 0) {
        lua_pushinteger(L, (int)csq);
    }
    else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/**
获取rssi
@api mobile.rssi()
@return int 当前rssi值,若失败返回0
 */
static int l_mobile_rssi(lua_State* L) {
    luat_mobile_signal_strength_info_t info = {0};
    if (luat_mobile_get_signal_strength_info(&info) == 0) {
        lua_pushinteger(L, info.lte_signal_strength.rssi);
    }
    else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/**
获取rsrp
@api mobile.rsrp()
@return int 当前rsrp值,若失败返回0
 */
static int l_mobile_rsrp(lua_State* L) {
    luat_mobile_signal_strength_info_t info = {0};
    if (luat_mobile_get_signal_strength_info(&info) == 0) {
        lua_pushinteger(L, info.lte_signal_strength.rsrp);
    }
    else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/**
获取rsrq
@api mobile.rsrq()
@return int 当前rsrq值,若失败返回0
 */
static int l_mobile_rsrq(lua_State* L) {
    luat_mobile_signal_strength_info_t info = {0};
    if (luat_mobile_get_signal_strength_info(&info) == 0) {
        lua_pushinteger(L, info.lte_signal_strength.rsrq);
    }
    else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/**
获取snr
@api mobile.snr()
@return int 当前snq值,若失败返回0
 */
static int l_mobile_snr(lua_State* L) {
    luat_mobile_signal_strength_info_t info = {0};
    if (luat_mobile_get_signal_strength_info(&info) == 0) {
        lua_pushinteger(L, info.lte_signal_strength.snr);
    }
    else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/**
进出飞行模式
@api mobile.flymode(index, enable)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@bool 是否设置为飞行模式,true为设置, false为退出,可选
@return bool 原飞行模式的状态
 */
static int l_mobile_flymode(lua_State* L) {
    int index = luaL_optinteger(L, 1, 0);
    int flymode = luat_mobile_get_flymode(index);
    if (lua_isboolean(L, 2)) {
        luat_mobile_set_flymode(index, lua_toboolean(L, 2));
    }
    lua_pushboolean(L, flymode == 0 ? 0 : 1);
    return 1;
}

/**
获取网络状态
@api mobile.status()
@return int 当前网络状态
 */
static int l_mobile_status(lua_State* L) {
    int LUAT_MOBILE_REGISTER_STATUS_E = luat_mobile_get_register_status();
    lua_pushinteger(L, LUAT_MOBILE_REGISTER_STATUS_E);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mobile[] = {
    {"status",      ROREG_FUNC(l_mobile_status)},
    {"imei",        ROREG_FUNC(l_mobile_imei)},
    {"imsi",        ROREG_FUNC(l_mobile_imsi)},
    {"sn",          ROREG_FUNC(l_mobile_sn)},
    {"iccid",       ROREG_FUNC(l_mobile_iccid)},
    {"muid",        ROREG_FUNC(l_mobile_muid)},
    {"apn",         ROREG_FUNC(l_mobile_apn)},
    {"csq",         ROREG_FUNC(l_mobile_csq)},
    {"rssi",        ROREG_FUNC(l_mobile_rssi)},
    {"rsrq",        ROREG_FUNC(l_mobile_rsrq)},
    {"rsrp",        ROREG_FUNC(l_mobile_rsrp)},
    {"snr",         ROREG_FUNC(l_mobile_snr)},
    {"flymode",     ROREG_FUNC(l_mobile_flymode)},
    {"simid",       ROREG_FUNC(l_mobile_simid)},

    // const UNREGISTER 未注册
    {"UNREGISTER",                  ROREG_INT(LUAT_MOBILE_STATUS_UNREGISTER)},
    // const REGISTERED 已注册
    {"REGISTERED",                  ROREG_INT(LUAT_MOBILE_STATUS_REGISTERED)},
    // const DENIED 注册被拒绝
    {"DENIED",                      ROREG_INT(LUAT_MOBILE_STATUS_DENIED)},
    // const UNKNOW 未知
    {"UNKNOW",                      ROREG_INT(LUAT_MOBILE_STATUS_UNKNOW)},
    // const REGISTERED_ROAMING 已注册,漫游
    {"REGISTERED_ROAMING",          ROREG_INT(LUAT_MOBILE_STATUS_REGISTERED_ROAMING)},
    // const SMS_ONLY_REGISTERED 已注册,仅SMS
    {"SMS_ONLY_REGISTERED",         ROREG_INT(LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED)},
    // const SMS_ONLY_REGISTERED_ROAMING 已注册,漫游,仅SMS
    {"SMS_ONLY_REGISTERED_ROAMING", ROREG_INT(LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED_ROAMING)},
    // const EMERGENCY_REGISTERED 已注册,紧急服务
    {"EMERGENCY_REGISTERED",        ROREG_INT(LUAT_MOBILE_STATUS_EMERGENCY_REGISTERED)},
    // const CSFB_NOT_PREFERRED_REGISTERED 已注册,非主要服务
    {"CSFB_NOT_PREFERRED_REGISTERED",  ROREG_INT(LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED)},
    // const CSFB_NOT_PREFERRED_REGISTERED_ROAMING 已注册,非主要服务,漫游
    {"CSFB_NOT_PREFERRED_REGISTERED_ROAMING",  ROREG_INT(LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED_ROAMING)},
    // const REGISTERED 已注册

    {NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_mobile( lua_State *L ) {
    luat_newlib2(L, reg_mobile);
    return 1;
}
