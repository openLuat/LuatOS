
/*
@module  dac
@summary 数模转换
@version 1.0
@date    2021.12.03
@demo multimedia
@tag LUAT_USE_DAC
*/

#include "luat_base.h"
#include "luat_dac.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#define LUAT_LOG_TAG "dac"
#include "luat_log.h"
#ifdef LUAT_USE_DAC
static int l_dac_cb;


int l_dac_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    if (l_dac_cb)
    {
        lua_geti(L, LUA_REGISTRYINDEX, l_dac_cb);
        lua_pushinteger(L, msg->arg1);
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 2, 0);
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

/*
打开DAC通道,并配置参数
@api dac.open(ch, freq, bits, dac_chl)
@int 通道编号,例如0
@int 输出频率,单位hz
@int 深度,默认为16
@int 通道选择,默认为0, 0:左声道, 1:右声道, 2:左右声道
@return true 成功返回true,否则返回false
@return int 底层返回值,调试用
@usage
if dac.open(0, 44000, 16, 0) then
    log.info("dac", "dac ch0 is opened")
end

*/
static int l_dac_open(lua_State *L) {
    luat_dac_config_t config = {0};
    int ch = luaL_checkinteger(L, 1);
    config.samp_rate = luaL_checkinteger(L, 2);
    config.bits = luaL_optinteger(L, 3, LUAT_DAC_BITS_16);
    config.dac_chl = luaL_optinteger(L, 4, LUAT_DAC_CHL_L);
    int ret = luat_dac_setup(ch, &config);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
从指定DAC通道输出一段波形,或者单个值
@api dac.write(ch, data)
@int 通道编号,例如0
@string 若输出固定值,可以填数值, 若输出波形,填string
@return boolean true 成功返回true,否则返回false
@return int 底层返回值,调试用
@usage
if dac.open(0, 44000) then
    log.info("dac", "dac ch0 is opened")
    dac.write(0, string.fromHex("ABCDABCD"))
end
dac.close(0)
*/
static int l_dac_write(lua_State *L) {
    uint8_t* buff;
    size_t len;
    int ch;
    uint8_t value;
    luat_zbuff_t *tx_buff;
    ch = luaL_checkinteger(L, 1);
    if (lua_isinteger(L, 2)) {
        value = luaL_checkinteger(L, 2);
        buff = &value;
        len = 1;
    }
    else if (lua_isuserdata(L, 2)) {
    	tx_buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
    	buff = tx_buff->addr;
    	len = tx_buff->used;
    }
    else if (lua_isstring(L, 2)) {
        buff = (uint8_t*)luaL_checklstring(L, 2, &len);
    }
    else {
        return 0;
    }
    int ret = luat_dac_write(ch, buff, len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
关闭DAC通道
@api dac.close(ch)
@int 通道编号,例如0
@return true 成功返回true,否则返回false
@return int 底层返回值,调试用
@usage
if dac.open(0, 44000) then
    log.info("dac", "dac ch0 is opened")
    dac.write(0, string.fromHex("ABCDABCD"))
end
dac.close(0)
*/
static int l_dac_close(lua_State *L) {
    int ch = luaL_checkinteger(L, 1);
    int ret = luat_dac_close(ch);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
注册全局DAC事件回调
@api dac.on(func)
@function 回调方法
@return nil 无返回值
@usage
dac.on(function(ch, event, param1, param2, param3)
    log.info("dac", ch, event, param1, param2, param3)
end)
--回调参数有5个
1、ch 0:左声道, 1:右声道
2、event
3、param1,
4、param2,
5、param3,
event类型含义及后续param含义
1、dac.TX_DONE 发送完成

*/
static int l_dac_on(lua_State *L) {

    if (l_dac_cb)
    {
    	luaL_unref(L, LUA_REGISTRYINDEX, l_dac_cb);
    	l_dac_cb = 0;
    }
	if (lua_isfunction(L, 1)) {
		lua_pushvalue(L, 1);
		l_dac_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_dac[] =
{
    { "open" ,       ROREG_FUNC(l_dac_open)},
    { "write" ,      ROREG_FUNC(l_dac_write)},
    { "close" ,      ROREG_FUNC(l_dac_close)},
	{ "on" ,       	 ROREG_FUNC(l_dac_on)},
	//@const HOST number USB主机模式
    { "TX_DONE",     ROREG_INT(LUAT_DAC_EVENT_TX_DONE)},
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_dac( lua_State *L ) {
    luat_newlib2(L, reg_dac);
    return 1;
}

#endif
