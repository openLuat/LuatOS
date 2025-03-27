/*
@module  i2s
@summary 数字音频
@version core V0007
@date    2022.05.26
@tag LUAT_USE_I2S
@demo    multimedia
@usage
-- 这个库属于底层适配库, 具体用法请查阅示例
-- demo/multimedia
-- demo/tts
-- demo/record
*/
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_i2s.h"
#include "luat_zbuff.h"

#ifdef LUAT_USE_I2S

#include "c_common.h"
#define LUAT_LOG_TAG "i2s"
#include "luat_log.h"
#ifndef I2S_DEVICE_MAX_CNT
#define I2S_DEVICE_MAX_CNT 2
#endif
static int i2s_cbs[I2S_DEVICE_MAX_CNT];
static luat_zbuff_t *i2s_rx_buffer[I2S_DEVICE_MAX_CNT];


int l_i2s_handler(lua_State *L, void* ptr) {
    (void)ptr;
    //LLOGD("l_uart_handler");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int i2s_id = msg->arg1;
    lua_geti(L, LUA_REGISTRYINDEX, i2s_cbs[i2s_id]);

    if (lua_isfunction(L, -1)) {
        if (msg->arg2 == 0) {
            //LLOGD("uart%ld sent callback", i2s_id);
        	lua_pushinteger(L, i2s_id);
    		lua_pushnil(L);
    		lua_call(L, 2, 0);
        }
        else {
        	lua_pushinteger(L, i2s_id);
        	lua_pushlightuserdata(L, i2s_rx_buffer[i2s_id]);
            lua_call(L, 2, 0);
        }
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

int luat_i2s_event_cb(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param){
	uint32_t len;
	rtos_msg_t msg;
	switch (event){
    case LUAT_I2S_EVENT_RX_DONE:
        if (!i2s_rx_buffer[id] || !i2s_cbs[id]){
            return -1;
        }

        len = (rx_len > i2s_rx_buffer[id]->len)?i2s_rx_buffer[id]->len:rx_len;
        memcpy(i2s_rx_buffer[id]->addr, rx_data, rx_len);
        i2s_rx_buffer[id]->used = len;
        msg.handler = l_i2s_handler;
        msg.ptr = NULL;
        msg.arg1 = id;
        msg.arg2 = len;
        luat_msgbus_put(&msg, 0);
        break;
    default:
        break;
    }
	return 0;
}

/*
初始化i2s
@api i2s.setup(id, mode, sample, bitw, channel, format, framebit)
@int i2s通道号,与具体设备有关
@int 模式, 0 主机 1 从机
@int 采样率,默认44100. 可选
@int 数据位数,默认16, 可以是8的倍数
@int 声道, 0 左声道, 1 右声道, 2 立体声. 可选
@int 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
@int 1个声道的BCLK数量, 可选16和32
@return boolean 成功与否
@return int 底层返回值
@usage
-- 以默认参数初始化i2s
i2s.setup(0)
-- 以详细参数初始化i2s, 示例为默认值
i2s.setup(0, 0, 44100, 16, 0, 0, 16)
*/
static int l_i2s_setup(lua_State *L) {
    luat_i2s_conf_t conf = {0};
    conf.id = luaL_checkinteger(L, 1);
    conf.mode = luaL_optinteger(L, 2, LUAT_I2S_MODE_MASTER);
    conf.sample_rate = luaL_optinteger(L, 3, LUAT_I2S_HZ_44k);
    conf.data_bits = luaL_optinteger(L, 4, LUAT_I2S_BITS_16);
    conf.channel_format = luaL_optinteger(L, 5, LUAT_I2S_CHANNEL_STEREO);
    conf.standard = luaL_optinteger(L, 6, LUAT_I2S_MODE_I2S);
    conf.channel_bits = luaL_optinteger(L, 7, LUAT_I2S_BITS_16);
    conf.luat_i2s_event_callback = luat_i2s_event_cb;
    int ret = luat_i2s_setup(&conf);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
发送i2s数据
@api i2s.send(id, data, len)
@int 通道id
@string 数据, 可以是字符串或zbuff
@int 数据长度,单位字节, 字符串默认为字符串全长, zbuff默认为指针位置
@return boolean 成功与否
@return int 底层返回值,供调试用
@usage
local f = io.open("/luadb/abc.wav")
while 1 do
    local data = f:read(4096)
    if not data or #data == 0 then
        break
    end
    i2s.send(0, data)
    sys.wait(100)
end
*/
static int l_i2s_send(lua_State *L) {
    char* buff;
    size_t len;
    int id = luaL_checkinteger(L, 1);
    if (lua_isuserdata(L, 2)) {
        luat_zbuff_t* zbuff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        buff = (char*)zbuff->addr;
        len = zbuff->cursor;
    }
    else {
        buff = (char*)luaL_checklstring(L, 2, &len);
    }
    if (lua_type(L, 3) == LUA_TNUMBER) {
        len = luaL_checkinteger(L, 3);
    }
    int ret = luat_i2s_send(id, buff, len);
    lua_pushboolean(L, ret == len ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/*
接收i2s数据，注意在数据在回调时已经存放在zbuff里，目前只有air780exxx系列支持
@api i2s.recv(id, buffer, len)
@int 通道id
@zbuff 数据缓存区
@int 单次返回的数据长度,单位字节,必须与传入的zbuff的大小一致
@return boolean 成功与否
@usage
local buffer = zbuff.create(3200)
local succ = i2s.recv(0, buffer, 3200);
*/
static int l_i2s_recv(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id >= I2S_DEVICE_MAX_CNT)
    {
    	lua_pushboolean(L, 0);
        return 1;
    }
    if (lua_isuserdata(L, 2)) {
        luat_zbuff_t* zbuff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        i2s_rx_buffer[id] = zbuff;
    }
    else {
    	i2s_rx_buffer[id] = NULL;
    }

    size_t len = luaL_checkinteger(L, 3);
	lua_pushboolean(L, !luat_i2s_recv(id, NULL, len));
    return 1;
}

/*
关闭i2s
@api i2s.close(id)
@int 通道id
@return nil 无返回值
@usage
i2s.close(0)
*/
static int l_i2s_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    luat_i2s_close(id);
    return 0;
}

/*
注册I2S事件回调
@api    i2s.on(id, func)
@int i2s id, i2s0写0, i2s1写1
@function 回调方法
@return nil 无返回值
@usage
i2s.on(0, function(id, buff)
	if buff then
		log.info("i2s get data in zbuff")
	else
		log.info("i2s tx one block done")
	end
end)
*/
static int l_i2s_on(lua_State *L) {
    int i2s_id = luaL_checkinteger(L, 1);
    if (i2s_id >= I2S_DEVICE_MAX_CNT)
    {
        lua_pushliteral(L, "no such i2s id");
        return 1;
    }
    if (i2s_cbs[i2s_id] != 0)
    {
    	luaL_unref(L, LUA_REGISTRYINDEX, i2s_cbs[i2s_id]);
    }
    if (lua_isfunction(L, 2)) {
        lua_pushvalue(L, 2);
        i2s_cbs[i2s_id] = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    return 0;
}

/*
获取i2s的发送缓冲区状态
@api    i2s.txStat(id)
@int i2s id, i2s0写0, i2s1写1
@return 底层缓冲区的总大小
@return 底层缓冲区的剩余待发送数据
@usage
-- 读取发送缓冲区的状态, 从而判断是否需要继续传入音频数据
local max, remain = i2s.txStat(0)
log.info("i2s发送缓冲区状态", max, remain)
*/
static int l_i2s_tx_stat(lua_State *L) {
    int i2s_id = luaL_checkinteger(L, 1);
    size_t buffsize = 0, remain = 0;
    luat_i2s_txbuff_info(i2s_id, &buffsize, &remain);
    lua_pushinteger(L, buffsize);
    lua_pushinteger(L, remain);
    return 2;
}
#if 0
/*
获取I2S参数，参数具体参考setup
@api i2s.getPara(id)
@int 通道id
@return boolean 是否在工作状态 true是
@return int 模式, 0 主机 1 从机
@return int 采样率
@return int 数据位数
@return int 声道
@return int 格式
@return int 1个声道的BCLK数量
*/
static int l_i2s_get_param(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    luat_i2s_conf_t *config = luat_i2s_get_config(id);
    lua_pushboolean(L, config->state);
    lua_pushinteger(L, config->mode);
    lua_pushinteger(L, config->sample_rate);
    lua_pushinteger(L, config->data_bits);
    lua_pushinteger(L, config->channel_format);
    lua_pushinteger(L, config->standard);
    lua_pushinteger(L, config->channel_bits);
    return 7;
}
#endif
int l_i2s_play(lua_State *L);
int l_i2s_pause(lua_State *L);
int l_i2s_stop(lua_State *L);

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int luat_i2s_txbuff_info(uint8_t id, size_t *buffsize, size_t* remain) {
    (void)id;
    (void)buffsize;
    (void)remain;
    return -1;
}
LUAT_WEAK int l_i2s_play(lua_State *L) {
    LLOGE("not support yet");
    return 0;
}

LUAT_WEAK int l_i2s_pause(lua_State *L) {
    LLOGE("not support yet");
    return 0;
}

LUAT_WEAK int l_i2s_stop(lua_State *L) {
    LLOGE("not support yet");
    return 0;
}
#endif

#include "rotable2.h"
static const rotable_Reg_t reg_i2s[] =
{
    { "setup",      ROREG_FUNC(l_i2s_setup)},
    { "send",       ROREG_FUNC(l_i2s_send)},
    { "recv",       ROREG_FUNC(l_i2s_recv)},
    { "close",      ROREG_FUNC(l_i2s_close)},
	{ "on",         ROREG_FUNC(l_i2s_on)},
    { "txStat",     ROREG_FUNC(l_i2s_tx_stat)},
#if 0
	{ "getPara",         ROREG_FUNC(l_i2s_get_param)},
#endif
    // 以下为兼容扩展功能,待定
    { "play",       ROREG_FUNC(l_i2s_play)},
    { "pause",      ROREG_FUNC(l_i2s_pause)},
    { "stop",       ROREG_FUNC(l_i2s_stop)},
	//@const MODE_I2S number I2S标准，比如ES7149
	{ "MODE_I2S", 	ROREG_INT(0)},
	//@const MODE_LSB number LSB格式
	{ "MODE_LSB", 	ROREG_INT(1)},
	//@const MODE_MSB number MSB格式，比如TM8211
	{ "MODE_MSB", 	ROREG_INT(2)},
	//@const MONO_L number 左声道
	{ "MONO_L", 	ROREG_INT(0)},
	//@const MONO_R number 右声道
	{ "MONO_R", 	ROREG_INT(1)},
	//@const STEREO number 立体声
	{ "STEREO", 	ROREG_INT(2)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_i2s(lua_State *L)
{
    luat_newlib2(L, reg_i2s);
    return 1;
}

#endif

