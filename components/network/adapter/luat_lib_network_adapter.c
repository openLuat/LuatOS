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
static const char NW_TYPE[] = "NW*";
typedef struct
{
	network_ctrl_t *netc;
	int cb_ref;	//回调函数
	char *task_name;
}luat_network_ctrl_t;


static int32_t l_network_callback(lua_State *L, void* ptr)
{
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_network_ctrl_t *l_ctrl =(luat_network_ctrl_t *)msg->ptr;

    if (l_ctrl->netc)
    {
    	if (l_ctrl->cb_ref)
    	{
            lua_geti(L, LUA_REGISTRYINDEX, l_ctrl->cb_ref);
            if (lua_isfunction(L, -1)) {
            	lua_pushlightuserdata(L, l_ctrl);
            	lua_pushinteger(L, msg->arg1);
            	lua_pushinteger(L, msg->arg2);
                lua_call(L, 3, 0);
            }
    	}
    	else if (l_ctrl->task_name)
    	{
    	    lua_getglobal(L, "sys_send");
    	    if (lua_isfunction(L, -1)) {
    	        lua_pushstring(L, l_ctrl->task_name);
    	        lua_pushinteger(L, msg->arg1);
    	        lua_pushinteger(L, msg->arg2);
    	        lua_call(L, 3, 0);
    	    }
    	}
    	else
    	{
    	    lua_getglobal(L, "sys_pub");
    	    if (lua_isfunction(L, -1)) {
    	        lua_pushstring(L, NW_TYPE);
    	        lua_pushinteger(L, l_ctrl->netc->adapter_index);
    	        lua_pushinteger(L, l_ctrl->netc->socket_id);
    	        lua_pushinteger(L, msg->arg1);
    	        lua_pushinteger(L, msg->arg2);
    	        lua_call(L, 5, 0);
    	    }
    	}
    }
    lua_pushinteger(L, 0);
    return 1;
}

static int32_t luat_lib_network_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;

    rtos_msg_t msg;
    msg.handler = l_network_callback;
    msg.ptr = param;
    msg.arg1 = event->ID & 0x0fffffff;
    msg.arg2 = event->Param2;
    luat_msgbus_put(&msg, 0);
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_network_adapter[] =
{
    { "ETH0",           ROREG_INT(NW_ADAPTER_INDEX_ETH0)},
	{ "STA",          	ROREG_INT(NW_ADAPTER_INDEX_STA)},
	{ "AP",     		ROREG_INT(NW_ADAPTER_INDEX_AP)},

    { "RESET",           ROREG_INT(EV_NW_RESET & 0x0fffffff)},
	{ "STATE",          	ROREG_INT(EV_NW_STATE & 0x0fffffff)},
	{ "TIMEOUT",     		ROREG_INT(EV_NW_TIMEOUT & 0x0fffffff)},
    { "TX_OK",           ROREG_INT(EV_NW_SOCKET_TX_OK & 0x0fffffff)},
	{ "RX_NEW",          	ROREG_INT(EV_NW_SOCKET_RX_NEW & 0x0fffffff)},
	{ "RX_FULL",     		ROREG_INT(EV_NW_SOCKET_RX_FULL & 0x0fffffff)},
	{ "CLOSED",     		ROREG_INT(EV_NW_SOCKET_CLOSE_OK & 0x0fffffff)},
	{ "R_CLOSE",     		ROREG_INT(EV_NW_SOCKET_REMOTE_CLOSE & 0x0fffffff)},
	{ "CONNECT",     		ROREG_INT(EV_NW_SOCKET_CONNECT_OK & 0x0fffffff)},
	{ "DNS",     		ROREG_INT(EV_NW_SOCKET_DNS_RESULT & 0x0fffffff)},
	{ "ERROR",     		ROREG_INT(EV_NW_SOCKET_ERROR & 0x0fffffff)},
	{ "LISTEN",     		ROREG_INT(EV_NW_SOCKET_LISTEN & 0x0fffffff)},
	{ "R_CONN",     		ROREG_INT(EV_NW_SOCKET_NEW_CONNECT & 0x0fffffff)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_network_adapter( lua_State *L ) {
    luat_newlib2(L, reg_network_adapter);
    return 1;
}
#endif
