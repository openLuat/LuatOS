/*
@module  i2s
@summary 数字音频
@version core V0007
@date    2022.05.26
*/
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_i2s.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "i2s"
#include "luat_log.h"

/*
初始化i2s
@api i2s.setup(id, mode, sample, bitw, channel, format, mclk)
@int i2s通道号,与具体设备有关
@int 模式, 当前仅支持0, MASTER|TX|RX 模式, 暂不支持slave. 可选
@int 采样率,默认44100. 可选
@int 声道, 0 左声道, 1 右声道, 2 双声道. 可选
@int 格式, 当前仅支持i2s标准格式. 可选
@int mclk频率, 默认 8M. 可选
@return boolean 成功与否
@return int 底层返回值
@usage
-- 这个库处于开发阶段, 尚不可用
-- 以默认参数初始化i2s
i2s.setup(0)
-- 以详细参数初始化i2s, 示例为默认值
i2s.setup(0, 0, 44100, 16, 0, 0, 8000000)
*/
static int l_i2s_setup(lua_State *L) {
    luat_i2s_conf_t conf = {0};
    conf.id = luaL_checkinteger(L, 1);
    conf.mode = luaL_optinteger(L, 2, 0);
    conf.sample_rate = luaL_optinteger(L, 3, 44100); // 44.1k比较常见吧,待讨论
    conf.bits_per_sample = luaL_optinteger(L, 4, 16); // 通常就是16bit
    conf.channel_format = luaL_optinteger(L, 5, 0); // 1 右声道, 0 左声道
    conf.communication_format = luaL_optinteger(L, 6, 0); // 0 - I2S 标准, 当前只支持这种就行
    conf.mclk = luaL_optinteger(L, 7, 0);
    // conf.intr_alloc_flags = luaL_optinteger(L, 8, 0);
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
    if (lua_type(L, 3) == LUA_TINTEGER) {
        len = luaL_checkinteger(L, 3);
    }
    int ret = luat_i2s_send(id, buff, len);
    lua_pushboolean(L, ret == len ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

// 暂不支持读取
static int l_i2s_recv(lua_State *L) {
    luaL_Buffer buff;
    int id = luaL_checkinteger(L, 1);
    size_t len = luaL_checkinteger(L, 2);
    char* buff2 = luaL_buffinitsize(L, &buff, len);
    int ret = luat_i2s_recv(id, buff2, len);
    if (ret > 0)
        luaL_pushresultsize(&buff, ret);
    else {
        lua_pushstring(L, "");
    }
    lua_pushinteger(L, ret);
    return 2;
}

/*
关闭i2s
@api i2s.close(id, data, len)
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

int l_i2s_play(lua_State *L);
int l_i2s_pause(lua_State *L);
int l_i2s_stop(lua_State *L);

#ifndef LUAT_COMPILER_NOWEAK
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
    // 以下为兼容扩展功能,待定
    { "play",       ROREG_FUNC(l_i2s_play)},
    { "pause",      ROREG_FUNC(l_i2s_pause)},
    { "stop",       ROREG_FUNC(l_i2s_stop)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_i2s(lua_State *L)
{
    luat_newlib2(L, reg_i2s);
    return 1;
}

