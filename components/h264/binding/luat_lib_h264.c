/*
@module  h264
@summary H264视频解码
@catalog 多媒体
@version 1.0
@date    2024.06.01
@demo    h264
@tag LUAT_USE_H264
@usage
-- 打开MP4文件, 逐帧解码后绘制到LCD
local fdec = h264.open_mp4("/sdcard/video.mp4")
if not fdec then
    log.error("h264", "打开MP4失败")
    return
end
h264.debug(true)
while true do
    local frame, err = h264.read_frame(fdec)
    if err == "eof" then break end
    if frame then
        log.info("h264", "帧", frame.width, frame.height)
    end
end
h264.close_file(fdec)
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

/*
创建H264解码器实例
@api h264.create()
@return userdata 解码器对象, 失败时返回nil和错误信息
@usage
local dec, err = h264.create()
if not dec then
    log.error("h264", "创建失败", err)
    return
end
*/
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

/*
销毁H264解码器, 释放内存
@api h264.destroy(dec)
@userdata dec h264.create()返回的解码器对象
@return nil 无返回值
@usage
h264.destroy(dec)
dec = nil
*/
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

/*
解码单个NAL单元(不含Annex-B起始码)
@api h264.decode_nal(dec, data)
@userdata dec h264.create()返回的解码器对象
@string data 单个NAL单元的原始字节数据, 不含起始码(0x00000001)
@return table 成功且为图像帧时返回帧数据表(含width/height/y/cb/cr字段), 否则返回nil和错误信息
@usage
-- 解码一个NAL数据包
local frame, err = h264.decode_nal(dec, nal_bytes)
if frame then
    log.info("h264", "分辨率", frame.width, frame.height)
end
*/
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

/*
解码Annex-B格式的H264码流片段, 自动查找起始码并解码NAL单元
@api h264.decode_stream(dec, data)
@userdata dec h264.create()返回的解码器对象
@string data Annex-B格式的H264码流数据(含0x00000001起始码)
@return table 成功解出图像帧时返回帧数据表(含width/height/y/cb/cr字段), 否则返回nil和错误信息
@usage
-- 从网络或文件中分段接收H264码流, 逐段解码
local frame, err = h264.decode_stream(dec, stream_chunk)
if frame then
    log.info("h264", "帧", frame.width, frame.height)
end
*/
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

/*
打开Annex-B格式的H264裸流文件(.h264/.264), 返回文件解码器对象
@api h264.open_file(path)
@string path 文件路径, 例如 "/sdcard/video.h264"
@return userdata 文件解码器对象, 失败时返回nil和错误信息
@usage
local fdec, err = h264.open_file("/sdcard/video.h264")
if not fdec then
    log.error("h264", "打开文件失败", err)
    return
end
*/
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

/*
打开MP4文件并提取H264视频轨道, 返回文件解码器对象
@api h264.open_mp4(path)
@string path MP4文件路径, 例如 "/sdcard/video.mp4"
@return userdata 文件解码器对象, 失败时返回nil和错误信息
@usage
local fdec, err = h264.open_mp4("/sdcard/video.mp4")
if not fdec then
    log.error("h264", "打开MP4失败", err)
    return
end
*/
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

/*
从文件解码器中读取并解码下一帧图像
@api h264.read_frame(fdec)
@userdata fdec h264.open_file()或h264.open_mp4()返回的文件解码器对象
@return table 成功返回帧数据表(含width/height/y/cb/cr字段), 到达文件末尾时返回nil和"eof", 出错返回nil和错误信息
@usage
-- 逐帧读取视频
while true do
    local frame, err = h264.read_frame(fdec)
    if err == "eof" then
        log.info("h264", "播放结束")
        break
    end
    if frame then
        log.info("h264", "帧", frame.width, frame.height)
        -- frame.y  亮度平面, 字符串, 长度 = width * height
        -- frame.cb 色度Cb平面, 字符串, 长度 = (width/2) * (height/2)
        -- frame.cr 色度Cr平面, 字符串, 长度 = (width/2) * (height/2)
    end
end
*/
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

/*
关闭文件解码器, 释放相关资源
@api h264.close_file(fdec)
@userdata fdec h264.open_file()或h264.open_mp4()返回的文件解码器对象
@return nil 无返回值
@usage
h264.close_file(fdec)
fdec = nil
*/
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

/*
设置调试信息输出开关, 开启后将打印MP4分辨率、解码过程等关键信息
@api h264.debug(on_off)
@boolean on_off true开启调试输出, false关闭(默认)
@return nil 无返回值
@usage
-- 开启调试, 将打印分辨率、帧序号等信息
h264.debug(true)
-- 关闭调试
h264.debug(false)
*/
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
从文件解码器读取下一帧, 将YUV420p数据转换为RGB565后绘制到默认LCD屏幕, 需开启LUAT_USE_LCD
@api h264.draw_frame(fdec, x, y)
@userdata fdec h264.open_file()或h264.open_mp4()返回的文件解码器对象
@int x 显示起始X坐标
@int y 显示起始Y坐标
@return boolean 成功返回true, 到达文件末尾返回nil和"eof", 失败返回nil和错误信息
@usage
-- 开启调试信息
h264.debug(true)
-- 打开MP4文件
local fdec = h264.open_mp4("/sdcard/video.mp4")
-- 逐帧解码并显示到LCD左上角
while true do
    local ok, err = h264.draw_frame(fdec, 0, 0)
    if err == "eof" then break end
    sys.wait(33)  -- 约30fps
end
h264.close_file(fdec)
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
