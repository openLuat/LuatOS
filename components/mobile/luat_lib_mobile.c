
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
#include "luat_network_adapter.h"

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
@int SIM卡的编号, 例如0, 1, 如果支持双卡，比如EC618，可以填2来自适应，但是会占用掉4个IO(gpio4/5/6/23)。如果不填就直接读取当前卡槽
@boolean 是否优先用SIM0，只有SIM卡编号写2自适应才有用！！！。true优先用SIM0，false则优先用上一次探测到的，默认是false，必须在开机就配置，否则就无效了
@return int 当前sim卡槽编号,若失败返回-1
@usage
-- 注意, SIM1会占用GPIO4/5/6/23
mobile.simid(0) -- 固定使用SIM0
mobile.simid(1) -- 固件使用SIM1
mobile.simid(2) -- 自动识别SIM0, SIM1, 且SIM0优先
mobile.simid(2, true) -- -- 自动识别SIM0, SIM1, 且SIM1优先
-- 提醒, 自动识别是会增加时间的
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
    		luat_mobile_set_sim_detect_sim0_first();
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
检测当前SIM卡是否准备好，对SIM卡的PIN码做相关操作
@api mobile.simPin(id,operation,pin1,pin2)
@int SIM卡的编号, 例如0, 1, 支持双卡双待的才需要选择
@int PIN码操作类型，只能是mobile.PIN_XXXX，不操作就留空
@string 更换pin时操作的pin码，或者验证操作的pin码，或者解锁pin码时的PUK，4~8字节
@string 更换pin码操作时的新的pin码，解锁pin码时的新PIN，4~8字节
@return boolean 当无PIN操作时，返回SIM卡是否准备好，有PIN操作时，返回是否成功
@usage
local cpin_is_ready = mobile.simPin() -- 当前sim卡是否准备好，一般返回false就是没卡
local succ = mobile.simPin(0, mobile.PIN_VERIFY, "1234")	-- 输入pin码验证
 */
static int l_mobile_sim_pin(lua_State* L) {
    char old[9] = {0};
    char new[9] = {0};
    int id = luaL_optinteger(L, 1, 0);
    int operation = luaL_optinteger(L, 2, -1);
    size_t old_len, new_len;
    if (lua_isstring(L, 3))
    {
    	const char *old_pin = lua_tolstring(L, 3, &old_len);
    	memcpy(old, old_pin, (old_len > 8)?8:old_len);
    }
    if (lua_isstring(L, 4))
    {
    	const char *new_pin = lua_tolstring(L, 4, &new_len);
    	memcpy(new, new_pin, (new_len > 8)?8:new_len);
    }
    if (operation != -1)
    {
    	lua_pushboolean(L, (luat_mobile_set_sim_pin(id, operation, old, new) == 0));
    }
    else
    {
    	lua_pushboolean(L, (luat_mobile_get_sim_ready(id) == 1));
    }
    return 1;
}

/**
设置RRC自动释放时间间隔，当开启时后，遇到极弱信号+频繁数据操作可能会引起网络严重故障，因此需要额外设置自动重启协议栈
@api mobile.rtime(time, auto_reset_stack)
@int RRC自动释放时间，等同于Air724的AT+RTIME，单位秒，写0或者不写则是停用，不要超过20秒，没有意义
@boolean 网络遇到严重故障时尝试自动恢复，和飞行模式/SIM卡切换冲突，true开启，false关闭，留空时，如果设置了时间则自动开启
@return nil 无返回值
 */
static int l_mobile_set_rrc_auto_release_time(lua_State* L) {
	luat_mobile_set_rrc_auto_release_time(luaL_optinteger(L, 1, 0));
    if (LUA_TBOOLEAN == lua_type(L, 2)) {
    	luat_mobile_fatal_error_auto_reset_stack(lua_toboolean(L, 2));
    }
    else
    {
    	if (luaL_optinteger(L, 1, 0))
    	{
    		luat_mobile_fatal_error_auto_reset_stack(1);
    	}
    }
    return 0;
}

/**
设置一些辅助周期性或者自动功能，目前支持SIM卡暂时脱离后恢复，周期性获取小区信息，网络遇到严重故障时尝试自动恢复
@api mobile.setAuto(check_sim_period, get_cell_period, search_cell_time, auto_reset_stack)
@int SIM卡自动恢复时间，单位毫秒，建议5000~10000，和飞行模式/SIM卡切换冲突，不能再同一时间使用，必须错开执行。写0或者不写则是关闭功能
@int 周期性获取小区信息的时间间隔，单位毫秒。获取小区信息会增加部分功耗。写0或者不写则是关闭功能
@int 每次搜索小区时最大搜索时间，单位秒。不要超过8秒
@boolean 网络遇到严重故障时尝试自动恢复，和飞行模式/SIM卡切换冲突，true开启，false关闭，开始状态是false，留空则不做改变
@int 设置定时检测网络是否正常并且在检测到长时间无网时通过重启协议栈来恢复，无网恢复时长，单位ms，建议60000以上，为网络搜索网络保留足够的时间，留空则不做更改
@return nil 无返回值
 */
static int l_mobile_set_auto_work(lua_State* L) {
	luat_mobile_set_period_work(luaL_optinteger(L, 2, 0), luaL_optinteger(L, 1, 0), luaL_optinteger(L, 3, 0));
    if (LUA_TBOOLEAN == lua_type(L, 4)) {
    	luat_mobile_fatal_error_auto_reset_stack(lua_toboolean(L, 4));
    }
    if (lua_isinteger(L, 5)) {
    	luat_mobile_set_check_network_period(luaL_optinteger(L, 5, 0));
    }

	return 0;
}

/**
获取或设置APN，设置APN必须在入网前就设置好，比如在SIM卡识别完成前就设置好
@api mobile.apn(index, cid, new_apn_name, user_name, password, ip_type, protocol)
@int 编号,默认0. 在支持双卡的模块上才会出现0或1的情况
@int cid, 默认0，如果要用非默认APN来激活，必须>0
@string 新的APN,不填就是获取APN, 填了就是设置APN, 是否支持设置取决于底层实现
@string 新的APN的username,可以为nil
@string 新的APN的password,可以为nil
@int 激活APN时的IP TYPE,1=IPV4 2=IPV6 3=IPV4V6,默认是1
@int 激活APN时,如果需要username和password,就要写鉴权协议类型,1~3,默认3,代表1和2都尝试一下
@boolean 是否删除APN,true是,其他都否,只有参数3新的APN不是string的时候才有效果
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
		size_t user_name_len = 0;
		size_t password_len = 0;
		const char* user_name = luaL_checklstring(L, 4, &user_name_len);
		const char* password = luaL_checklstring(L, 5, &password_len);
		uint8_t ip_type = luaL_optinteger(L, 6, 1);
		uint8_t protocol = luaL_optinteger(L, 7, 3);
		if (!user_name_len && !password_len)
		{
			protocol = 0;
		}
		if (wlen) {
			luat_mobile_user_apn_auto_active(index, cid, ip_type, protocol, wbuff, wlen, user_name, user_name_len, password, password_len);
		}
		else
		{
			luat_mobile_user_apn_auto_active(index, cid, ip_type, 0xff, NULL, 0, NULL, 0, NULL, 0);
		}
	}
	else
	{
    	if (lua_isboolean(L, 8) && lua_toboolean(L, 8))
    	{
    		luat_mobile_del_apn(index, cid, 0);
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
//	uint8_t onoff;
    if (LUA_TBOOLEAN == lua_type(L, 1)) {
    	luat_mobile_set_default_pdn_ipv6(lua_toboolean(L, 1));
    }
    lua_pushboolean(L, luat_mobile_get_default_pdn_ipv6());
    return 1;
}

/**
获取csq
@api mobile.csq()
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
获取当前服务小区的ECI(E-UTRAN Cell Identifier)
@api mobile.eci()
@return int 当前eci值,若失败返回-1
 */
static int l_mobile_eci(lua_State* L) {
    uint32_t eci;
    if (luat_mobile_get_service_cell_identifier(&eci) == 0) {
        lua_pushinteger(L, eci);
    }
    else {
        lua_pushinteger(L, -1);
    }
    return 1;
}

/**
获取当前服务小区的eNBID(eNodeB Identifier)
@api mobile.enbid()
@return int 当前enbid值,若失败返回-1
 */
static int l_mobile_enbid(lua_State* L) {
    uint32_t eci;
    if (luat_mobile_get_service_cell_identifier(&eci) == 0) {
        lua_pushinteger(L, eci>>8);
    }
    else {
        lua_pushinteger(L, -1);
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
@return int 当前网络状态,0:网络未注册;1:网络已注册;2:正在搜网中;3:网络注册被拒绝
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
    if (info->lte_info_valid == 0 || info->lte_service_info.cid == 0) {
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
@usage
-- 重启LTE协议栈
mobile.reset()
 */
static int l_mobile_reset(lua_State* L) {
    luat_mobile_reset_stack();
    return 0;
}

/**
数据量流量处理
@api mobile.dataTraffic(clearUplink, clearDownlink)
@boolean 清空上行流量累计值，true清空，其他忽略
@boolean 清空下行流量累计值，true清空，其他忽略
@return int 上行流量GB
@return int 上行流量B
@return int 下行流量GB
@return int 下行流量B
@usage
-- 获取上下行流量累计值
-- 上行流量值Byte = uplinkGB * 1024 * 1024 * 1024 + uplinkB
-- 下行流量值Byte = downlinkGB * 1024 * 1024 * 1024 + downlinkB
local uplinkGB, uplinkB, downlinkGB, downlinkB = mobile.dataTraffic()

-- 清空上下行流量累计值
mobile.dataTraffic(true, true)
 */
static int l_mobile_data_traffic(lua_State* L) {
    uint64_t uplink;
    uint64_t downlink;
    uint8_t clear_uplink = 0;
    uint8_t clear_downlink = 0;
    volatile uint32_t temp;
    if (LUA_TBOOLEAN == lua_type(L, 1)) {
    	clear_uplink = lua_toboolean(L, 1);
    }
    if (LUA_TBOOLEAN == lua_type(L, 2)) {
    	clear_downlink = lua_toboolean(L, 2);
    }
    luat_mobile_get_ip_data_traffic(&uplink, &downlink);
    if (clear_uplink || clear_downlink) {
    	luat_mobile_clear_ip_data_traffic(clear_uplink, clear_downlink);
    }
    temp = (uint32_t)(uplink >> 30);
    lua_pushinteger(L, temp);
    temp = (((uint32_t)uplink) & 0x3FFFFFFF);
    lua_pushinteger(L, temp);
    temp = (uint32_t)(downlink >> 30);
    lua_pushinteger(L, temp);
    temp = (((uint32_t)downlink) & 0x3FFFFFFF);
    lua_pushinteger(L, temp);
    return 4;
}
extern int luat_mobile_config(uint8_t item, uint32_t value);
/**
网络特殊配置，针对不同平台有不同的配置，谨慎使用，目前只有EC618
@api mobile.config(item, value)
@int 配置项目，看mobile.CONF_XXX
@int 配置值
@return boolean 是否成功
@usage
-- EC618配置小区重选信号差值门限，不能大于15dbm，必须在飞行模式下才能用
mobile.flymode(0,true)
mobile.config(mobile.CONF_RESELTOWEAKNCELL, 15)
mobile.config(mobile.CONF_STATICCONFIG, 1) --开启网络静态优化
mobile.flymode(0,false)
 */
static int l_mobile_config(lua_State* L) {
    uint8_t item = luaL_optinteger(L, 1, 0);
    uint32_t value = luaL_optinteger(L, 2, 0);
    if (!item)
    {
    	lua_pushboolean(L, 0);
    }
    else
    {
    	lua_pushboolean(L, !luat_mobile_config(item, value));
    }
    return 1;
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
    {"eci",         ROREG_FUNC(l_mobile_eci)},
    {"enbid",      ROREG_FUNC(l_mobile_enbid)},
    {"flymode",     ROREG_FUNC(l_mobile_flymode)},
    {"simid",       ROREG_FUNC(l_mobile_simid)},
	{"simPin",       ROREG_FUNC(l_mobile_sim_pin)},
	{"rtime",       ROREG_FUNC(l_mobile_set_rrc_auto_release_time)},
	{"setAuto",       ROREG_FUNC(l_mobile_set_auto_work)},
    {"getCellInfo", ROREG_FUNC(l_mobile_get_cell_info)},
    {"reqCellInfo", ROREG_FUNC(l_mobile_request_cell_info)},
	{"reset",      ROREG_FUNC(l_mobile_reset)},
	{"dataTraffic",      ROREG_FUNC(l_mobile_data_traffic)},
	{"config",      ROREG_FUNC(l_mobile_config)},
	//@const UNREGISTER number 未注册
    {"UNREGISTER",                  ROREG_INT(LUAT_MOBILE_STATUS_UNREGISTER)},
    //@const REGISTERED number 已注册
    {"REGISTERED",                  ROREG_INT(LUAT_MOBILE_STATUS_REGISTERED)},
	//@const SEARCH number 正在搜索中
	{"SEARCH",                      ROREG_INT(LUAT_MOBILE_STATUS_SEARCHING)},
	//@const DENIED number 注册被拒绝
    {"DENIED",                      ROREG_INT(LUAT_MOBILE_STATUS_DENIED)},
    //@const UNKNOW number 未知
    {"UNKNOW",                      ROREG_INT(LUAT_MOBILE_STATUS_UNKNOW)},
    //@const REGISTERED_ROAMING number 已注册,漫游
    {"REGISTERED_ROAMING",          ROREG_INT(LUAT_MOBILE_STATUS_REGISTERED_ROAMING)},
    //@const SMS_ONLY_REGISTERED number 已注册,仅SMS
    {"SMS_ONLY_REGISTERED",         ROREG_INT(LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED)},
    //@const SMS_ONLY_REGISTERED_ROAMING number 已注册,漫游,仅SMS
    {"SMS_ONLY_REGISTERED_ROAMING", ROREG_INT(LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED_ROAMING)},
    //@const EMERGENCY_REGISTERED number 已注册,紧急服务
    {"EMERGENCY_REGISTERED",        ROREG_INT(LUAT_MOBILE_STATUS_EMERGENCY_REGISTERED)},
    //@const CSFB_NOT_PREFERRED_REGISTERED number 已注册,非主要服务
    {"CSFB_NOT_PREFERRED_REGISTERED",  ROREG_INT(LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED)},
    //@const CSFB_NOT_PREFERRED_REGISTERED_ROAMING number 已注册,非主要服务,漫游
    {"CSFB_NOT_PREFERRED_REGISTERED_ROAMING",  ROREG_INT(LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED_ROAMING)},
	//@const CONF_RESELTOWEAKNCELL number 小区重选信号差值门限,需要飞行模式设置
	{"CONF_RESELTOWEAKNCELL",  ROREG_INT(MOBILE_CONF_RESELTOWEAKNCELL)},
	//@const CONF_STATICCONFIG number 网络静态模式优化,需要飞行模式设置
	{"CONF_STATICCONFIG",  ROREG_INT(MOBILE_CONF_STATICCONFIG)},
	//@const CONF_QUALITYFIRST number 网络切换以信号质量优先,需要飞行模式设置
	{"CONF_QUALITYFIRST",  ROREG_INT(MOBILE_CONF_QUALITYFIRST)},
	//@const CONF_USERDRXCYCLE number LTE跳paging,需要飞行模式设置,谨慎使用,0是不设置,1~7增大或减小DrxCycle周期倍数,1:1/8倍 2:1/4倍 3:1/2倍 4:2倍 5:4倍 6:8倍 7:16倍,8~12配置固定的DrxCycle周期,仅当该周期大于网络分配的DrxCycle周期时该配置才会生效,8:320ms 9:640ms 10:1280ms 11:2560ms 12:5120ms
	{"CONF_USERDRXCYCLE",  ROREG_INT(MOBILE_CONF_USERDRXCYCLE)},
	//@const CONF_T3324MAXVALUE number PSM模式中的T3324时间,单位S
	{"CONF_T3324MAXVALUE",  ROREG_INT(MOBILE_CONF_T3324MAXVALUE)},
	//@const CONF_PSM_MODE number PSM模式开关,0关,1开
	{"CONF_PSM_MODE",  ROREG_INT(MOBILE_CONF_PSM_MODE)},
	//@const CONF_CE_MODE number attach模式，0为EPS ONLY 2为混合，遇到IMSI detach脱网问题，设置为0，注意设置为EPS ONLY时会取消短信功能
	{"CONF_CE_MODE",  ROREG_INT(MOBILE_CONF_CE_MODE)},
	//@const PIN_VERIFY number 验证PIN码操作
	{"PIN_VERIFY",  ROREG_INT(LUAT_SIM_PIN_VERIFY)},
	//@const PIN_CHANGE number 更换PIN码操作
	{"PIN_CHANGE",  ROREG_INT(LUAT_SIM_PIN_CHANGE)},
	//@const PIN_ENABLE number 使能PIN码验证
	{"PIN_ENABLE",  ROREG_INT(LUAT_SIM_PIN_ENABLE)},
	//@const PIN_DISABLE number 关闭PIN码验证
	{"PIN_DISABLE",  ROREG_INT(LUAT_SIM_PIN_DISABLE)},
	//@const PIN_UNBLOCK number 解锁PIN码
	{"PIN_UNBLOCK",  ROREG_INT(LUAT_SIM_PIN_UNBLOCK)},
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
    int ret;

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
		LLOGD("cid%d, state%d", index, status);
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
sys.subscribe("IP_READY", function(ip, adapter)
    log.info("mobile", "IP_READY", ip, (adapter or -1) == socket.LWIP_GP)
end)
*/
            lua_pushstring(L, "IP_READY");
            luat_ip_addr_t local_ip, net_mask, gate_way, ipv6;
            #ifdef LUAT_USE_LWIP
	        ipv6.type = 0xff;
	        int ret = network_get_full_local_ip_info(NULL, NW_ADAPTER_INDEX_LWIP_GPRS, &local_ip, &net_mask, &gate_way, &ipv6);
            #else
	        void* userdata = NULL;
	        network_adapter_info* info = network_adapter_fetch(NW_ADAPTER_INDEX_LWIP_GPRS, &userdata);
	        if (info == NULL)
		        ret = -1;
            else
                ret = info->get_local_ip_info(&local_ip, &net_mask, &gate_way, userdata);
            #endif
            if (ret == 0) {
                #ifdef LUAT_USE_LWIP
		        lua_pushfstring(L, "%s", ipaddr_ntoa(&local_ip));
                #else
                lua_pushfstring(L, "%d.%d.%d.%d", (local_ip.ipv4 >> 24) & 0xFF, (local_ip.ipv4 >> 16) & 0xFF, (local_ip.ipv4 >> 8) & 0xFF, (local_ip.ipv4 >> 0) & 0xFF);
                #endif
            }
            else {
                lua_pushliteral(L, "0.0.0.0");
            }
            lua_pushinteger(L, NW_ADAPTER_INDEX_LWIP_GPRS);
            lua_call(L, 3, 0);
			break;
        case LUAT_MOBILE_NETIF_LINK_OFF:
            LLOGD("NETIF_LINK_OFF -> IP_LOSE");
/*
@sys_pub mobile
已断网
IP_LOSE
@usage
-- 断网后会发一次这个消息
sys.subscribe("IP_LOSE", function(adapter)
    log.info("mobile", "IP_LOSE", (adapter or -1) == socket.LWIP_GP)
end)
*/
            lua_pushstring(L, "IP_LOSE");
            lua_pushinteger(L, NW_ADAPTER_INDEX_LWIP_GPRS);
            lua_call(L, 2, 0);
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
	case LUAT_MOBILE_EVENT_BEARER:
		LLOGD("bearer act %d, result %d",status, index);
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
