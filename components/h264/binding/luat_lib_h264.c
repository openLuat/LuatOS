/*
 * LuatOS Lua binding for the H.264 decoder library.
 *
 * API:
 *   h264.create()                    -> decoder_handle (userdata)
 *   h264.destroy(dec)
 *   h264.decode_nal(dec, nal_data)   -> frame_table or nil, err_msg
 *   h264.decode_stream(dec, data)    -> frame_table or nil, err_msg
 *
 * Frame table fields:
 *   frame.width, frame.height
 *   frame.y  (string: raw luma bytes, stride == width)
 *   frame.cb (string: raw Cb bytes)
 *   frame.cr (string: raw Cr bytes)
 */

/* Use standard libc when luat_base.h is unavailable (e.g. test builds). */
#ifdef LUAT_BUILD
#include "luat_base.h"
#include "luat_malloc.h"
#define H264_MALLOC luat_heap_malloc
#define H264_FREE   luat_heap_free
#else
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdlib.h>
#define H264_MALLOC malloc
#define H264_FREE   free
#endif

#include "h264_decoder.h"
#include "../src/h264_common.h"
#include <string.h>

/* Metatable name for the decoder userdata */
#define H264_META "h264.decoder"

/* Wrapper struct stored as Lua userdata */
typedef struct {
    H264Decoder *dec;
} LuaH264Decoder;

/* ---- error message helper ---- */
static const char *h264_strerror(int code)
{
    switch (code) {
    case  0: return "ok";
    case -1: return "out of memory";
    case -2: return "invalid bitstream";
    case -3: return "unsupported feature";
    case -4: return "invalid parameter";
    default: return "unknown error";
    }
}

/* ---- h264.create() ---- */
static int l_h264_create(lua_State *L)
{
    LuaH264Decoder *ud = (LuaH264Decoder *)lua_newuserdata(L, sizeof(LuaH264Decoder));
    ud->dec = h264_decoder_create();
    if (!ud->dec) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, "out of memory");
        return 2;
    }
    luaL_getmetatable(L, H264_META);
    lua_setmetatable(L, -2);
    return 1;
}

/* ---- h264.destroy(dec) ---- */
static int l_h264_destroy(lua_State *L)
{
    LuaH264Decoder *ud = (LuaH264Decoder *)luaL_checkudata(L, 1, H264_META);
    if (ud->dec) {
        h264_decoder_destroy(ud->dec);
        ud->dec = NULL;
    }
    return 0;
}

/* __gc metamethod */
static int l_h264_gc(lua_State *L)
{
    return l_h264_destroy(L);
}

/* ---- Push a decoded frame as a Lua table ---- */
static void push_frame(lua_State *L, const H264Frame *frame)
{
    lua_newtable(L);

    lua_pushinteger(L, frame->width);  lua_setfield(L, -2, "width");
    lua_pushinteger(L, frame->height); lua_setfield(L, -2, "height");

    /* Luma plane (width * height bytes) */
    {
        int rows = frame->height;
        int cols = frame->width;
        size_t total = (size_t)(rows * cols);
        luaL_Buffer b;
        luaL_buffinitsize(L, &b, total);
        int i;
        for (i = 0; i < rows; i++) {
            luaL_addlstring(&b, (const char *)(frame->y + i * frame->y_stride), (size_t)cols);
        }
        luaL_pushresult(&b);
        lua_setfield(L, -2, "y");
    }

    /* Chroma planes (width/2 * height/2 bytes each) */
    {
        int rows = (frame->height + 1) / 2;
        int cols = (frame->width  + 1) / 2;
        size_t total = (size_t)(rows * cols);

        luaL_Buffer b;
        luaL_buffinitsize(L, &b, total);
        int i;
        for (i = 0; i < rows; i++) {
            luaL_addlstring(&b, (const char *)(frame->cb + i * frame->c_stride), (size_t)cols);
        }
        luaL_pushresult(&b);
        lua_setfield(L, -2, "cb");

        luaL_buffinitsize(L, &b, total);
        for (i = 0; i < rows; i++) {
            luaL_addlstring(&b, (const char *)(frame->cr + i * frame->c_stride), (size_t)cols);
        }
        luaL_pushresult(&b);
        lua_setfield(L, -2, "cr");
    }
}

/* ---- h264.decode_nal(dec, nal_data) ---- */
static int l_h264_decode_nal(lua_State *L)
{
    LuaH264Decoder *ud = (LuaH264Decoder *)luaL_checkudata(L, 1, H264_META);
    if (!ud->dec) {
        lua_pushnil(L);
        lua_pushstring(L, "decoder destroyed");
        return 2;
    }

    size_t data_len;
    const char *data = luaL_checklstring(L, 2, &data_len);

    H264Frame frame;
    memset(&frame, 0, sizeof(frame));

    int ret = h264_decode_nal(ud->dec, (const uint8_t *)data, (int)data_len, &frame);
    if (ret != 0) {
        lua_pushnil(L);
        lua_pushstring(L, h264_strerror(ret));
        return 2;
    }

    if (!frame.is_valid) {
        lua_pushnil(L);
        lua_pushstring(L, "no frame output (SPS/PPS/SEI unit)");
        return 2;
    }

    push_frame(L, &frame);
    return 1;
}

/* ---- h264.decode_stream(dec, stream_data) ---- */
static int l_h264_decode_stream(lua_State *L)
{
    LuaH264Decoder *ud = (LuaH264Decoder *)luaL_checkudata(L, 1, H264_META);
    if (!ud->dec) {
        lua_pushnil(L);
        lua_pushstring(L, "decoder destroyed");
        return 2;
    }

    size_t data_len;
    const char *data = luaL_checklstring(L, 2, &data_len);

    H264Frame frame;
    memset(&frame, 0, sizeof(frame));

    int ret = h264_decode_stream(ud->dec, (const uint8_t *)data, (int)data_len, &frame);
    if (ret != 0 && ret != H264_ERR_BITSTREAM) {
        lua_pushnil(L);
        lua_pushstring(L, h264_strerror(ret));
        return 2;
    }

    if (!frame.is_valid) {
        lua_pushnil(L);
        lua_pushstring(L, "no frame decoded");
        return 2;
    }

    push_frame(L, &frame);
    return 1;
}

/* ---- Module registration ---- */
static const luaL_Reg h264_lib[] = {
    {"create",        l_h264_create},
    {"destroy",       l_h264_destroy},
    {"decode_nal",    l_h264_decode_nal},
    {"decode_stream", l_h264_decode_stream},
    {NULL, NULL}
};

LUAMOD_API int luaopen_h264(lua_State *L)
{
    /* Create metatable for decoder userdata */
    luaL_newmetatable(L, H264_META);
    lua_pushcfunction(L, l_h264_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_h264_destroy);
    lua_setfield(L, -2, "__close");
    lua_pop(L, 1);

    luaL_newlib(L, h264_lib);
    return 1;
}
