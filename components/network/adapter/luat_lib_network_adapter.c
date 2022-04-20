/*
@module  network_adapter
@summary 网络接口适配
@version 1.0
@date    2022.04.11
*/
#include "luat_base.h"
#ifdef LUAT_USE_NETWORK
#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "net_adapter"
#include "luat_log.h"


static int32_t l_network_callback(void *pdata, void *param)
{

}
/*
将某个通道的通用网络接口的回调调整给lua api
@api network.attach(network.xxx)
@int 通用网络通道号
@function lua回调函数
@usage
network.attach(network.ETH0)
*/
static int l_network_attach(lua_State *L){

	int adapter_index = luaL_checkinteger(L, 1);
	network_set_user_callback(adapter_index, l_network_callback, adapter_index);
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_network_adapter[] =
{
	{ "attach", ROREG_FUNC(l_network_attach)},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
	{},
    { "ETH0",           ROREG_INT(NW_ADAPTER_INDEX_ETH0)},
	{ "STA",          	ROREG_INT(NW_ADAPTER_INDEX_STA)},
	{ "AP",     		ROREG_INT(NW_ADAPTER_INDEX_AP)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_network_adapter( lua_State *L ) {
    luat_newlib2(L, reg_network_adapter);
    return 1;
}
#endif
