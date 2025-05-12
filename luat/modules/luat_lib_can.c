/*
@module  can
@summary can操作库
@version 1.0
@date    2025.2.24
@demo can
@tag LUAT_USE_CAN
@usage
--[[
错误码介绍
错误码由4byte组成小端格式的uint32
byte3预留无意义
byte2方向，0TX 1RX
byte1类型，0bit 1form 2stuff
byte0位置：
0x03 start of frame
0x02 extended: ID bits 28 - 21, standard:  10 - 3
0x06 extended: ID bits 20 - 18, standard:  2 - 0
0x04 extended: substitute RTR, standard: RTR
0x05 identifier extension
0x07 extended: ID bits 17 - 13
0x0f extended: ID bits 12 - 5
0x0e extended: ID bits 4 - 0
0x0C RTR
0x0D reserved bit 1
0x09 reserved bit 0
0x0b data length code
0x0a data section
0x08 CRC sequence
0x18 CRC delimiter
0x19 ACK slot
0x1b ACK delimiter
0x1a end of frame
0x12 intermission
0x00 unspecified
]]
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_can.h"
#include "luat_zbuff.h"
#include "c_common.h"
#define LUAT_LOG_TAG "can"
#include "luat_log.h"
#include "rotable2.h"
#define MAX_DEVICE_COUNT 2
static int l_can_cb[MAX_DEVICE_COUNT];
static uint8_t l_can_debug_flag;
static int l_can_handler(lua_State *L, void* ptr)
{
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int can_id = msg->arg1;
    if (l_can_debug_flag) LLOGD("callback %d,%d,%x", can_id, msg->arg2, msg->ptr);
    if (l_can_cb[can_id])
    {
    	lua_geti(L, LUA_REGISTRYINDEX, l_can_cb[can_id]);
        if (lua_isfunction(L, -1))
        {
            lua_pushinteger(L, can_id);
            switch(msg->arg2)
            {
            case LUAT_CAN_CB_NEW_MSG:
            	lua_pushinteger(L, msg->arg2);
            	lua_pushnil(L);
            	break;
            case LUAT_CAN_CB_TX_OK:
            	lua_pushinteger(L, msg->arg2);
            	lua_pushboolean(L, 1);
            	break;
            case LUAT_CAN_CB_TX_FAILED:
            	lua_pushinteger(L, LUAT_CAN_CB_TX_OK);
            	lua_pushboolean(L, 0);
            	break;
            case LUAT_CAN_CB_ERROR_REPORT:
            	lua_pushinteger(L, msg->arg2);
            	lua_pushinteger(L, (uint32_t)msg->ptr);
            	break;
            case LUAT_CAN_CB_STATE_CHANGE:
            	lua_pushinteger(L, msg->arg2);
            	lua_pushinteger(L, (uint32_t)msg->ptr);
            	break;
            }
            lua_call(L, 3, 0);
        }
    }

    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

static void l_can_callback(int can_id, LUAT_CAN_CB_E cb_type, void *cb_param)
{
    rtos_msg_t msg;
    msg.handler = l_can_handler;
    msg.ptr = cb_param;
    msg.arg1 = can_id;
    msg.arg2 = cb_type;
    luat_msgbus_put(&msg, 0);
}
/*
CAN总线初始化
@api can.init(id, rx_message_cache_max)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@int rx_message_cache_max，接收缓存消息数的最大值，写0或者留空则使用平台默认值
@return boolean 成功返回true,失败返回false
@usage
can.init()
*/
static int l_can_init(lua_State *L)
{
	int ret = luat_can_base_init(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, 0));
	if (ret)
	{
		LLOGE("init failed %d",  ret);
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}


/*
注册CAN事件回调
@api can.on(id, func)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@function 回调方法
@return nil 无返回值
@usage
can.on(1, function(id, type, param)
    log.info("can", id, type, param)
end)
*/
static int l_can_on(lua_State *L) {
    int id = luaL_optinteger(L, 1, 0);
    if (id >= MAX_DEVICE_COUNT)
    {
    	id = 0;
    }
    if (l_can_cb[id] != 0)
    {
    	luaL_unref(L, LUA_REGISTRYINDEX, l_can_cb[id]);
    }
    if (lua_isfunction(L, 2))
    {
        lua_pushvalue(L, 2);
        luat_can_set_callback(id, l_can_callback);
        l_can_cb[id] = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    else
    {
    	luat_can_set_callback(id, NULL);
    }
    return 0;
}

/*
CAN总线配置时序
@api can.timing(id, br, PTS, PBS1, PBS2, SJW)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@int br, 波特率, 默认1Mbps
@int PTS, 传播时间段, 范围1~8
@int PBS1, 相位缓冲段1，范围1~8
@int PBS2, 相位缓冲段2，范围2~8
@int SJW, 同步补偿宽度值，范围1~4，默认2
@return boolean 成功返回true,失败返回false
@usage
-- air780EPM参考，不一定适合其他平台，CAN的实际波特率=基础时钟/分频系数/(1+PTS+PBS1+PBS2)，详见can.capacity
can.timing(0, 100000, 6, 6, 3, 2)
can.timing(0, 125000, 6, 6, 4, 2)
*/
static int l_can_timing(lua_State *L)
{
	int ret = luat_can_set_timing(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, 1000000),
			luaL_optinteger(L, 3, 6), luaL_optinteger(L, 4, 6), luaL_optinteger(L, 5, 4),
			luaL_optinteger(L, 6, 2));
	if (ret)
	{
		LLOGE("set timing failed %d",  ret);
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN总线设置工作模式
@api can.mode(id, mode)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@int mode, 见MODE_XXX，默认是MODE_NORMAL
@return boolean 成功返回true,失败返回false
@usage
can.mode(0, CAN.MODE_NORMAL)
*/
static int l_can_mode(lua_State *L)
{
	int ret = luat_can_set_work_mode(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, LUAT_CAN_WORK_MODE_NORMAL));
	if (ret)
	{
		LLOGE("set mode failed %d",  ret);
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN总线设置节点ID，这是一种简易的过滤规则，只接收和ID完全匹配的消息，和can.filter选择一个使用
@api can.node(id, node_id, id_type)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@int node_id, 节点ID, 标准格式11位或者扩展格式29位，根据id_type决定，默认值是0x1fffffff，id值越小，优先级越高
@int id_type，ID类型，填1或者CAN.EXT为扩展格式，填0或者CAN.STD为标准格式
@return boolean 成功返回true,失败返回false
@usage
can.node(0, 0x12345678, CAN.EXT)
can.node(0, 0x123, CAN.STD)
*/
static int l_can_node(lua_State *L)
{

	int ret = luat_can_set_node(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, 0x1fffffff), luaL_optinteger(L, 3, 1));
	if (ret)
	{
		LLOGE("set node failed %d",  ret);
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN总线设置接收过滤模式，当can.node不满足需求时才使用这个，和can.node选择一个使用，过滤模式比较复杂，请参考SJA1000的Pelican模式下滤波
@api can.filter(id, dual_mode, ACR, AMR)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@boolean dual_mode, 是否是双过滤模式，true是，false不是，默认是false
@int ACR, 接收代码寄存器值，必须写0xnnnnnnnn这样的格式，大端格式赋值到4个ACR寄存器上，默认值是0
@int AMR, 接收屏蔽寄存器值，必须写0xnnnnnnnn这样的格式，大端格式赋值到4个AMR寄存器上，对应bit写0表示需要检测，写1表示不检测，默认是0xffffffff，不过滤全接收
@return boolean 成功返回true,失败返回false
@usage
can.filter(0, false, 0x12345678 << 3, 0x07) --效果等同于can.node(0, 0x12345678, CAN.EXT)
can.filter(0, false, 0x123 << 21, 0x0001fffff) --效果等同于can.node(0, 0x123, CAN.STD)
*/
static int l_can_filter(lua_State *L)
{
	uint32_t mask = luaL_optinteger(L, 4, 0xffffffff);
	uint32_t node_id = luaL_optinteger(L, 3, 0);
	uint8_t ACR[4];
	uint8_t AMR[4];
	uint8_t dual_mode = lua_toboolean(L,2);
    BytesPutBe32(ACR, node_id);
    BytesPutBe32(AMR, mask);
    int ret = luat_can_set_filter(luaL_optinteger(L, 1, 0), dual_mode, ACR, AMR);
	if (ret)
	{
		LLOGE("set filter failed %d",  ret);
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN工作状态
@api can.state(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return int 返回值见STATE_XXX
@usage
can.state(0)
*/
static int l_can_state(lua_State *L)
{
	lua_pushinteger(L, luat_can_get_state(luaL_optinteger(L, 1, 0)));
	return 1;
}

/*
CAN发送一条消息
@api can.tx(id, msg_id, id_type, RTR, need_ack, data)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@int msg_id, 节点ID, 标准格式11位或者扩展格式29位，根据id_type决定，默认值是0x1fffffff，id值越小，优先级越高
@int id_type, ID类型，填1或者CAN.EXT为扩展格式，填0或者CAN.STD为标准格式
@boolean RTR, 是否是遥控帧，true是，false不是，默认是false
@boolean need_ack，是否需要应答，true是，false不需要，默认是true
@string/zbuff data, 需要发送的数据, 如果是zbuff会从指针起始位置开始发送，最多发送8字节
@return boolean 成功返回true,失败返回false
@usage
can.tx(id, 0x12345678, CAN.EXT, false, true, "\x00\x01\x02\x03\0x04\x05\0x6\x07")
*/
static int l_can_tx(lua_State *L)
{
    size_t len;
    const char *buf;
	uint32_t id = luaL_optinteger(L, 2, 0x1fffffff);
    if(lua_isuserdata(L, 6))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 6, LUAT_ZBUFF_TYPE));
        len = buff->used;
        buf = (const char *)(buff->addr);
    }
    else
    {
        buf = lua_tolstring(L, 6, &len);//取出字符串数据
    }
    if (len > 8) len = 8;

	lua_pushinteger(L, luat_can_tx_message(luaL_optinteger(L, 1, 0), id, luaL_optinteger(L, 3, 0), lua_toboolean(L, 4), lua_toboolean(L, 5), len, buf));
	return 1;
}

/*
从缓存里读出一条消息
@api can.rx(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return boolean 是否读出数据，true读出，false没有读出，缓存已经空了，或者id不对
@return int 消息ID
@return int ID类型，1或者CAN.EXT为扩展格式，0或者CAN.STD为标准格式
@return boolean 是否是遥控帧，true是，false不是
@return string 数据
@usage
local succ, id, type, rtr, data = can.rx(0)
*/
static int l_can_rx(lua_State *L)
{
	luat_can_message_t msg = {0};
	int id = luaL_optinteger(L, 1, 0);
	if (luat_can_rx_message_from_cache(id, &msg) > 0)
	{
		lua_pushboolean(L, 1);
		lua_pushinteger(L, msg.id);
		lua_pushinteger(L, msg.is_extend);
		lua_pushboolean(L, msg.RTR);
		lua_pushlstring(L, (const char*)msg.data, msg.len);
	}
	else
	{
		lua_pushboolean(L, 0);
		lua_pushnil(L);
		lua_pushnil(L);
		lua_pushnil(L);
		lua_pushnil(L);
	}

	return 5;
}

/*
立刻停止当前的发送
@api can.stop(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return boolean 成功返回true,失败返回false
@usage
can.stop(0)
*/
static int l_can_stop(lua_State *L)
{
	int id = luaL_optinteger(L, 1, 0);
	if (luat_can_tx_stop(id))
	{
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN总线复位，一般用于从总线关闭状态恢复成主动错误
@api can.reset(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return boolean 成功返回true,失败返回false
@usage
can.reset(0)
*/
static int l_can_reset(lua_State *L)
{
	if (luat_can_reset(luaL_optinteger(L, 1, 0)))
	{
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}


/*
CAN总线关闭，此时可以重新进行timing,filter,node等配置
@api can.busOff(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return boolean 成功返回true,失败返回false
@usage
can.busOff(0)
*/
static int l_can_bus_off(lua_State *L)
{
	if (luat_can_bus_off(luaL_optinteger(L, 1, 0)))
	{
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN完全关闭
@api can.deinit(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return boolean 成功返回true,失败返回false
@usage
can.deinit(0)
*/
static int l_can_deinit(lua_State *L)
{
	if (luat_can_close(luaL_optinteger(L, 1, 0)))
	{
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	return 1;
}

/*
CAN debug开关，打开后有更详细的打印
@api can.debug(on_off)
@boolean true打开，false关闭
@return nil
@usage
can.debug(true)
*/
static int l_can_debug(lua_State *L)
{
	l_can_debug_flag = lua_toboolean(L, 1);
	luat_can_set_debug(l_can_debug_flag);
	return 0;
}

/*
获取CAN时钟特性，包括基础时钟,分频系数范围,CAN的实际波特率=基础时钟/分频系数/(1+PTS+PBS1+PBS2),从时钟特性里能看出对应平台是否能配置出需要的波特率
@api can.capacity(id)
@int id, 如果只有一条总线写0或者留空, 有多条的，can0写0，can1写1, 如此类推, 一般情况只有1条
@return boolean 成功返回true,失败返回false,如果失败就不用看后面的参数了
@return int 基础时钟
@return int 最小分频系数
@return int 最大分频系数
@return int 分频系数步进，一般为1
@usage
local res, clk, div_min, div_max, div_step = can.capacity(0)
*/
static int l_can_capacity(lua_State *L)
{
	uint32_t clk, div_min, div_max, div_step;
	if (luat_can_get_capacity(luaL_optinteger(L, 1, 0), &clk, &div_min, &div_max, &div_step))
	{
		lua_pushboolean(L, 0);
	}
	else
	{
		lua_pushboolean(L, 1);
	}
	lua_pushinteger(L, clk);
	lua_pushinteger(L, div_min);
	lua_pushinteger(L, div_max);
	lua_pushinteger(L, div_step);
	return 5;
}

static const rotable_Reg_t reg_can[] =
{
    { "init",			ROREG_FUNC(l_can_init)},
	{ "on",				ROREG_FUNC(l_can_on)},
	{ "timing",			ROREG_FUNC(l_can_timing)},
	{ "mode",			ROREG_FUNC(l_can_mode)},
	{ "node",			ROREG_FUNC(l_can_node)},
	{ "filter",			ROREG_FUNC(l_can_filter)},
	{ "state",			ROREG_FUNC(l_can_state)},
	{ "tx",				ROREG_FUNC(l_can_tx)},
	{ "rx",				ROREG_FUNC(l_can_rx)},
	{ "stop", 			ROREG_FUNC(l_can_stop)},
	{ "reset",			ROREG_FUNC(l_can_reset)},
	{ "busOff",			ROREG_FUNC(l_can_bus_off)},
	{ "deinit",			ROREG_FUNC(l_can_deinit)},
	{ "debug",			ROREG_FUNC(l_can_debug)},
	{ "capacity",		ROREG_FUNC(l_can_capacity)},
	//@const MODE_NORMAL number 正常工作模式
    { "MODE_NORMAL",        ROREG_INT(LUAT_CAN_WORK_MODE_NORMAL)},
	//@const MODE_LISTEN number 监听模式
    { "MODE_LISTEN",       ROREG_INT(LUAT_CAN_WORK_MODE_ONLY_LISTEN)},
	//@const MODE_TEST number 自测模式
    { "MODE_TEST",       ROREG_INT(LUAT_CAN_WORK_MODE_SELF_TEST)},
    //@const MODE_SLEEP number 休眠模式
    { "MODE_SLEEP",        ROREG_INT(LUAT_CAN_WORK_MODE_SLEEP)},
    //@const STATE_STOP number 停止工作状态
    { "STATE_STOP",       ROREG_INT(LUAT_CAN_STOP)},
    //@const STATE_ACTIVE number 主动错误状态，一般都是这个状态
    { "STATE_ACTIVE",       ROREG_INT(LUAT_CAN_ACTIVE_ERROR)},
    //@const STATE_PASSIVE number 被动错误状态，总线上错误多会进入这个状态，但是还能正常收发
    { "STATE_PASSIVE",        ROREG_INT(LUAT_CAN_PASSIVE_ERROR)},
    //@const STATE_BUSOFF number 离线状态，总线上错误非常多会进入这个状态，不能收发，需要手动退出
    { "STATE_BUSOFF",        ROREG_INT(LUAT_CAN_BUS_OFF)},
    //@const STATE_LISTEN number 监听状态，选择监听模式时进入这个状态
    { "STATE_LISTEN",        ROREG_INT(LUAT_CAN_ONLY_LISTEN)},
    //@const STATE_TEST number 自收自发状态，选择自测模式时进入这个状态
    { "STATE_TEST",        ROREG_INT(LUAT_CAN_SELF_TEST)},
	//@const STATE_SLEEP number 休眠状态，选择休眠模式时进入这个状态
	{ "STATE_SLEEP",        ROREG_INT(LUAT_CAN_SLEEP)},
    //@const CB_MSG number 回调消息类型，有新数据写入缓存
    { "CB_MSG",        ROREG_INT(LUAT_CAN_CB_NEW_MSG)},
    //@const CB_TX number 回调消息类型，数据发送结束，需要根据后续param确定发送成功还是失败
    { "CB_TX",        ROREG_INT(LUAT_CAN_CB_TX_OK)},
    //@const CB_ERR number 回调消息类型，有错误报告，后续param是错误码，具体见错误码介绍
    { "CB_ERR",        ROREG_INT(LUAT_CAN_CB_ERROR_REPORT)},
	//@const CB_STATE number 回调消息类型，总线状态变更，后续param是新的状态，也可以用can.state读出
	{ "CB_STATE",        ROREG_INT(LUAT_CAN_CB_STATE_CHANGE)},
    //@const EXT number 扩展帧
    { "EXT",        ROREG_INT(1)},
	//@const STD number 标准帧
	{ "STD",        ROREG_INT(0)},
    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_can( lua_State *L )
{
    luat_newlib2(L, reg_can);
    return 1;
}
