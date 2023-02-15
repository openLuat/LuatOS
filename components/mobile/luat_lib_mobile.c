
/*
@module  mobile
@summary 蜂窝网络
@version 1.0
@date    2022.8.9
@demo    mobile
@tag LUAT_USE_MOBILE
@usage
-- 简单演示

log.info("imei", mobile.imei())
log.info("imsi", mobile.imsi())
local sn = mobile.sn()
if sn then
    log.info("sn",   sn:toHex())
end
log.info("muid", mobile.muid())
log.info("iccid", mobile.iccid())
log.info("csq", mobile.csq())
log.info("rssi", mobile.rssi())
log.info("rsrq", mobile.rsrq())
log.info("rsrp", mobile.rsrp())
log.info("snr", mobile.snr())
log.info("simid", mobile.simid())
*/
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"

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
    if (ret > 0) {
        buff[23] = 0x00; // 确保能结束
        lua_pushlstring(L, buff, strlen(buff));
    }
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
    if (ret > 0){
        buff[23] = 0x00; // 确保能结束
        lua_pushlstring(L, buff, strlen(buff));
    }
    else
        lua_pushnil(L);
    return 1;
}



/**
获取SN
@api mobile.sn()
@return string 当前的SN值,若失败返回nil. 注意, SN可能包含不可见字符
 */
static int l_mobile_sn(lua_State* L) {
    char buff[32] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    ret = luat_mobile_get_sn(buff, 32);
    // if (lua_isstring(L, 1)) {
    //     const char* wbuff = luaL_checklstring(L, 1, &wlen);
    //     if (wlen >= 1) {
    //         ret = luat_mobile_set_sn(wbuff, wlen);
    //         LLOGI("SN write %d %s ret %d", index, wbuff, ret);
    //     }
    // }
    if (ret > 0) {        
        //buff[63] = 0x00; // 确保能结束
        lua_pushlstring(L, buff, ret);
    }
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
    char buff[33] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    ret = luat_mobile_get_muid(buff, 32);
    if (lua_isstring(L, 1)) {
        // const char* wbuff = luaL_checklstring(L, 1, &wlen);
        // if (wlen >= 15) {
        //     ret = luat_mobile_set_muid(index, wbuff, wlen);
        //     LLOGI("SN write %d %s ret %d", index, wbuff, ret);
        // }
    }
    if (ret > 0)  {        
        lua_pushlstring(L, buff, strlen(buff));
    }
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
    if (ret > 0) {        
        buff[23] = 0x00; // 确保能结束
        lua_pushlstring(L, buff, strlen(buff));
    }
    else
        lua_pushnil(L);
    return 1;
}

/**
获取手机卡号，注意，只有写入了手机号才能读出，因此有可能读出来是空的
@api mobile.number(id)
@int SIM卡的编号, 例如0, 1, 默认0
@return string number值,若失败返回nil
 */
static int l_mobile_number(lua_State* L) {
    char buff[24] = {0};
    // size_t len = 0;
    // size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    ret = luat_mobile_get_sim_number(index, buff, 24);
    if (ret > 0) {
        buff[23] = 0x00; // 确保能结束
        lua_pushlstring(L, buff, strlen(buff));
    }
    else
        lua_pushnil(L);
    return 1;
}

/**
获取当前SIM卡槽,或者切换卡槽
@api mobile.simid(id)
@int SIM卡的编号, 例如0, 1, 如果支持双卡，比如EC618，可以填2来自适应，但是会占用掉4个IO。如果不填就直接读取当前卡槽
@boolean 是否优先用SIM0，只有SIM卡编号写2自适应才有用！！！。true优先用SIM0，false则优先用上一次探测到的，默认是false，必须在开机就配置，否则就无效了
@return int 当前sim卡槽编号,若失败返回-1
 */
static int l_mobile_simid(lua_State* L) {
    // char buff[24] = {0};
    int ret = 0;
    int id = 0;
    if (lua_isinteger(L, 1)) {
        ret = luat_mobile_set_sim_id(lua_tointeger(L, 1));
        LLOGI("sim set to %d , ret %d", lua_tointeger(L, 1), ret);
    }
    if (LUA_TBOOLEAN == lua_type(L, 2)) {
    	if (lua_toboolean(L, 2)) {
    		luat_mobile_set_sim_detect_sim0_fisrt();
    	}
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
设置RRC自动释放时间间隔
@api mobile.rtime(time)
@int RRC自动释放时间，等同于Air724的AT+RTIME，单位秒，写0或者不写则是停用，不要超过20秒，没有意义
@return nil 无返回值
 */
static int l_mobile_set_rrc_auto_release_time(lua_State* L) {
	luat_mobile_set_rrc_auto_release_time(luaL_optinteger(L, 1, 0));
    return 0;
}

/**
设置一些辅助周期性功能，目前支持SIM卡暂时脱离后恢复和周期性获取小区信息
@api mobile.setAuto(check_sim_period, get_cell_period, search_cell_time)
@int SIM卡自动恢复时间，单位毫秒，建议5000~10000，和飞行模式/SIM卡切换冲突，不能再同一时间使用，必须错开执行。写0或者不写则是关闭功能
@int 周期性获取小区信息的时间间隔，单位毫秒。获取小区信息会增加部分功耗。写0或者不写则是关闭功能
@int 每次搜索小区时最大搜索时间，单位秒。不要超过8秒
@return nil 无返回值
 */
static int l_mobile_set_auto_work(lua_State* L) {
	luat_mobile_set_period_work(luaL_optinteger(L, 2, 0), luaL_optinteger(L, 1, 0), luaL_optinteger(L, 3, 0));
    return 0;
}

/**
获取或设置APN
@api mobile.apn(index, cid, newvalue)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@int cid, 默认0
@string 新的APN. 不填就是获取APN, 填了就是设置APN, 是否支持设置取决于底层实现.
@return string 获取到的默认APN值,失败返回nil
 */
static int l_mobile_apn(lua_State* L) {
    char buff[64] = {0};
    size_t len = 0;
    size_t wlen = 0;
    int ret = 0;
    int index = luaL_optinteger(L, 1, 0);
    int cid = luaL_optinteger(L, 2, 0);
    ret = luat_mobile_get_apn(index, cid, buff, sizeof(buff) - 1);
	if (lua_isstring(L, 3)) {
		const char* wbuff = luaL_checklstring(L, 3, &wlen);
		if (wlen) {
			luat_mobile_user_apn_auto_active(index, cid, 3, 0xff, wbuff, wlen, NULL, 0, NULL, 0);
			LLOGI("APN write %d %s ret %d", index, wbuff, ret);
		}
		else
		{
			luat_mobile_user_apn_auto_active(index, cid, 3, 0xff, NULL, 0, NULL, 0, NULL, 0);
		}
	}
    if (ret > 0) {
        lua_pushlstring(L, buff, strlen(buff));
    }
    else
        lua_pushnil(L);
    return 1;
}

/**
是否默认开启IPV6功能，必须在LTE网络连接前就设置好
@api mobile.ipv6(onff)
@boolean 开关 true开启 false 关闭
@return boolean true 当前是开启的，false 当前是关闭的
 */
static int l_mobile_ipv6(lua_State* L) {
    // char buff[24] = {0};
	uint8_t onoff;
    if (LUA_TBOOLEAN == lua_type(L, 1)) {
    	luat_mobile_set_default_pdn_ipv6(lua_toboolean(L, 1));
    }
    lua_pushboolean(L, luat_mobile_get_default_pdn_ipv6());
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
@return int 当前网络状态,0:网络未注册;1:网络已注册;2:网络注册被拒绝，或者正在搜网中
 */
static int l_mobile_status(lua_State* L) {
    int LUAT_MOBILE_REGISTER_STATUS_E = luat_mobile_get_register_status();
    lua_pushinteger(L, LUAT_MOBILE_REGISTER_STATUS_E);
    return 1;
}

static inline uint16_t u162bcd(uint16_t src) {
    uint8_t high = (src >> 8) & 0xFF;
    uint8_t low  = src & 0xFF;
    uint16_t dst = 0;
    dst += (low & 0x0F) + (low >> 4) * 10;
    dst += ((high & 0x0F) + (high >> 4) * 10) * 100;
    //LLOGD("src %04X dst %d", src, dst);
    return dst;
}

/**
获取机制信息
@api mobile.getCellInfo()
@return table 包含基站数据的数组
@usage
--示例输出
--[[
[
    {"rsrq":-10,"rssi":-55,"cid":124045360,"mnc":17,"pci":115,"earfcn":1850,"snr":15,"rsrp":-85,"mcc":1120,"tdd":0},
    {"pci":388,"rsrq":-11,"mnc":17,"earfcn":2452,"snr":5,"rsrp":-67,"mcc":1120,"cid":124045331},
    {"pci":100,"rsrq":-9,"mnc":17,"earfcn":75,"snr":17,"rsrp":-109,"mcc":1120,"cid":227096712}
]
]]

-- 订阅式
sys.subscribe("CELL_INFO_UPDATE", function()
    log.info("cell", json.encode(mobile.getCellInfo()))
end)

-- 定期轮训式
sys.taskInit(function()
    sys.wait(3000)
    while 1 do
        mobile.reqCellInfo(15)
        sys.waitUntil("CELL_INFO_UPDATE", 15000)
        log.info("cell", json.encode(mobile.getCellInfo()))
    end
end)
 */
static int l_mobile_get_cell_info(lua_State* L) {
    lua_newtable(L);
    luat_mobile_cell_info_t* info = luat_heap_malloc(sizeof(luat_mobile_cell_info_t));
    if (info == NULL) {
        LLOGE("out of memory when malloc cell_info");
        return 1;
    }
    int ret = luat_mobile_get_last_notify_cell_info(info);
    if (ret != 0) {
        LLOGI("none cell info found %d", ret);
        goto exit;
    }

    //LLOGD("cid %d neighbor %d", info->lte_service_info.cid, info->lte_neighbor_info_num);

    // 当前仅返回lte信息
    if (info->lte_info_valid == 0 && info->lte_service_info.cid == 0) {
        LLOGI("lte cell info not found");
        goto exit;
    }
    
    lua_newtable(L);
    lua_pushinteger(L, info->lte_service_info.pci);
    lua_setfield(L, -2, "pci");
    lua_pushinteger(L, info->lte_service_info.cid);
    lua_setfield(L, -2, "cid");
    lua_pushinteger(L, info->lte_service_info.earfcn);
    lua_setfield(L, -2, "earfcn");
    lua_pushinteger(L, info->lte_service_info.rsrp);
    lua_setfield(L, -2, "rsrp");
    lua_pushinteger(L, info->lte_service_info.rsrq);
    lua_setfield(L, -2, "rsrq");
    lua_pushinteger(L, info->lte_service_info.rssi);
    lua_setfield(L, -2, "rssi");
    lua_pushinteger(L, info->lte_service_info.is_tdd);
    lua_setfield(L, -2, "tdd");
    lua_pushinteger(L, info->lte_service_info.snr);
    lua_setfield(L, -2, "snr");
    lua_pushinteger(L, u162bcd(info->lte_service_info.mcc));
    lua_setfield(L, -2, "mcc");
    lua_pushinteger(L, u162bcd(info->lte_service_info.mnc));
    lua_setfield(L, -2, "mnc");
    lua_pushinteger(L, info->lte_service_info.tac);
    lua_setfield(L, -2, "tac");
    lua_pushinteger(L, info->lte_service_info.band);
    lua_setfield(L, -2, "band");
    lua_seti(L, -2, 1);

    if (info->lte_neighbor_info_num > 0) {
        for (size_t i = 0; i < info->lte_neighbor_info_num; i++)
        {
            lua_settop(L, 1);
            //LLOGD("add neighbor %d", i);
            lua_newtable(L);
            lua_pushinteger(L, info->lte_info[i].pci);
            lua_setfield(L, -2, "pci");
            lua_pushinteger(L, info->lte_info[i].cid);
            lua_setfield(L, -2, "cid");
            lua_pushinteger(L, info->lte_info[i].earfcn);
            lua_setfield(L, -2, "earfcn");
            lua_pushinteger(L, info->lte_info[i].rsrp);
            lua_setfield(L, -2, "rsrp");
            lua_pushinteger(L, info->lte_info[i].rsrq);
            lua_setfield(L, -2, "rsrq");
            lua_pushinteger(L, u162bcd(info->lte_info[i].mcc));
            lua_setfield(L, -2, "mcc");
            lua_pushinteger(L, u162bcd(info->lte_info[i].mnc));
            lua_setfield(L, -2, "mnc");
            lua_pushinteger(L, info->lte_info[i].snr);
            lua_setfield(L, -2, "snr");
            lua_pushinteger(L, info->lte_info[i].tac);
            lua_setfield(L, -2, "tac");

            lua_seti(L, -2, i + 2);
        }
    }
    lua_settop(L, 1);

    exit:
        luat_heap_free(info);
    return 1;
}
/**
发起基站信息查询,含临近小区
@api mobile.reqCellInfo(timeout)
@int 超时时长,单位秒,默认15. 最少5, 最高60
@return nil 无返回值
@usage
-- 参考 mobile.getCellInfo 函数
 */
static int l_mobile_request_cell_info(lua_State* L) {
    int timeout = luaL_optinteger(L, 1, 15);
    if (timeout > 60)
        timeout = 60;
    else if (timeout < 5)
        timeout = 5;
    luat_mobile_get_cell_info_async(timeout);
    return 0;
}

/**
重启协议栈
@api mobile.reset()
@usage mobile.reset()
 */
static int l_mobile_reset(lua_State* L) {
    luat_mobile_reset_stack();
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mobile[] = {
    {"status",      ROREG_FUNC(l_mobile_status)},
    {"imei",        ROREG_FUNC(l_mobile_imei)},
    {"imsi",        ROREG_FUNC(l_mobile_imsi)},
    {"sn",          ROREG_FUNC(l_mobile_sn)},
    {"iccid",       ROREG_FUNC(l_mobile_iccid)},
	{"number",       ROREG_FUNC(l_mobile_number)},
    {"muid",        ROREG_FUNC(l_mobile_muid)},
    {"apn",         ROREG_FUNC(l_mobile_apn)},
	{"ipv6",         ROREG_FUNC(l_mobile_ipv6)},
    {"csq",         ROREG_FUNC(l_mobile_csq)},
    {"rssi",        ROREG_FUNC(l_mobile_rssi)},
    {"rsrq",        ROREG_FUNC(l_mobile_rsrq)},
    {"rsrp",        ROREG_FUNC(l_mobile_rsrp)},
    {"snr",         ROREG_FUNC(l_mobile_snr)},
    {"flymode",     ROREG_FUNC(l_mobile_flymode)},
    {"simid",       ROREG_FUNC(l_mobile_simid)},
	{"rtime",       ROREG_FUNC(l_mobile_set_rrc_auto_release_time)},
	{"setAuto",       ROREG_FUNC(l_mobile_set_auto_work)},
    {"getCellInfo", ROREG_FUNC(l_mobile_get_cell_info)},
    {"reqCellInfo", ROREG_FUNC(l_mobile_request_cell_info)},
	{"reset",      ROREG_FUNC(l_mobile_reset)},
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

    {NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_mobile( lua_State *L ) {
    luat_newlib2(L, reg_mobile);
    return 1;
}

static int l_mobile_event_handle(lua_State* L, void* ptr) {
    LUAT_MOBILE_EVENT_E event;
    uint8_t index;
    uint8_t status;

    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    event = msg->arg1;
    index = msg->arg2 >> 8;
    status = msg->arg2 & 0xFF;

	// luat_mobile_cell_info_t cell_info;
	// luat_mobile_signal_strength_info_t signal_info;
	// uint8_t csq, i;
	// char imsi[20];
	// char iccid[24] = {0};

    if (lua_getglobal(L, "sys_pub") != LUA_TFUNCTION) {
        return 0;
    };

	switch(event)
	{
	case LUAT_MOBILE_EVENT_CFUN:
		break;
	case LUAT_MOBILE_EVENT_SIM:
/*
@sys_pub mobile
sim卡状态变化
SIM_IND
@usage
sys.subscribe("SIM_IND", function(status)
    -- status的取值有:
    -- RDY SIM卡就绪
    -- NORDY 无SIM卡
    -- SIM_PIN 需要输入PIN
    -- GET_NUMBER 获取到电话号码(不一定有值)
    log.info("sim status", status)
end)
*/
        switch (status)
        {
        case LUAT_MOBILE_SIM_READY:
            lua_pushstring(L, "SIM_IND");
            lua_pushstring(L, "RDY");
            lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_NO_SIM:
            lua_pushstring(L, "SIM_IND");
            lua_pushstring(L, "NORDY");
            lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_SIM_NEED_PIN:
            lua_pushstring(L, "SIM_IND");
            lua_pushstring(L, "SIM_PIN");
            lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_SIM_NUMBER:
            lua_pushstring(L, "SIM_IND");
            lua_pushstring(L, "GET_NUMBER");
            lua_call(L, 2, 0);
            break;
        default:
            break;
        }
		break;
	case LUAT_MOBILE_EVENT_REGISTER_STATUS:
		break;
	case LUAT_MOBILE_EVENT_CELL_INFO:
        switch (status)
        {
        case LUAT_MOBILE_CELL_INFO_UPDATE:
/*
@sys_pub mobile
基站数据已更新
CELL_INFO_UPDATE
@usage
-- 订阅式, 模块本身会周期性查询基站信息,但通常不包含临近小区
sys.subscribe("CELL_INFO_UPDATE", function()
    log.info("cell", json.encode(mobile.getCellInfo()))
end)
*/
            lua_pushstring(L, "CELL_INFO_UPDATE");
            lua_call(L, 1, 0);
		    break;
        default:
            break;
        }
		break;
	case LUAT_MOBILE_EVENT_PDP:
		break;
	case LUAT_MOBILE_EVENT_NETIF:
		switch (status)
		{
		case LUAT_MOBILE_NETIF_LINK_ON:
            LLOGD("NETIF_LINK_ON -> IP_READY");
/*
@sys_pub mobile
已联网
IP_READY
@usage
-- 联网后会发一次这个消息
-- 与wlan库不同, 本消息不带ip地址
sys.subscribe("IP_READY", function()
    log.info("mobile", "IP_READY")
end)
*/
            lua_pushstring(L, "IP_READY");
            lua_call(L, 1, 0);
			break;
        case LUAT_MOBILE_NETIF_LINK_OFF:
            LLOGD("NETIF_LINK_OFF -> IP_LOSE");
/*
@sys_pub mobile
已断网
IP_LOSE
@usage
-- 断网后会发一次这个消息
sys.subscribe("IP_LOSE", function()
    log.info("mobile", "IP_LOSE")
end)
*/
            lua_pushstring(L, "IP_LOSE");
            lua_call(L, 1, 0);
            break;
		default:
			break;
		}
		break;
	case LUAT_MOBILE_EVENT_TIME_SYNC:
/*
@sys_pub mobile
时间已经同步
NTP_UPDATE
@usage
-- 对于电信/移动的卡, 联网后,基站会下发时间,但联通卡不会,务必留意
sys.subscribe("NTP_UPDATE", function()
    log.info("mobile", "time", os.date())
end)
*/
        LLOGD("TIME_SYNC %d", status);
        lua_pushstring(L, "NTP_UPDATE");
        lua_call(L, 1, 0);
		break;
	case LUAT_MOBILE_EVENT_CSCON:
		LLOGD("CSCON %d", status);
		break;
	default:
		break;
	}
    return 0;
}

// 给luat_mobile_event_register_handler 注册用, 给lua层发消息
void luat_mobile_event_cb(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status) {
    rtos_msg_t msg = {
        .handler = l_mobile_event_handle,
        .arg1 = event,
        .arg2 = (index << 8) + status ,
        .ptr = NULL
    };
    luat_msgbus_put(&msg, 0);
}
