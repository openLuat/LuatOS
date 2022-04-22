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
#define LUAT_LOG_TAG "network"
#include "luat_log.h"
//static const char NW_TYPE[] = "NWA*";
#define LUAT_NW_CTRL_TYPE "NWCTRL*"
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
    	        lua_pushstring(L, LUAT_NW_CTRL_TYPE);
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

// __gc
static int l_network_gc(lua_State *L)
{
	luat_network_ctrl_t *l_ctrl = ((luat_network_ctrl_t *)luaL_checkudata(L, 1, LUAT_NW_CTRL_TYPE));
    if (l_ctrl->netc)
    {
    	network_socket_force_close(l_ctrl->netc);
    	network_release_ctrl(l_ctrl->netc);
    	l_ctrl->netc = NULL;
    }
    if (l_ctrl->cb_ref)
    {
        luaL_unref(L, LUA_REGISTRYINDEX, l_ctrl->cb_ref);
        l_ctrl->cb_ref = 0;
    }
    if (l_ctrl->task_name)
    {
    	luat_heap_free(l_ctrl->task_name);
    	l_ctrl->task_name = 0;
    }
    return 0;
}

/*
在某个适配的网卡上申请一个network_ctrl
@api    network.create(adapter, cb)
@int 适配器序号， 只能是network.ETH0，network.STA，network.AP，如果不填，会选择最后一个注册的适配器
@string or function string为消息通知的taskName, function则为回调函数
当通过回调函数回调消息时，输入给function一共3个参数：
param1为申请的network_ctrl
param2为具体的消息，只能是network.RESET, network.STATE, network.TIMEOUT, network.TX_OK等等
param3为消息对应的参数
@return 成功返回network_ctrl，失败返回nil
@usage
local netc = network.create(network.ETH0, socket_cb_fun)	--以太网网卡上申请一个network_ctrl,通过socket_cb_fun回调相关消息
local netc = network.create(network.ETH0, "IOT_TASK")	--以太网网卡上申请一个network_ctrl,通过sendMsg方式通知taskName为"IOT_TASK"回调相关消息

*/
static int l_network_create(lua_State *L)
{
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY)
	{
		lua_pushnil(L);
		return 1;
	}
	luat_network_ctrl_t *l_ctrl = (luat_network_ctrl_t *)lua_newuserdata(L, sizeof(luat_network_ctrl_t));
	if (!l_ctrl)
	{
		lua_pushnil(L);
		return 1;
	}
	l_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!l_ctrl->netc)
	{
		lua_pushnil(L);
		return 1;
	}
	network_init_ctrl(l_ctrl->netc, NULL, luat_lib_network_callback, l_ctrl);
	if (lua_isfunction(L, 2))
	{
        lua_pushvalue(L, 2);
        l_ctrl->cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        l_ctrl->task_name = NULL;
	}
	else if (lua_isstring(L, 2))
	{
		l_ctrl->cb_ref = 0;
	    size_t len;
	    const char *buf;
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
		l_ctrl->task_name = luat_heap_malloc(len + 1);
		memset(l_ctrl->task_name, 0, len + 1);
		memcpy(l_ctrl->task_name, buf, len);
	}
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_network_adapter[] =
{
	{"create",			ROREG_FUNC(l_network_create)},

    { "ETH0",           ROREG_INT(NW_ADAPTER_INDEX_ETH0)},
	{ "STA",          	ROREG_INT(NW_ADAPTER_INDEX_STA)},
	{ "AP",     		ROREG_INT(NW_ADAPTER_INDEX_AP)},
    { "RESET",           ROREG_INT(EV_NW_RESET & 0x0fffffff)},
	{ "STATE",          	ROREG_INT(EV_NW_STATE & 0x0fffffff)},
    { "TX_OK",           ROREG_INT(EV_NW_SOCKET_TX_OK & 0x0fffffff)},
	{ "RX_NEW",          	ROREG_INT(EV_NW_SOCKET_RX_NEW & 0x0fffffff)},
	{ "RX_FULL",     		ROREG_INT(EV_NW_SOCKET_RX_FULL & 0x0fffffff)},
	{ "CLOSED",     		ROREG_INT(EV_NW_SOCKET_CLOSE_OK & 0x0fffffff)},
	{ "R_CLOSE",     		ROREG_INT(EV_NW_SOCKET_REMOTE_CLOSE & 0x0fffffff)},
	{ "CONNECT",     		ROREG_INT(EV_NW_SOCKET_CONNECT_OK & 0x0fffffff)},
	{ "ERROR",     		ROREG_INT(EV_NW_SOCKET_ERROR & 0x0fffffff)},
	{ "LISTEN",     		ROREG_INT(EV_NW_SOCKET_LISTEN & 0x0fffffff)},
	{ "R_CONN",     		ROREG_INT(EV_NW_SOCKET_NEW_CONNECT & 0x0fffffff)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_network_adapter( lua_State *L ) {
    luat_newlib2(L, reg_network_adapter);
    luaL_newmetatable(L, LUAT_NW_CTRL_TYPE); /* create metatable for file handles */
    lua_pushcfunction(L, l_network_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1); /* pop new metatable */
    return 1;
}
#endif
