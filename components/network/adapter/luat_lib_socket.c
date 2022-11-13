/*
@module  socket
@summary 网络接口
@version 1.0
@date    2022.11.13
@demo socket
*/
#include "luat_base.h"
#include "luat_malloc.h"
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
	uint8_t adapter_index;
}luat_socket_ctrl_t;

#ifdef LUAT_USE_LWIP

static int32_t l_socket_callback(lua_State *L, void* ptr)
{
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_socket_ctrl_t *l_ctrl =(luat_socket_ctrl_t *)msg->ptr;
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

static int32_t luat_lib_socket_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	rtos_msg_t msg;
    msg.handler = l_socket_callback;
    msg.ptr = param;
    msg.arg1 = event->ID & 0x0fffffff;
    msg.arg2 = event->Param1;
    luat_msgbus_put(&msg, 0);
    return 0;
}

static luat_socket_ctrl_t * l_get_ctrl(lua_State *L, int index)
{
	if (luaL_testudata(L, 1, LUAT_NW_CTRL_TYPE))
	{
		return ((luat_socket_ctrl_t *)luaL_checkudata(L, 1, LUAT_NW_CTRL_TYPE));
	}
	else
	{
		return ((luat_socket_ctrl_t *)lua_touserdata(L, 1));
	}
}

// __gc
static int l_socket_gc(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
    if (l_ctrl->netc)
    {
    	network_force_close_socket(l_ctrl->netc);
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
在某个适配的网卡上申请一个socket_ctrl
@api    socket.create(adapter, cb)
@int 适配器序号， 只能是socket.ETH0（外置以太网），socket.LWIP_ETH（内置以太网），socket.LWIP_STA（内置WIFI的STA），socket.LWIP_AP（内置WIFI的AP），socket.LWIP_GP（内置蜂窝网络的GPRS），socket.USB（外置USB网卡），如果不填，优先选择soc平台自带能上外网的适配器，若仍然没有，选择最后一个注册的适配器
@string or function string为消息通知的taskName，function则为回调函数，如果固件没有内置sys_wait，则必须是function
当通过回调函数回调消息时，输入给function一共3个参数：
param1为申请的network_ctrl
param2为具体的消息，只能是socket.RESET, socket.LINK, socket.ON_LINE, socket.TX_OK, socket.RX_NEW, socket.CLOSE等等
param3为消息对应的参数
@return some 成功返回network_ctrl，失败返回nil
@usage
local netc = socket.create(socket.ETH0, socket_cb_fun)	--以太网网卡上申请一个network_ctrl,通过socket_cb_fun回调相关消息
local netc = socket.create(socket.ETH0, "IOT_TASK")	--以太网网卡上申请一个network_ctrl,通过sendMsg方式通知taskName为"IOT_TASK"回调相关消息

*/
static int l_socket_create(lua_State *L)
{
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY)
	{
		lua_pushnil(L);
		return 1;
	}

	luat_socket_ctrl_t *l_ctrl = (luat_socket_ctrl_t *)lua_newuserdata(L, sizeof(luat_socket_ctrl_t));
	if (!l_ctrl)
	{
		lua_pushnil(L);
		return 1;
	}
	l_ctrl->adapter_index = adapter_index;
	l_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!l_ctrl->netc)
	{
		LLOGD("create fail");
		lua_pushnil(L);
		return 1;
	}
	network_init_ctrl(l_ctrl->netc, NULL, luat_lib_socket_callback, l_ctrl);
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
	luaL_setmetatable(L, LUAT_NW_CTRL_TYPE);
	return 1;
}

/*
配置是否打开debug信息
@api socket.debug(ctrl, onoff)
@user_data socket.create得到的ctrl
@boolean true 打开debug开关
@return nil 无返回值
@usage socket.debug(ctrl, true)
*/
static int l_socket_set_debug(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	if (lua_isboolean(L, 2))
	{
		l_ctrl->netc->is_debug = lua_toboolean(L, 2);
	}
	return 0;
}

/*
配置network一些信息，
@api socket.config(ctrl, local_port, is_udp, is_tls, keep_idle, keep_interval, keep_cnt, server_cert, client_cert, client_key, client_password)
@user_data socket.create得到的ctrl
@int 本地端口号，小端格式，如果不写，则自动分配一个，如果用户填了端口号则需要小于60000, 默认不写
@boolean 是否是UDP，默认false
@boolean 是否是加密传输，默认false
@int tcp keep live模式下的idle时间（秒），如果留空则表示不启用，如果是不支持标准posix接口的网卡（比如W5500），则为心跳间隔
@int tcp keep live模式下的探测间隔时间（秒）
@int tcp keep live模式下的探测次数
@string TCP模式下的服务器ca证书数据，UDP模式下的PSK，不需要加密传输写nil，后续参数也全部nil
@string TCP模式下的客户端ca证书数据，UDP模式下的PSK-ID，TCP模式下如果不需要验证客户端证书时，忽略，一般不需要验证客户端证书
@string TCP模式下的客户端私钥加密数据
@string TCP模式下的客户端私钥口令数据
@return nil 无返回值
@usage socket.config(ctrl)	--最普通的TCP传输
socket.config(ctrl, nil, nil ,true)	--最普通的加密TCP传输，证书都不用验证的那种
*/
static int l_socket_config(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	uint8_t is_udp = 0;
	uint8_t is_tls = 0;
	int param_pos = 1;
	uint32_t keep_idle, keep_interval, keep_cnt;

	const char *server_cert = NULL;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	size_t server_cert_len, client_cert_len, client_key_len, client_password_len;

	uint16_t local_port = luaL_optinteger(L, ++param_pos, 0);
	if (lua_isboolean(L, ++param_pos))
	{
		is_udp = lua_toboolean(L, param_pos);
	}
	if (lua_isboolean(L, ++param_pos))
	{
		is_tls = lua_toboolean(L, param_pos);
	}
	keep_idle = luaL_optinteger(L, ++param_pos, 0);
	keep_interval = luaL_optinteger(L, ++param_pos, 0);
	keep_cnt = luaL_optinteger(L, ++param_pos, 0);
	if (lua_isstring(L, ++param_pos))
	{
		server_cert_len = 0;
		server_cert = luaL_checklstring(L, param_pos, &server_cert_len);
	}
	if (lua_isstring(L, ++param_pos))
	{
		client_cert_len = 0;
		client_cert = luaL_checklstring(L, param_pos, &client_cert_len);
	}

	if (lua_isstring(L, ++param_pos))
	{
		client_key_len = 0;
		client_key = luaL_checklstring(L, param_pos, &client_key_len);
	}
	if (lua_isstring(L, ++param_pos))
	{
		client_password_len = 0;
		client_password = luaL_checklstring(L, param_pos, &client_password_len);
	}
	network_set_base_mode(l_ctrl->netc, !is_udp, 10000, keep_idle, keep_idle, keep_interval, keep_cnt);
	network_set_local_port(l_ctrl->netc, local_port);
	if (is_tls)
	{
		network_init_tls(l_ctrl->netc, (server_cert || client_cert)?2:0);
		if (is_udp)
		{
			network_set_psk_info(l_ctrl->netc, server_cert, server_cert_len, client_key, client_key_len);
		}
		else
		{
			if (server_cert)
			{
				network_set_server_cert(l_ctrl->netc, server_cert, server_cert_len);
			}
			if (client_cert)
			{
				network_set_client_cert(l_ctrl->netc, client_cert, client_cert_len,
						client_key, client_key_len,
						client_password, client_password_len);
			}
		}
	}
	else
	{
		network_deinit_tls(l_ctrl->netc);
	}
	return 0;
}

/*
等待网卡linkup
@api socket.linkup(ctrl)
@user_data socket.create得到的ctrl
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了
@return boolean true已经linkup，false没有linkup，之后需要接收socket.LINK消息
@usage local error, result = socket.linkup(ctrl)
*/
static int l_socket_linkup(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_wait_link_up(l_ctrl->netc, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;


}

/*
作为客户端连接服务器
@api socket.connect(ctrl, ip, remote_port)
@user_data socket.create得到的ctrl
@string or int ip或者域名，如果是IPV4，可以是大端格式的int值
@int 服务器端口号，小端格式
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return boolean true已经connect，false没有connect，之后需要接收socket.ON_LINE消息
@usage local error, result = socket.connect(ctrl, "xxx.xxx.xxx.xxx", xxxx)
*/
static int l_socket_connect(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	luat_ip_addr_t ip_addr;
	const char *ip;
	size_t ip_len;
	ip_addr.type = 0xff;
	if (lua_isinteger(L, 2))
	{
		ip_addr.type = IPADDR_TYPE_V4;
		ip_addr.u_addr.ip4.addr = lua_tointeger(L, 2);
		ip = NULL;
		ip_len = 0;
	}
	else
	{
		ip_len = 0;
	    ip = luaL_checklstring(L, 2, &ip_len);
	}
	uint16_t remote_port = luaL_checkinteger(L, 3);
	int result = network_connect(l_ctrl->netc, ip, ip_len, (ip_addr.type != IPADDR_TYPE_V4)?NULL:&ip_addr, remote_port, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
作为客户端断开连接
@api socket.discon(ctrl)
@user_data socket.create得到的ctrl
@return
boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了
boolean true已经断开，false没有断开，之后需要接收socket.CLOSED消息
@usage local error, result = socket.discon(ctrl)
*/
static int l_socket_disconnect(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_close(l_ctrl->netc, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
强制关闭socket
@api socket.close(ctrl)
@user_data socket.create得到的ctrl
*/
static int l_socket_close(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	network_force_close_socket(l_ctrl->netc);
	return 0;
}

/*
发送数据给对端，UDP单次发送不要超过1460字节，否则很容易失败
@api socket.tx(ctrl, data, ip, port, flag)
@user_data socket.create得到的ctrl
@string or user_data zbuff  要发送的数据
@string or int 对端IP，如果是TCP应用则忽略，如果是UDP，如果留空则用connect时候的参数，如果是IPV4，可以是大端格式的int值
@int 对端端口号，小端格式，如果是TCP应用则忽略，如果是UDP，如果留空则用connect时候的参数
@int 发送参数，目前预留，不起作用
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return boolean true缓冲区满了，false没有异常，如果true，则需要等待一段时间或者等到socket.TX_OK消息后再尝试发送，同时忽略下一个返回值
@return boolean true已经收到应答，false没有收到应答，之后需要接收socket.TX_OK消息， 也可以忽略继续发送，直到full==true
@usage local error, full, result = socket.tx(ctrl, "123456", "xxx.xxx.xxx.xxx", xxxx)
*/
static int l_socket_tx(lua_State *L)
{
	char ip_buf[68];
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	luat_ip_addr_t ip_addr;
	luat_zbuff_t *buff = NULL;
	const char *ip;
	const char *data;
	size_t ip_len, data_len;
	ip_addr.type = 0xff;
	if (lua_isstring(L, 2))
	{
		data_len = 0;
		data = luaL_checklstring(L, 2, &data_len);
	}
	else
	{
		buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
		data = buff->addr;
		data_len = buff->used;
	}
	if (lua_isinteger(L, 3))
	{
		ip_addr.type = 0;
		ip_addr.u_addr.ip4.addr = lua_tointeger(L, 3);
	}
	else if (lua_isstring(L, 3))
	{
		ip_len = 0;
	    ip = luaL_checklstring(L, 3, &ip_len);
	    memcpy(ip_buf, ip, ip_len);
	    ip_buf[ip_len] = 0;
	    ipaddr_aton(ip_buf, &ip_addr);

	}
	uint32_t tx_len;
	int result = network_tx(l_ctrl->netc, data, data_len, luaL_optinteger(L, 5, 0), (ip_addr.type != 0xff)?&ip_addr:NULL, luaL_optinteger(L, 4, 0), &tx_len, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, tx_len != data_len);
	lua_pushboolean(L, result == 0);
	return 3;
}

/*
接收对端发出的数据，注意数据已经缓存在底层，使用本函数只是提取出来，UDP模式下一次只会取出一个数据包
@api socket.rx(ctrl, buff, flag)
@user_data socket.create得到的ctrl
@user_data zbuff 存放接收的数据，如果缓冲区不够大会自动扩容
@int 接收参数，目前预留，不起作用
@return boolean true有异常发生，false没有异常，如果有异常，后续要close
@return int 本次接收到数据长度
@return string 对端IP，只有UDP模式下才有意义，TCP模式返回nil，注意返回的格式，如果是IPV4，1byte 0x00 + 4byte地址 如果是IPV6，1byte 0x01 + 16byte地址
@return int 对端port，只有UDP模式下才有意义，TCP模式返回0
@usage local error, data_len, ip, port = socket.rx(ctrl, buff)
*/
static int l_socket_rx(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));

	luat_ip_addr_t ip_addr;
	uint8_t ip[17];
	uint16_t port;
	uint8_t new_flag = 0;
	int rx_len;
	int total_len;
	int result = network_rx(l_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (result < 0)
	{
		lua_pushboolean(L, 1);
		lua_pushinteger(L, 0);
		lua_pushnil(L);
		lua_pushnil(L);
	}
	else if (!total_len)
	{
		lua_pushboolean(L, 0);
		lua_pushinteger(L, 0);
		lua_pushnil(L);
		lua_pushnil(L);
	}
	else
	{
		if ((buff->len - buff->used) < total_len)
		{
			__zbuff_resize(buff, total_len + buff->used);
		}
		result = network_rx(l_ctrl->netc, buff->addr + buff->used, total_len, 0, &ip_addr, &port, &rx_len);
		if (result < 0)
		{
			lua_pushboolean(L, 1);
			lua_pushinteger(L, 0);
			lua_pushnil(L);
			lua_pushnil(L);
		}
		else if (!rx_len)
		{
			lua_pushboolean(L, 0);
			lua_pushinteger(L, 0);
			lua_pushnil(L);
			lua_pushnil(L);
		}
		else
		{
			buff->used += rx_len;
			lua_pushboolean(L, 0);
			lua_pushinteger(L, rx_len);
			if (l_ctrl->netc->is_tcp)
			{
				lua_pushnil(L);
				lua_pushnil(L);
			}
			else
			{
				if (IPADDR_TYPE_V4 == ip_addr.type)
				{
					ip[0] = 0;
					memcpy(ip + 1, &ip_addr.u_addr.ip4.addr, 4);
					lua_pushlstring(L, ip, 5);
				}
				else
				{
					ip[0] = 1;
					memcpy(ip + 1, ip_addr.u_addr.ip6.addr, 16);
					lua_pushlstring(L, ip, 17);
				}
				lua_pushinteger(L, port);
			}
		}
	}
	return 4;
}

/*
等待新的socket消息，在连接成功和发送数据成功后，使用一次将network状态转换到接收新数据
@api socket.wait(ctrl)
@user_data socket.create得到的ctrl
@return boolean true有异常发生，false没有异常，如果有异常，后续要close
@return boolean true有新的数据需要接收，false没有数据，之后需要接收socket.EVENT消息
@usage local error, result = socket.wait(ctrl)
*/
static int l_socket_wait(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_wait_event(l_ctrl->netc, NULL, 0, NULL);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
作为服务端开始监听
@api socket.listen(ctrl)
@user_data socket.create得到的ctrl
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return boolean true已经connect，false没有connect，之后需要接收socket.ON_LINE消息
@usage local error, result = socket.listen(ctrl)
*/
static int l_socket_listen(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_listen(l_ctrl->netc, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
作为服务端接收到一个新的客户端，注意，如果是类似W5500的硬件协议栈不支持1对多，则不需要第二个参数
@api socket.accept(ctrl)
@user_data socket.create得到的ctrl，这里是服务器端
@string or function or nil string为消息通知的taskName，function则为回调函数，和socket.create参数一致
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return user_data or nil 如果支持1对多，则会返回新的ctrl，自动create，如果不支持则返回nil
@usage local error, new_netc = socket.listen(ctrl, cb)
*/
static int l_socket_accept(lua_State *L)
{
	luat_socket_ctrl_t *old_ctrl = l_get_ctrl(L, 1);
	if (network_accept_enable(old_ctrl->netc))
	{
		luat_socket_ctrl_t *new_ctrl = (luat_socket_ctrl_t *)lua_newuserdata(L, sizeof(luat_socket_ctrl_t));
		if (!new_ctrl)
		{
			lua_pushboolean(L, 0);
			lua_pushnil(L);
			return 2;
		}
		new_ctrl->adapter_index = old_ctrl->adapter_index;
		new_ctrl->netc = network_alloc_ctrl(old_ctrl->adapter_index);
		if (!new_ctrl->netc)
		{
			LLOGD("create fail");
			lua_pushboolean(L, 0);
			lua_pushnil(L);
			return 2;
		}
		network_init_ctrl(new_ctrl->netc, NULL, luat_lib_socket_callback, new_ctrl);
		if (lua_isfunction(L, 2))
		{
			lua_pushvalue(L, 2);
			new_ctrl->cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
			new_ctrl->task_name = NULL;
		}
		else if (lua_isstring(L, 2))
		{
			new_ctrl->cb_ref = 0;
			size_t len;
			const char *buf;
			buf = lua_tolstring(L, 2, &len);//取出字符串数据
			new_ctrl->task_name = luat_heap_malloc(len + 1);
			memset(new_ctrl->task_name, 0, len + 1);
			memcpy(new_ctrl->task_name, buf, len);
		}
		if (network_socket_accept(old_ctrl, new_ctrl))
		{
			lua_pushboolean(L, 0);
			lua_pushnil(L);
			return 2;
		}
		else
		{
			lua_pushboolean(L, 1);
			luaL_setmetatable(L, LUAT_NW_CTRL_TYPE);
			return 2;
		}

	}
	else
	{
		lua_pushboolean(L, !network_socket_accept(old_ctrl->netc, NULL));
		lua_pushnil(L);
		return 2;
	}
}

/*
主动释放掉network_ctrl
@api    socket.release(ctrl)
@user_data	socket.create得到的ctrl
@usage socket.release(ctrl)
*/
static int l_socket_release(lua_State *L)
{
	return l_socket_gc(L);
}

/*
设置DNS服务器
@api    socket.setDNS(adapter_index, dns_index, ip)
@int 适配器序号， 只能是socket.ETH0，socket.STA，socket.AP，如果不填，会选择最后一个注册的适配器
@int dns服务器序号，从1开始
@string or int dns，如果是IPV4，可以是大端格式的int值
@return boolean 成功返回true，失败返回false
@usage socket.setDNS(socket.ETH0, 1, "114.114.114.114")
*/
static int l_socket_set_dns(lua_State *L)
{
	char ip_buf[68];
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
	int dns_index = luaL_optinteger(L, 2, 1);
	luat_ip_addr_t ip_addr;
	const char *ip;
	size_t ip_len;
	ip_addr.type = 0xff;
	if (lua_isinteger(L, 3))
	{
		ip_addr.type = 0;
		ip_addr.u_addr.ip4.addr = lua_tointeger(L, 3);
		ip = NULL;
		ip_len = 0;
	}
	else
	{
		ip_len = 0;
	    ip = luaL_checklstring(L, 3, &ip_len);
	    memcpy(ip_buf, ip, ip_len);
	    ip_buf[ip_len] = 0;
	    ipaddr_aton(ip_buf, &ip_addr);
	}
	network_set_dns_server(adapter_index, dns_index - 1, &ip_addr);
	lua_pushboolean(L, 1);
	return 1;
}

/*
设置SSL的log
@api    socket.sslLog(log_level)
@int	mbedtls log等级，<=2基本不打印，不要超过9
@usage socket.sslLog(3)
*/
static int l_socket_set_ssl_log(lua_State *L)
{
	mbedtls_debug_set_threshold(luaL_optinteger(L, 1, 1));
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_socket_adapter[] =
{
	{"create",			ROREG_FUNC(l_socket_create)},
	{"debug",		ROREG_FUNC(l_socket_set_debug)},
	{"config",		ROREG_FUNC(l_socket_config)},
	{"linkup",			ROREG_FUNC(l_socket_linkup)},
	{"connect",			ROREG_FUNC(l_socket_connect)},
	{"listen",			ROREG_FUNC(l_socket_listen)},
	{"accept",			ROREG_FUNC(l_socket_accept)},
	{"discon",			ROREG_FUNC(l_socket_disconnect)},
	{"close",			ROREG_FUNC(l_socket_close)},
	{"tx",			ROREG_FUNC(l_socket_tx)},
	{"rx",			ROREG_FUNC(l_socket_rx)},
	{"wait",			ROREG_FUNC(l_socket_wait)},
	//{"listen",			ROREG_FUNC(l_socket_listen)},
	//{"accept",			ROREG_FUNC(l_socket_accept)},
	{"release",			ROREG_FUNC(l_socket_release)},
	{ "setDNS",           ROREG_FUNC(l_socket_set_dns)},
	{ "sslLog",			ROREG_FUNC(l_socket_set_ssl_log)},
    { "ETH0",           ROREG_INT(NW_ADAPTER_INDEX_ETH0)},
	{ "LWIP_ETH",          	ROREG_INT(NW_ADAPTER_INDEX_LWIP_ETH)},
	{ "LWIP_STA",          	ROREG_INT(NW_ADAPTER_INDEX_LWIP_WIFI_STA)},
	{ "LWIP_AP",     		ROREG_INT(NW_ADAPTER_INDEX_LWIP_WIFI_AP)},
	{ "LWIP_GP",          	ROREG_INT(NW_ADAPTER_INDEX_LWIP_GPRS)},
	{ "USB",     		ROREG_INT(NW_ADAPTER_INDEX_USB)},
    { "LINK",           ROREG_INT(EV_NW_RESULT_LINK & 0x0fffffff)},
	{ "ON_LINE",          	ROREG_INT(EV_NW_RESULT_CONNECT & 0x0fffffff)},
	{ "EVENT",          	ROREG_INT(EV_NW_RESULT_EVENT & 0x0fffffff)},
	{ "TX_OK",     		ROREG_INT(EV_NW_RESULT_TX & 0x0fffffff)},
	{ "CLOSED",     		ROREG_INT(EV_NW_RESULT_CLOSE & 0x0fffffff)},
	{ NULL,            ROREG_INT(0)}
};

#else
static int32_t l_socket_callback(lua_State *L, void* ptr)
{
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_socket_ctrl_t *l_ctrl =(luat_socket_ctrl_t *)msg->ptr;
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

static int32_t luat_lib_socket_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	rtos_msg_t msg;
    msg.handler = l_socket_callback;
    msg.ptr = param;
    msg.arg1 = event->ID & 0x0fffffff;
    msg.arg2 = event->Param1;
    luat_msgbus_put(&msg, 0);
    return 0;
}

static luat_socket_ctrl_t * l_get_ctrl(lua_State *L, int index)
{
	if (luaL_testudata(L, 1, LUAT_NW_CTRL_TYPE))
	{
		return ((luat_socket_ctrl_t *)luaL_checkudata(L, 1, LUAT_NW_CTRL_TYPE));
	}
	else
	{
		return ((luat_socket_ctrl_t *)lua_touserdata(L, 1));
	}
}

// __gc
static int l_socket_gc(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
    if (l_ctrl->netc)
    {
    	network_force_close_socket(l_ctrl->netc);
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
@api    socket.create(adapter, cb)
@int 适配器序号， 只能是socket.ETH0，socket.STA，socket.AP，如果不填，会选择最后一个注册的适配器
@string or function string为消息通知的taskName，function则为回调函数，如果固件没有内置sys_wait，则必须是function
当通过回调函数回调消息时，输入给function一共3个参数：
param1为申请的network_ctrl
param2为具体的消息，只能是socket.RESET, socket.LINK, socket.ON_LINE, socket.TX_OK, socket.RX_NEW, socket.CLOSE等等
param3为消息对应的参数
@return some 成功返回network_ctrl，失败返回nil
@usage
local netc = socket.create(socket.ETH0, socket_cb_fun)	--以太网网卡上申请一个network_ctrl,通过socket_cb_fun回调相关消息
local netc = socket.create(socket.ETH0, "IOT_TASK")	--以太网网卡上申请一个network_ctrl,通过sendMsg方式通知taskName为"IOT_TASK"回调相关消息

*/
static int l_socket_create(lua_State *L)
{
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY)
	{
		lua_pushnil(L);
		return 1;
	}

	luat_socket_ctrl_t *l_ctrl = (luat_socket_ctrl_t *)lua_newuserdata(L, sizeof(luat_socket_ctrl_t));
	if (!l_ctrl)
	{
		lua_pushnil(L);
		return 1;
	}
	l_ctrl->adapter_index = adapter_index;
	l_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!l_ctrl->netc)
	{
		LLOGD("create fail");
		lua_pushnil(L);
		return 1;
	}
	network_init_ctrl(l_ctrl->netc, NULL, luat_lib_socket_callback, l_ctrl);
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
	luaL_setmetatable(L, LUAT_NW_CTRL_TYPE);
	return 1;
}

/*
配置是否打开debug信息
@api socket.debug(ctrl, onoff)
@user_data socket.create得到的ctrl
@boolean true 打开debug开关
@return nil 无返回值
@usage socket.debug(ctrl, true)
*/
static int l_socket_set_debug(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	if (lua_isboolean(L, 2))
	{
		l_ctrl->netc->is_debug = lua_toboolean(L, 2);
	}
	return 0;
}

/*
配置network一些信息，
@api socket.config(ctrl, local_port, is_udp, is_tls, keep_idle, keep_interval, keep_cnt, server_cert, client_cert, client_key, client_password)
@user_data socket.create得到的ctrl
@int 本地端口号，小端格式，如果不写，则自动分配一个，如果用户填了端口号则需要小于60000, 默认不写
@boolean 是否是UDP，默认false
@boolean 是否是加密传输，默认false
@int tcp keep live模式下的idle时间，如果留空则表示不启用，如果是不支持标准posix接口的网卡（比如W5500），则为心跳间隔
@int tcp keep live模式下的探测间隔时间
@int tcp keep live模式下的探测次数
@string TCP模式下的服务器ca证书数据，UDP模式下的PSK，不需要加密传输写nil，后续参数也全部nil
@string TCP模式下的客户端ca证书数据，UDP模式下的PSK-ID，TCP模式下如果不需要验证客户端证书时，忽略，一般不需要验证客户端证书
@string TCP模式下的客户端私钥加密数据
@string TCP模式下的客户端私钥口令数据
@return nil 无返回值
@usage socket.config(ctrl)	--最普通的TCP传输
socket.config(ctrl, nil, nil ,true)	--最普通的加密TCP传输，证书都不用验证的那种
*/
static int l_socket_config(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	uint8_t is_udp = 0;
	uint8_t is_tls = 0;
	int param_pos = 1;
	uint32_t keep_idle, keep_interval, keep_cnt;

	const char *server_cert = NULL;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	size_t server_cert_len, client_cert_len, client_key_len, client_password_len;

	uint16_t local_port = luaL_optinteger(L, ++param_pos, 0);
	if (lua_isboolean(L, ++param_pos))
	{
		is_udp = lua_toboolean(L, param_pos);
	}
	if (lua_isboolean(L, ++param_pos))
	{
		is_tls = lua_toboolean(L, param_pos);
	}
	keep_idle = luaL_optinteger(L, ++param_pos, 0);
	keep_interval = luaL_optinteger(L, ++param_pos, 0);
	keep_cnt = luaL_optinteger(L, ++param_pos, 0);
	if (lua_isstring(L, ++param_pos))
	{
		server_cert_len = 0;
		server_cert = luaL_checklstring(L, param_pos, &server_cert_len);
	}
	if (lua_isstring(L, ++param_pos))
	{
		client_cert_len = 0;
		client_cert = luaL_checklstring(L, param_pos, &client_cert_len);
	}

	if (lua_isstring(L, ++param_pos))
	{
		client_key_len = 0;
		client_key = luaL_checklstring(L, param_pos, &client_key_len);
	}
	if (lua_isstring(L, ++param_pos))
	{
		client_password_len = 0;
		client_password = luaL_checklstring(L, param_pos, &client_password_len);
	}
	network_set_base_mode(l_ctrl->netc, !is_udp, 10000, keep_idle, keep_idle, keep_interval, keep_cnt);
	network_set_local_port(l_ctrl->netc, local_port);
	if (is_tls)
	{
		network_init_tls(l_ctrl->netc, (server_cert || client_cert)?2:0);
		if (is_udp)
		{
			network_set_psk_info(l_ctrl->netc, server_cert, server_cert_len, client_key, client_key_len);
		}
		else
		{
			if (server_cert)
			{
				network_set_server_cert(l_ctrl->netc, server_cert, server_cert_len);
			}
			if (client_cert)
			{
				network_set_client_cert(l_ctrl->netc, client_cert, client_cert_len,
						client_key, client_key_len,
						client_password, client_password_len);
			}
		}
	}
	else
	{
		network_deinit_tls(l_ctrl->netc);
	}
	return 0;
}

/*
等待网卡linkup
@api socket.linkup(ctrl)
@user_data socket.create得到的ctrl
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了
@return boolean true已经linkup，false没有linkup，之后需要接收socket.LINK消息
@usage local error, result = socket.linkup(ctrl)
*/
static int l_socket_linkup(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_wait_link_up(l_ctrl->netc, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;


}

/*
作为客户端连接服务器
@api socket.connect(ctrl, ip, remote_port)
@user_data socket.create得到的ctrl
@string or int ip或者域名，如果是IPV4，可以是大端格式的int值
@int 服务器端口号，小端格式
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return boolean true已经connect，false没有connect，之后需要接收socket.ON_LINE消息
@usage local error, result = socket.connect(ctrl, "xxx.xxx.xxx.xxx", xxxx)
*/
static int l_socket_connect(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	luat_ip_addr_t ip_addr;
	const char *ip;
	size_t ip_len;
	ip_addr.is_ipv6 = 0xff;
	if (lua_isinteger(L, 2))
	{
		ip_addr.is_ipv6 = 0;
		ip_addr.ipv4 = lua_tointeger(L, 2);
		ip = NULL;
		ip_len = 0;
	}
	else
	{
		ip_len = 0;
	    ip = luaL_checklstring(L, 2, &ip_len);
	}
	uint16_t remote_port = luaL_checkinteger(L, 3);
	int result = network_connect(l_ctrl->netc, ip, ip_len, ip_addr.is_ipv6?NULL:&ip_addr, remote_port, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
作为客户端断开连接
@api socket.discon(ctrl)
@user_data socket.create得到的ctrl
@return
boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了
boolean true已经断开，false没有断开，之后需要接收socket.CLOSED消息
@usage local error, result = socket.discon(ctrl)
*/
static int l_socket_disconnect(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_close(l_ctrl->netc, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
强制关闭socket
@api socket.close(ctrl)
@user_data socket.create得到的ctrl
*/
static int l_socket_close(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	network_force_close_socket(l_ctrl->netc);
	return 0;
}

/*
发送数据给对端
@api socket.tx(ctrl, data, ip, port, flag)
@user_data socket.create得到的ctrl
@string or user_data zbuff  要发送的数据
@string or int 对端IP，如果是TCP应用则忽略，如果是UDP，如果留空则用connect时候的参数，如果是IPV4，可以是大端格式的int值
@int 对端端口号，小端格式，如果是TCP应用则忽略，如果是UDP，如果留空则用connect时候的参数
@int 发送参数，目前预留，不起作用
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return boolean true缓冲区满了，false没有异常，如果true，则需要等待一段时间或者等到socket.TX_OK消息后再尝试发送，同时忽略下一个返回值
@return boolean true已经收到应答，false没有收到应答，之后需要接收socket.TX_OK消息， 也可以忽略继续发送，直到full==true
@usage local error, full, result = socket.tx(ctrl, "123456", "xxx.xxx.xxx.xxx", xxxx)
*/
static int l_socket_tx(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	luat_ip_addr_t ip_addr;
	luat_zbuff_t *buff = NULL;
	const char *ip;
	const char *data;
	size_t ip_len, data_len;
	ip_addr.is_ipv6 = 0xff;
	if (lua_isstring(L, 2))
	{
		data_len = 0;
		data = luaL_checklstring(L, 2, &data_len);
	}
	else
	{
		buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
		data = buff->addr;
		data_len = buff->used;
	}
	if (lua_isinteger(L, 3))
	{
		ip_addr.is_ipv6 = 0;
		ip_addr.ipv4 = lua_tointeger(L, 3);
	}
	else if (lua_isstring(L, 3))
	{
		ip_len = 0;
	    ip = luaL_checklstring(L, 3, &ip_len);

		if (network_string_is_ipv4(ip, ip_len))
		{
			ip_addr.is_ipv6 = 0;
			ip_addr.ipv4 = network_string_to_ipv4(ip, ip_len);
		}
		else
		{
			char *name = luat_heap_malloc(ip_len + 1);
			memcpy(name, ip, ip_len);
			name[ip_len] = 0;
			network_string_to_ipv6(name, &ip_addr);
			free(name);
		}
	}
	uint32_t tx_len;
	int result = network_tx(l_ctrl->netc, data, data_len, luaL_optinteger(L, 5, 0), (ip_addr.is_ipv6 != 0xff)?&ip_addr:NULL, luaL_optinteger(L, 4, 0), &tx_len, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, tx_len != data_len);
	lua_pushboolean(L, result == 0);
	return 3;
}

/*
接收对端发出的数据，注意数据已经缓存在底层，使用本函数只是提取出来，UDP模式下一次只会取出一个数据包
@api socket.rx(ctrl, buff, flag)
@user_data socket.create得到的ctrl
@user_data zbuff 存放接收的数据，如果缓冲区不够大会自动扩容
@int 接收参数，目前预留，不起作用
@return boolean true有异常发生，false没有异常，如果有异常，后续要close
@return int 本次接收到数据长度
@return string 对端IP，只有UDP模式下才有意义，TCP模式返回nil，注意返回的格式，如果是IPV4，1byte 0x00 + 4byte地址 如果是IPV6，1byte 0x01 + 16byte地址
@return int 对端port，只有UDP模式下才有意义，TCP模式返回0
@usage local error, data_len, ip, port = socket.rx(ctrl, buff)
*/
static int l_socket_rx(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));

	luat_ip_addr_t ip_addr;
	uint8_t ip[17];
	uint16_t port;
	uint8_t new_flag = 0;
	int rx_len;
	int total_len;
	int result = network_rx(l_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (result < 0)
	{
		lua_pushboolean(L, 1);
		lua_pushinteger(L, 0);
		lua_pushnil(L);
		lua_pushnil(L);
	}
	else if (!total_len)
	{
		lua_pushboolean(L, 0);
		lua_pushinteger(L, 0);
		lua_pushnil(L);
		lua_pushnil(L);
	}
	else
	{
		if ((buff->len - buff->used) < total_len)
		{
			__zbuff_resize(buff, total_len + buff->used);
		}
		result = network_rx(l_ctrl->netc, buff->addr + buff->used, total_len, 0, &ip_addr, &port, &rx_len);
		if (result < 0)
		{
			lua_pushboolean(L, 1);
			lua_pushinteger(L, 0);
			lua_pushnil(L);
			lua_pushnil(L);
		}
		else if (!rx_len)
		{
			lua_pushboolean(L, 0);
			lua_pushinteger(L, 0);
			lua_pushnil(L);
			lua_pushnil(L);
		}
		else
		{
			buff->used += rx_len;
			lua_pushboolean(L, 0);
			lua_pushinteger(L, rx_len);
			if (l_ctrl->netc->is_tcp)
			{
				lua_pushnil(L);
				lua_pushnil(L);
			}
			else
			{
				if (!ip_addr.is_ipv6)
				{
					ip[0] = 0;
					memcpy(ip + 1, &ip_addr.ipv4, 4);
					lua_pushlstring(L, ip, 5);
				}
				else
				{
					ip[0] = 1;
					memcpy(ip + 1, &ip_addr.ipv6_u8_addr, 16);
					lua_pushlstring(L, ip, 17);
				}
				lua_pushinteger(L, port);
			}
		}
	}
	return 4;
}

/*
等待新的socket消息，在连接成功和发送数据成功后，使用一次将network状态转换到接收新数据
@api socket.wait(ctrl)
@user_data socket.create得到的ctrl
@return boolean true有异常发生，false没有异常，如果有异常，后续要close
@return boolean true有新的数据需要接收，false没有数据，之后需要接收socket.EVENT消息
@usage local error, result = socket.wait(ctrl)
*/
static int l_socket_wait(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_wait_event(l_ctrl->netc, NULL, 0, NULL);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
作为服务端开始监听
@api socket.listen(ctrl)
@user_data socket.create得到的ctrl
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return boolean true已经connect，false没有connect，之后需要接收socket.ON_LINE消息
@usage local error, result = socket.listen(ctrl)
*/
static int l_socket_listen(lua_State *L)
{
	luat_socket_ctrl_t *l_ctrl = l_get_ctrl(L, 1);
	int result = network_listen(l_ctrl->netc, 0);
	lua_pushboolean(L, result < 0);
	lua_pushboolean(L, result == 0);
	return 2;
}

/*
作为服务端接收到一个新的客户端，注意，如果是类似W5500的硬件协议栈不支持1对多，则不需要第二个参数
@api socket.accept(ctrl)
@user_data socket.create得到的ctrl，这里是服务器端
@string or function or nil string为消息通知的taskName，function则为回调函数，和socket.create参数一致
@return boolean true有异常发生，false没有异常，如果有error则不需要看下一个返回值了，如果有异常，后续要close
@return user_data or nil 如果支持1对多，则会返回新的ctrl，自动create，如果不支持则返回nil
@usage local error, new_netc = socket.listen(ctrl, cb)
*/
static int l_socket_accept(lua_State *L)
{
	luat_socket_ctrl_t *old_ctrl = l_get_ctrl(L, 1);
	if (network_accept_enable(old_ctrl->netc))
	{
		luat_socket_ctrl_t *new_ctrl = (luat_socket_ctrl_t *)lua_newuserdata(L, sizeof(luat_socket_ctrl_t));
		if (!new_ctrl)
		{
			lua_pushboolean(L, 0);
			lua_pushnil(L);
			return 2;
		}
		new_ctrl->adapter_index = old_ctrl->adapter_index;
		new_ctrl->netc = network_alloc_ctrl(old_ctrl->adapter_index);
		if (!new_ctrl->netc)
		{
			LLOGD("create fail");
			lua_pushboolean(L, 0);
			lua_pushnil(L);
			return 2;
		}
		network_init_ctrl(new_ctrl->netc, NULL, luat_lib_socket_callback, new_ctrl);
		if (lua_isfunction(L, 2))
		{
			lua_pushvalue(L, 2);
			new_ctrl->cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
			new_ctrl->task_name = NULL;
		}
		else if (lua_isstring(L, 2))
		{
			new_ctrl->cb_ref = 0;
			size_t len;
			const char *buf;
			buf = lua_tolstring(L, 2, &len);//取出字符串数据
			new_ctrl->task_name = luat_heap_malloc(len + 1);
			memset(new_ctrl->task_name, 0, len + 1);
			memcpy(new_ctrl->task_name, buf, len);
		}
		if (network_socket_accept(old_ctrl, new_ctrl))
		{
			lua_pushboolean(L, 0);
			lua_pushnil(L);
			return 2;
		}
		else
		{
			lua_pushboolean(L, 1);
			luaL_setmetatable(L, LUAT_NW_CTRL_TYPE);
			return 2;
		}

	}
	else
	{
		lua_pushboolean(L, !network_socket_accept(old_ctrl->netc, NULL));
		lua_pushnil(L);
		return 2;
	}
}

/*
主动释放掉network_ctrl
@api    socket.release(ctrl)
@user_data	socket.create得到的ctrl
@usage socket.release(ctrl)
*/
static int l_socket_release(lua_State *L)
{
	return l_socket_gc(L);
}

/*
设置DNS服务器
@api    socket.setDNS(adapter_index, dns_index, ip)
@int 适配器序号， 只能是socket.ETH0，socket.STA，socket.AP，如果不填，会选择最后一个注册的适配器
@int dns服务器序号，从1开始
@string or int dns，如果是IPV4，可以是大端格式的int值
@return boolean 成功返回true，失败返回false
@usage socket.setDNS(socket.ETH0, 1, "114.114.114.114")
*/
static int l_socket_set_dns(lua_State *L)
{
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
	int dns_index = luaL_optinteger(L, 2, 1);
	luat_ip_addr_t ip_addr;
	const char *ip;
	size_t ip_len;
	ip_addr.is_ipv6 = 0xff;
	if (lua_isinteger(L, 3))
	{
		ip_addr.is_ipv6 = 0;
		ip_addr.ipv4 = lua_tointeger(L, 3);
		ip = NULL;
		ip_len = 0;
	}
	else
	{
		ip_len = 0;
	    ip = luaL_checklstring(L, 3, &ip_len);
	    ip_addr.is_ipv6 = !network_string_is_ipv4(ip, ip_len);
	    if (ip_addr.is_ipv6)
	    {
	    	char *temp = luat_heap_malloc(ip_len + 1);
	    	memcpy(temp, ip, ip_len);
	    	temp[ip_len] = 0;
	    	network_string_to_ipv6(temp, &ip_addr);
	    	luat_heap_free(temp);
	    }
	    else
	    {
	    	ip_addr.ipv4 = network_string_to_ipv4(ip, ip_len);
	    }
	}
	network_set_dns_server(adapter_index, dns_index - 1, &ip_addr);
	lua_pushboolean(L, 1);
	return 1;
}

/*
设置SSL的log
@api    socket.sslLog(log_level)
@int	mbedtls log等级，<=2基本不打印，不要超过9
@usage socket.sslLog(3)
*/
static int l_socket_set_ssl_log(lua_State *L)
{
	mbedtls_debug_set_threshold(luaL_optinteger(L, 1, 1));
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_socket_adapter[] =
{
	{"create",			ROREG_FUNC(l_socket_create)},
	{"debug",		ROREG_FUNC(l_socket_set_debug)},
	{"config",		ROREG_FUNC(l_socket_config)},
	{"linkup",			ROREG_FUNC(l_socket_linkup)},
	{"connect",			ROREG_FUNC(l_socket_connect)},
	{"listen",			ROREG_FUNC(l_socket_listen)},
	{"accept",			ROREG_FUNC(l_socket_accept)},
	{"discon",			ROREG_FUNC(l_socket_disconnect)},
	{"close",			ROREG_FUNC(l_socket_close)},
	{"tx",			ROREG_FUNC(l_socket_tx)},
	{"rx",			ROREG_FUNC(l_socket_rx)},
	{"wait",			ROREG_FUNC(l_socket_wait)},
	//{"listen",			ROREG_FUNC(l_socket_listen)},
	//{"accept",			ROREG_FUNC(l_socket_accept)},
	{"release",			ROREG_FUNC(l_socket_release)},
	{ "setDNS",           ROREG_FUNC(l_socket_set_dns)},
	{ "sslLog",			ROREG_FUNC(l_socket_set_ssl_log)},
    //@const ETH0 number ETH0
    { "ETH0",           ROREG_INT(NW_ADAPTER_INDEX_ETH0)},
    //@const LINK number LINK事件
    { "LINK",           ROREG_INT(EV_NW_RESULT_LINK & 0x0fffffff)},
    //@const ON_LINE number ON_LINE事件
	{ "ON_LINE",          	ROREG_INT(EV_NW_RESULT_CONNECT & 0x0fffffff)},
    //@const EVENT number EVENT事件
	{ "EVENT",          	ROREG_INT(EV_NW_RESULT_EVENT & 0x0fffffff)},
    //@const TX_OK number TX_OK事件
	{ "TX_OK",     		ROREG_INT(EV_NW_RESULT_TX & 0x0fffffff)},
    //@const CLOSED number CLOSED事件
	{ "CLOSED",     		ROREG_INT(EV_NW_RESULT_CLOSE & 0x0fffffff)},
	{ NULL,            ROREG_INT(0)}
};
#endif

LUAMOD_API int luaopen_socket_adapter( lua_State *L ) {
    luat_newlib2(L, reg_socket_adapter);
    luaL_newmetatable(L, LUAT_NW_CTRL_TYPE); /* create metatable for file handles */
    lua_pushcfunction(L, l_socket_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1); /* pop new metatable */
    return 1;
}
#endif
