/*
@module  ctiot
@summary coap数据处理
@version 1.0
@date    2020.06.30
*/
#include "luat_base.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "luat.ctiot"
#include "luat_log.h"
//---------------------------
#ifdef AIR302
extern void luat_ctiot_init(void);
/**
 * @brief 初始化ctiot，在复位开机后使用一次
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_init(lua_State *L)
{
	luat_ctiot_init();
	return 0;
}

/**
 * @brief 设置和读取ctiot相关参数，有参数输入则设置，无论是否有参数输入，均输出当前参数
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_param(lua_State *L)
{

}

/**
 * @brief 设置和读取ctiot相关模式，有模式输入则设置，无论是否有模式输入，均输出当前模式
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_mode(lua_State *L)
{

}

/**
 * @brief 连接CTIOT，必须在设置完参数和模式后再使用
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_connect(lua_State *L)
{

}

/**
 * @brief 断开ctiot
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_disconnect(lua_State *L)
{

}

/**
 * @brief 发送数据给ctiot
 *
 * @param L
 * @return int
 */
static int l_ctiot_write(lua_State *L)
{

}

/**
 * @brief 读取已经接收到的数据
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_read(lua_State *L)
{

}

/**
 * @brief 发送更新注册信息给ctiot
 * 
 * @param L 
 * @return int 
 */
static int l_ctiot_update(lua_State *L)
{

}
#endif


#include "rotable.h"
static const rotable_Reg reg_ctiot[] =
{
#ifdef AIR302
    { "init", l_ctiot_init, 0},
    { "param", l_ctiot_param, 0},
	{ "mode", l_ctiot_mode, 0},
	{ "connect", l_ctiot_connect, 0},
	{ "disconnect", l_ctiot_disconnect, 0},
	{ "write", l_ctiot_write, 0},
	{ "read", l_ctiot_read, 0},
	{ "update", l_ctiot_update, 0},
    // ----- 类型常量
#endif
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_ctiot( lua_State *L ) {
    rotable_newlib(L, reg_ctiot);
    return 1;
}
