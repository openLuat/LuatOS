
/*
@module  multimedia
@summary 多媒体
@version 1.0
@date    2022.03.11
*/
#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "multimedia"
#include "luat_log.h"

#define MAX_DEVICE_COUNT 2

typedef struct luat_multimedia_cb {
    int function_ref;
} luat_multimedia_cb_t;

static luat_multimedia_cb_t multimedia_cbs[MAX_DEVICE_COUNT];

int l_multimedia_raw_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    if (multimedia_cbs[msg->arg2].function_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, multimedia_cbs[msg->arg2].function_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, msg->arg2);
            lua_pushinteger(L, msg->arg1);
            lua_call(L, 2, 0);
        }
    }
    lua_pushinteger(L, 0);
    return 1;
}

/*
启动一个多媒体通道准备播放音频
@api audio.start(id, AudioFormat, NumChannels, SampleRate, BitsPerSample)
@int 多媒体播放通道号，0或者1
@int 音频格式
@int 声音通道数
@int 采样频率
@int 采样位数
@boolean 是否有符号，默认true
@return boolean 成功true, 失败false
@usage
audio.start(0, audio.PCM, 1, 16000, 16)
*/

static int l_audio_start_raw(lua_State *L){
	int multimedia_id = luaL_checkinteger(L, 1);
	int audio_format = luaL_checkinteger(L, 2);
	int num_channels= luaL_checkinteger(L, 3);
	int sample_rate = luaL_checkinteger(L, 4);
	int bits_per_sample = luaL_checkinteger(L, 5);
	int is_signed = 1;
	if (lua_isboolean(L, 6))
	{
		is_signed = lua_toboolean(L, 6);
	}
	lua_pushboolean(L, !luat_audio_start_raw(multimedia_id, audio_format, num_channels, sample_rate, bits_per_sample, is_signed));
    return 1;
}
/**
往一个多媒体通道写入音频数据
@api audio.write(id, data)
@string 音频数据
@return boolean 成功返回true,否则返回false
@usage
audio.write(0, "xxxxxx")
*/
static int l_audio_write_raw(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
    size_t len;
    uint8_t *buf;
    if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        len = buff->len - buff->cursor;
        buf = (const char *)(buff->addr + buff->cursor);
    }
    else
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
    }
	lua_pushboolean(L, !luat_audio_write_raw(multimedia_id, buf, len));
    return 1;
}

/**
停止指定的多媒体通道
@api audio.stop(id)
@int audio id,例如0
@return boolean 成功返回true,否则返回false
@usage
audio.stop(0)
*/
static int l_audio_stop_raw(lua_State *L) {
    lua_pushboolean(L, !luat_audio_stop_raw(luaL_checkinteger(L, 1)));
    return 1;
}

/**
暂停/恢复指定的多媒体通道
@api audio.pause(id, pause)
@int audio id,例如0
@boolean
@return boolean 成功返回true,否则返回false
@usage
audio.pause(0, true) --暂停通道0
audio.pause(0, false) --恢复通道0
*/
static int l_audio_pause_raw(lua_State *L) {
    lua_pushboolean(L, !luat_audio_pause_raw(luaL_checkinteger(L, 1), lua_toboolean(L, 2)));
    return 1;
}

/*
注册audio播放事件回调
@api    audio.on(id, event, func)
@int audio id, audio 0写0, audio 1写1
@function 回调方法
@return nil 无返回值
@usage
camera.on(0, function(id, str)
    print(id, str)
end)
*/
static int l_audio_raw_on(lua_State *L) {
    int multimedia_id = luaL_checkinteger(L, 1);
	if (multimedia_cbs[multimedia_id].function_ref != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, multimedia_cbs[multimedia_id].function_ref);
		multimedia_cbs[multimedia_id].function_ref = 0;
	}
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		multimedia_cbs[multimedia_id].function_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_audio[] =
{
    { "start" ,       l_audio_start_raw , 0},
    { "write" ,        l_audio_write_raw, 0},
    { "pause",      l_audio_pause_raw, 0},
	{ "stop",		l_audio_stop_raw, 0},
    { "on",     l_audio_raw_on, 0},
    { "PCM",            NULL,           MULTIMEDIA_DATA_TYPE_PCM},
	{ "MORE_DATA",            NULL,           MULTIMEDIA_CB_AUDIO_NEED_DATA},
	{ "DONE",            NULL,           MULTIMEDIA_CB_AUDIO_DONE},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_multimedia_audio( lua_State *L ) {
    luat_newlib(L, reg_audio);
    return 1;
}

