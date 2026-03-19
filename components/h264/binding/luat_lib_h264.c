/*
 * LuatOS Lua binding for the H.264 decoder library.
 *
 * API:
 *   h264.create()                    -> decoder_handle (userdata)
 *   h264.destroy(dec)
 *   h264.decode_nal(dec, nal_data)   -> frame_table or nil, err_msg
 *   h264.decode_stream(dec, data)    -> frame_table or nil, err_msg
 *   h264.open_file(path)             -> file_decoder or nil, err_msg
 *   h264.open_mp4(path)              -> file_decoder or nil, err_msg
 *   h264.read_frame(fdec)            -> frame_table or nil, err_msg
 *   h264.close_file(fdec)
 *   h264.debug(on_off)               -> (void)  toggle debug output
 *
 * When LUAT_USE_LCD is defined:
 *   h264.draw_frame(fdec, x, y)      -> true or nil, err_msg
 *     Reads the next frame from a file decoder and draws it to the
 *     default LCD via luat_lcd_draw() using YUV420p→RGB565 conversion.
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
#include "../src/h264_file.h"  /* for g_h264_debug */
#include <string.h>

/* Metatable name for file-decoder userdata */
#define H264_FILE_META "h264.filedec"

/* Wrapper for H264FileDecoder Lua userdata */
typedef struct {
    H264FileDecoder *fctx;
} LuaH264FileDecoder;

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
    case -5: return "end of file";
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

/* ---- File-decoder Lua bindings ---- */

/* h264.open_file(path) → fileDecoder userdata or nil, errmsg */
static int l_h264_open_file(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    LuaH264FileDecoder *ud =
        (LuaH264FileDecoder *)lua_newuserdata(L, sizeof(LuaH264FileDecoder));
    ud->fctx = h264_open_file(path);
    if (!ud->fctx) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, "failed to open file");
        return 2;
    }
    luaL_getmetatable(L, H264_FILE_META);
    lua_setmetatable(L, -2);
    return 1;
}

/* h264.open_mp4(path) → fileDecoder userdata or nil, errmsg */
static int l_h264_open_mp4(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    LuaH264FileDecoder *ud =
        (LuaH264FileDecoder *)lua_newuserdata(L, sizeof(LuaH264FileDecoder));
    ud->fctx = h264_open_mp4(path);
    if (!ud->fctx) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, "failed to open mp4");
        return 2;
    }
    luaL_getmetatable(L, H264_FILE_META);
    lua_setmetatable(L, -2);
    return 1;
}

/* h264.read_frame(fdec) → frame table, or nil, errmsg (nil,"eof" at end) */
static int l_h264_read_frame(lua_State *L)
{
    LuaH264FileDecoder *ud =
        (LuaH264FileDecoder *)luaL_checkudata(L, 1, H264_FILE_META);
    if (!ud->fctx) {
        lua_pushnil(L);
        lua_pushstring(L, "decoder closed");
        return 2;
    }

    H264Frame frame;
    memset(&frame, 0, sizeof(frame));
    int ret = h264_read_frame(ud->fctx, &frame);

    if (ret == H264_ERR_EOF) {
        lua_pushnil(L);
        lua_pushstring(L, "eof");
        return 2;
    }
    if (ret != H264_OK) {
        lua_pushnil(L);
        lua_pushstring(L, h264_strerror(ret));
        return 2;
    }
    if (!frame.is_valid) {
        lua_pushnil(L);
        lua_pushstring(L, "no frame");
        return 2;
    }

    push_frame(L, &frame);
    return 1;
}

/* h264.close_file(fdec) */
static int l_h264_close_file(lua_State *L)
{
    LuaH264FileDecoder *ud =
        (LuaH264FileDecoder *)luaL_checkudata(L, 1, H264_FILE_META);
    if (ud->fctx) {
        h264_close_file(ud->fctx);
        ud->fctx = NULL;
    }
    return 0;
}

/* __gc for file-decoder userdata */
static int l_h264_filedec_gc(lua_State *L)
{
    return l_h264_close_file(L);
}

/* ---- h264.debug(on_off) ---- */
static int l_h264_debug(lua_State *L)
{
    g_h264_debug = lua_toboolean(L, 1);
    return 0;
}

/* ---- LCD frame output (only when LCD support is compiled in) ---- */
#ifdef LUAT_USE_LCD
#include "luat_lcd.h"

/*
 * Convert one YCbCr (4:2:0) sample to a packed RGB565 pixel.
 * Uses integer approximation of BT.601 full-range coefficients.
 */
static uint16_t yuv_to_rgb565(int y, int u, int v)
{
    int u_off = u - 128;
    int v_off = v - 128;
    int r = y + ((1435 * v_off) >> 10);
    int g = y - (( 352 * u_off + 731 * v_off) >> 10);
    int b = y + ((1814 * u_off) >> 10);
    if (r < 0) r = 0; else if (r > 255) r = 255;
    if (g < 0) g = 0; else if (g > 255) g = 255;
    if (b < 0) b = 0; else if (b > 255) b = 255;
    return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}

/*
 * h264.draw_frame(fdec, x, y)
 *
 * Reads the next frame from the file decoder @fdec and draws it to the
 * default LCD starting at pixel (x, y) using YUV420p → RGB565 conversion.
 *
 * Returns true on success, or nil + error string on failure.
 * Returns nil + "eof" when the stream is exhausted.
 */
static int l_h264_draw_frame(lua_State *L)
{
    LuaH264FileDecoder *ud =
        (LuaH264FileDecoder *)luaL_checkudata(L, 1, H264_FILE_META);
    if (!ud->fctx) {
        lua_pushnil(L);
        lua_pushstring(L, "decoder closed");
        return 2;
    }

    int16_t x = (int16_t)luaL_checkinteger(L, 2);
    int16_t y = (int16_t)luaL_checkinteger(L, 3);

    luat_lcd_conf_t *lcd = luat_lcd_get_default();
    if (!lcd) {
        lua_pushnil(L);
        lua_pushstring(L, "no lcd");
        return 2;
    }

    H264Frame frame;
    memset(&frame, 0, sizeof(frame));
    int ret = h264_read_frame(ud->fctx, &frame);

    if (ret == H264_ERR_EOF) {
        lua_pushnil(L);
        lua_pushstring(L, "eof");
        return 2;
    }
    if (ret != H264_OK || !frame.is_valid) {
        lua_pushnil(L);
        lua_pushstring(L, h264_strerror(ret));
        return 2;
    }

    int width  = frame.width;
    int height = frame.height;

    /* Allocate RGB565 buffer (2 bytes per pixel) */
    uint16_t *rgb_buf = (uint16_t *)H264_MALLOC((size_t)(width * height) * 2);
    if (!rgb_buf) {
        lua_pushnil(L);
        lua_pushstring(L, "out of memory");
        return 2;
    }

    /* YUV420p → RGB565 */
    int i, j;
    for (i = 0; i < height; i++) {
        for (j = 0; j < width; j++) {
            int yv = frame.y [i       * frame.y_stride + j      ];
            int uv = frame.cb[(i / 2) * frame.c_stride + (j / 2)];
            int vv = frame.cr[(i / 2) * frame.c_stride + (j / 2)];
            rgb_buf[i * width + j] = yuv_to_rgb565(yv, uv, vv);
        }
    }

    luat_lcd_draw(lcd, x, y,
                  (int16_t)(x + width  - 1),
                  (int16_t)(y + height - 1),
                  (luat_color_t *)rgb_buf);

    H264_FREE(rgb_buf);
    lua_pushboolean(L, 1);
    return 1;
}
#endif /* LUAT_USE_LCD */

/* ---- Module registration ---- */
static const luaL_Reg h264_lib[] = {
    {"create",        l_h264_create},
    {"destroy",       l_h264_destroy},
    {"decode_nal",    l_h264_decode_nal},
    {"decode_stream", l_h264_decode_stream},
    {"open_file",     l_h264_open_file},
    {"open_mp4",      l_h264_open_mp4},
    {"read_frame",    l_h264_read_frame},
    {"close_file",    l_h264_close_file},
    {"debug",         l_h264_debug},
#ifdef LUAT_USE_LCD
    {"draw_frame",    l_h264_draw_frame},
#endif
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

    /* Create metatable for file-decoder userdata */
    luaL_newmetatable(L, H264_FILE_META);
    lua_pushcfunction(L, l_h264_filedec_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_h264_close_file);
    lua_setfield(L, -2, "__close");
    lua_pop(L, 1);

    luaL_newlib(L, h264_lib);
    return 1;
}
