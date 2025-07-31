/*
@module  onewire
@summary 单总线协议驱动
@version 1.0
@date    2023.11.16
@author  wendal
@tag     LUAT_USE_ONEWIRE
@demo    onewire
@usage
-- 本代码库尚处于开发阶段
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_onewire.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "onewire"
#include "luat_log.h"

/*
初始化单总线
@api onewire.init(id)
@int id, 硬件单总线编号,如果只有一条则随意填写
@return nil
@usage
onewire.init(0) --初始化硬件单总线
*/
static int l_onewire_init(lua_State *L)
{
	luat_onewire_init(luaL_optinteger(L, 1, 0));
    return 0;
}

/*
配置硬件单总线时序，如果不配置，默认情况下是直接匹配DS18B20
@api onewire.timing(id, is_tick, clk_div, tRSTL, tRSTH, tPDHIGH, tPDLOW, tSLOT, tStart, tLOW1, tRDV, tREC)
@int id, 硬件单总线编号,如果只有一条则随意填写
@boolean is_tick, 后续时序参数是否是tick,true是,false不是,如果不是tick,单位就是us,默认是false.除非具体平台有特殊要求,一般是us
@int clk_div, tick参数下的分频系数,建议分频到1个tick=1个us,如果us参数,本参数忽略
@int tRSTL, reset拉低总时间
@int tRSTH, reset释放总时间
@int tPDHIGH, reset释放到开始探测时间
@int tPDLOW, reset探测时间
@int tSLOT, 通信总有效时间
@int tStart, 通信start信号时间，一般就是开头拉低
@int tLOW1, start信号到允许写的时间
@int tRDV, start信号到允许读的时间
@int tREC, 通信结束前恢复时间
@return nil
@usage
onewire.timing(0, false, 0, 500, 500, 15, 240, 65, 1, 15, 15, 2) --配置单总线时序匹配DS18B20，保留了点余量
*/
static int l_onewire_timing(lua_State *L)
{
	onewire_timing_t timing = {0};
	int id = luaL_optinteger(L, 1, 0);
	int p1 = luaL_optinteger(L, 4, 500);
	int p2 = luaL_optinteger(L, 5, 500);
	int p3 = luaL_optinteger(L, 6, 15);
	int p4 = luaL_optinteger(L, 7, 240);
	int p5 = luaL_optinteger(L, 8, 65);
	int p6 = luaL_optinteger(L, 9, 1);
	int p7 = luaL_optinteger(L, 10, 15);
	int p8 = luaL_optinteger(L, 11, 15);
	int p9 = luaL_optinteger(L, 12, 2);
	timing.type = lua_toboolean(L, 2);
	if (timing.type)
	{
		timing.timing_tick.clock_div = luaL_optinteger(L, 3, 25);
		timing.timing_tick.reset_keep_low_tick = p1;
		timing.timing_tick.reset_wait_ack_tick = p2;
		timing.timing_tick.reset_read_ack_before_tick = p3;
		timing.timing_tick.reset_read_ack_tick = p4;
		timing.timing_tick.wr_slot_tick = p5;
		timing.timing_tick.wr_start_tick = p6;
		timing.timing_tick.wr_write_start_tick = p7;
		timing.timing_tick.wr_read_start_tick = p8;
		timing.timing_tick.wr_recovery_tick = p9;
	}
	else
	{
		timing.timing_us.reset_keep_low_time = p1;
		timing.timing_us.reset_wait_ack_time = p2;
		timing.timing_us.reset_read_ack_before_time = p3;
		timing.timing_us.reset_read_ack_time = p4;
		timing.timing_us.wr_slot_time = p5;
		timing.timing_us.wr_start_time = p6;
		timing.timing_us.wr_write_start_time = p7;
		timing.timing_us.wr_read_start_time = p8;
		timing.timing_us.wr_recovery_time = p9;
	}
	luat_onewire_setup_timing(id, &timing);
    return 0;
}

/*
硬件单总线复位
@api onewire.reset(id, need_ack)
@int id, 硬件单总线编号,如果只有一条则随意填写
@boolean need_ack, 是否需要检测应答信号,true需要检测,false不需要
@return boolean 检测到应答,或者无需检测返回true,失败返回false
@usage
onewire.reset(0, true)
*/
static int l_onewire_reset(lua_State *L)
{
	lua_pushboolean(L, !luat_onewire_reset(luaL_optinteger(L, 1, 0), lua_toboolean(L, 2)));
    return 1;
}

/*
硬件单总线发送或1bit者接收1bit
@api onewire.bit(id, send1bit)
@int id, 硬件单总线编号,如果只有一条则随意填写
@int/nil send1bit, 发送bit的电平,1高电平,0低电平,留空或者其他值,则是读1bit
@return int 如果是发送,则忽略结果,如果是接收,则是接收到的电平
@usage
onewire.bit(0, 1) --发送1bit高电平
onewire.bit(0) --读取1bit数据
*/
static int l_onewire_bit(lua_State *L)
{
	int id = luaL_optinteger(L, 1, 0);
	int v = luaL_optinteger(L, 2, -1);
	switch(v)
	{
	case 0:
	case 1:
		luat_onewire_write_bit(id, v);
		break;
	default:
		v = luat_onewire_read_bit(id);
		break;
	}
	lua_pushinteger(L, v);
    return 1;
}

/*
硬件单总线发送N字节数据
@api onewire.tx(id, data, is_msb, need_reset, need_ack)
@int id, 硬件单总线编号,如果只有一条则随意填写
@int/string/zbuff data, 需要发送的数据,如果是int则是1个字节数据,如果是zbuff,则是从开头到指针前的数据,如果指针是0则发送全部数据
@boolean is_msb, 是否需要先发送MSB,true是,false不是,默认情况下都是false
@boolean need_reset, 是否需要先发送reset,true需要检测,false不需要
@boolean need_ack, 是否需要检测应答信号,true需要检测,false不需要
@return boolean 检测到应答,或者无需检测返回true,失败或者参数错误返回false
@usage
local succ = onewire.tx(0, 0x33, false, true, true) --复位并检测ACK，接收到ACK后发送0x33
local succ = onewire.tx(0, 0x33, false, true, false) --复位后发送0x33，无视从机是否ACK
local succ = onewire.tx(0, 0x33) --直接发送0x33
*/
static int l_onewire_tx(lua_State *L)
{
	int id = luaL_optinteger(L, 1, 0);
	uint8_t is_msb = lua_toboolean(L, 3);
	uint8_t need_reset = lua_toboolean(L, 4);
	uint8_t need_ack = lua_toboolean(L, 5);
	uint8_t data;
    size_t len;
    const char *buf;
	if (lua_isinteger(L, 2))
	{
		data = luaL_checkinteger(L, 2);
		lua_pushboolean(L, !luat_onewire_write_byte(id, &data, 1, is_msb, need_reset, need_ack));
	}
	else
	{
		if (lua_isuserdata(L, 2))
		{
			luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
			len = buff->used;
			buf = (const char *)(buff->addr);
		}
		else if (lua_isstring(L, 2))
		{
			buf = lua_tolstring(L, 2, &len);//取出字符串数据
		}
		else
		{
			lua_pushboolean(L, 0);
			return 1;
		}
		lua_pushboolean(L, !luat_onewire_write_byte(id, buf, len, is_msb, need_reset, need_ack));
	}
    return 1;
}

/*
硬件单总线读取N字节数据
@api onewire.rx(id, len, cmd, buff, is_msb, need_reset, need_ack)
@int id, 硬件单总线编号,如果只有一条则随意填写
@int len, 需要读取的字节数量
@int cmd, 在读取前发送命令,可以填nil不发送任何命令
@zbuff data, 接收数据缓存,接收前会清空整个缓存.如果填nil则输出字符串
@boolean is_msb, 是否需要先发送MSB,true是,false不是,默认情况下都是false
@boolean need_reset, 是否需要先发送reset,true需要检测,false不需要
@boolean need_ack, 是否需要检测应答信号,true需要检测,false不需要
@return boolean 检测到应答,或者无需检测返回true,失败或者参数错误返回false
@return string 如果data填nil,则接收数据从这里输出
@usage
local succ, rx_data = onewire.rx(0, 8) --直接接收8个字节
local succ, rx_data = onewire.rx(0, 8, 0x33, buf, nil, true, true) --先发送reset,检查ack信号,发送0x33,接收8个字节,这是DS18B20读ROM ID标准流程
*/
static int l_onewire_rx(lua_State *L)
{
	int result;
	int id = luaL_optinteger(L, 1, 0);
	size_t len = luaL_checkinteger(L, 2);
	uint8_t *rx_buff;
	luat_zbuff_t *buff = NULL;
	uint8_t is_msb = lua_toboolean(L, 5);
	uint8_t need_reset = lua_toboolean(L, 6);
	uint8_t need_ack = lua_toboolean(L, 7);
	uint8_t data;
	if (lua_isuserdata(L, 4))
	{
		buff = ((luat_zbuff_t *)luaL_checkudata(L, 4, LUAT_ZBUFF_TYPE));
		if (buff->len < len)
		{
			__zbuff_resize(buff, len);
		}
		rx_buff = buff->addr;
	}
	else
	{
		rx_buff = luat_heap_malloc(len);
	}
	if (lua_isinteger(L, 3))
	{
		data = luaL_checkinteger(L, 3);
		result = luat_onewire_read_byte_with_cmd(id, data, rx_buff, len, is_msb, need_reset, need_ack);
	}
	else
	{
		result = luat_onewire_read_byte(id, rx_buff, len, is_msb, need_reset, need_ack);
	}
	if (result)
	{
		lua_pushboolean(L, 0);
		lua_pushnil(L);
	}
	else
	{
		lua_pushboolean(L, 1);
		if (buff)
		{
			buff->used = len;
			lua_pushnil(L);
		}
		else
		{
			lua_pushlstring(L, rx_buff, len);
			luat_heap_free(rx_buff);
		}
	}
    return 2;
}

/*
单总线调试开关
@api onewire.debug(id, onoff)
@int id, GPIO模式对应GPIO编号,HW模式是硬件单总线编号,如果只有一条则随意填写
@boolean onoff, true打开,false关闭
@return nil
@usage
onewire.debug(0, true)
*/
static int l_onewire_debug(lua_State *L)
{
	luat_onewire_debug(luaL_optinteger(L, 1, 0), lua_toboolean(L, 2));
    return 0;
}

/*
关闭单总线
@api onewire.deinit(id)
@int id, 硬件单总线编号,如果只有一条则随意填写
@return nil
@usage
onewire.deinit(0) --初始化硬件单总线
*/
static int l_onewire_deinit(lua_State *L)
{
	luat_onewire_deinit(luaL_optinteger(L, 1, 0));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_onewire[] =
    {
		{"init", ROREG_FUNC(l_onewire_init)},
		{"timing", ROREG_FUNC(l_onewire_timing)},
		{"reset", ROREG_FUNC(l_onewire_reset)},
		{"bit", ROREG_FUNC(l_onewire_bit)},
		{"tx", ROREG_FUNC(l_onewire_tx)},
		{"rx", ROREG_FUNC(l_onewire_rx)},
		{"debug", ROREG_FUNC(l_onewire_debug)},
		{"deinit", ROREG_FUNC(l_onewire_deinit)},
        {NULL, ROREG_INT(0)}
    };

LUAMOD_API int luaopen_onewire(lua_State *L)
{
    luat_newlib2(L, reg_onewire);
    return 1;
}
