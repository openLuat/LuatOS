/*
@module  iconv
@summary iconv操作
@catalog 外设API
@version 1.0
@date    2023.03.03
@demo iconv
@tag LUAT_USE_ICONV
*/
/*
 * luaiconv - Performs character set conversions in Lua
 * (c) 2005-08 Alexandre Erwin Ittner <aittner@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHOR OR COPYRIGHT HOLDER BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * If you use this package in a product, an acknowledgment in the product
 * documentation would be greatly appreciated (but it is not required).
 *
 * $Id: luaiconv.c 54 2008-05-19 00:37:56Z dermeister $
 *
 */


#include "lua.h"
#include "lauxlib.h"

#include "luat_base.h"
#include "luat_mem.h"

#define ICONV_TYPENAME          "iconv_t"

#define LUAT_LOG_TAG "iconv"
#include "luat_log.h"

#define boxptr(L, p)   (*(void**)(lua_newuserdata(L, sizeof(void*))) = (p))
#define unboxptr(L, i) (*(void**)(lua_touserdata(L, i)))

#define ERROR_NO_MEMORY     1
#define ERROR_INVALID       2
#define ERROR_INCOMPLETE    3
#define ERROR_UNKNOWN       4

#include "iconv.h"
#include "prv_iconv.h"

static void push_iconv_t(lua_State *L, iconv_t cd) {
    boxptr(L, cd);
    luaL_getmetatable(L, ICONV_TYPENAME);
    lua_setmetatable(L, -2);
}


static iconv_t get_iconv_t(lua_State *L, int i) {
    if (luaL_checkudata(L, i, ICONV_TYPENAME) != NULL) {
        iconv_t cd = unboxptr(L, i);
        if (cd == (iconv_t) NULL)
            luaL_error(L, "attempt to use an invalid " ICONV_TYPENAME);
        return cd;
    }
    luaL_argerror(L, i, "type not match");
    return NULL;
}

/*
打开相应字符编码转换函数
@api iconv.open(tocode, fromcode)
@string 释义：目标编码格式<br>取值：gb2312/ucs2/ucs2be/utf8
@string 释义：源编码格式<br>取值：gb2312/ucs2/ucs2be/utf8
@return userdata 编码转换函数的转换句柄,若不存在会返回nil
@usage
--unicode大端编码 转化为 utf8编码
local ic = iconv.open("utf8", "ucs2be")
*/
static int Liconv_open(lua_State *L) {
    const char *tocode = luaL_checkstring(L, 1);
    const char *fromcode = luaL_checkstring(L, 2);
    iconv_t cd = iconv_open(tocode, fromcode);
    if (cd != (iconv_t)(-1)) {
        push_iconv_t(L, cd);    /* ok */
        return 1;
    }
    return 0;
}

/*
字符编码转换
@api ic:iconv(inbuf)
@string 释义：待转换字符串
@return number 释义：返回编码转换后的结果<br>取值：0成功,-1失败
@usage
--unicode大端编码 转化为 utf8编码
function ucs2beToUtf8(ucs2s)
    local ic = iconv.open("utf8", "ucs2be")
    return ic:iconv(ucs2s)
end
*/
static int Liconv(lua_State *L) {
    iconv_t cd = get_iconv_t(L, 1);
    size_t ibleft = 0;
    char *inbuf = (char*) luaL_checklstring(L, 2, &ibleft);
    char *outbuf;
    char *outbufs;
    size_t obsize = ibleft * 2.1;
    size_t obleft = obsize;
    size_t ret = 0;

    outbuf = (char*) luat_heap_malloc(obsize * sizeof(char));
    if (outbuf == NULL) {
        lua_pushstring(L, "");
        lua_pushnumber(L, ERROR_NO_MEMORY);
        return 2;
    }
    outbufs = outbuf;
    ret = iconv_convert(cd, &inbuf, &ibleft, &outbuf, &obleft);
    if (ret == 0) {
        lua_pushlstring(L, outbufs, obsize - obleft);
    }
    else {
        lua_pushstring(L, "");
    }

    luat_heap_free(outbufs);
    return 1;   /* Done */
}



/*
关闭字符编码转换
@api iconv.close(cd) 
@userdata iconv.open返回的句柄
@return bool 成功返回true,否则返回false
@usage
--关闭字符编码转换
local cd = iconv.open("utf8", "ucs2be")
iconv.close(cd)
*/
static int Liconv_close(lua_State *L) {
    iconv_t cd = get_iconv_t(L, 1);
    if (iconv_close(cd) == 0)
        lua_pushboolean(L, 1);  /* ok */
    else
        lua_pushnil(L);         /* erro */
    return 1;
}

#include "rotable2.h"

/*
GB2312编码字符串转UTF8编码（快捷函数）
@api iconv.gb2utf8(str)
@string 待转换的GB2312编码字符串
@return string 成功返回UTF8编码字符串，失败返回nil
@usage
local utf8str = iconv.gb2utf8("\xC4\xE3\xBA\xC3")  -- 你好
log.info("iconv", "gb2utf8", utf8str)
*/
static int l_iconv_gb2utf8(lua_State *L) {
    size_t in_len = 0;
    const char *in = luaL_checklstring(L, 1, &in_len);

    if (in_len == 0) {
        lua_pushlstring(L, "", 0);
        return 1;
    }

    /* Step 1: GB2312 → UCS2 (little-endian)
       Worst case: N single-byte ASCII chars → N UCS2 chars → N*2 bytes */
    size_t ucs2_size = in_len * 2;
    char *ucs2_buf = (char *)luat_heap_malloc(ucs2_size);
    if (!ucs2_buf) {
        LLOGE("oom ucs2 buf");
        return 0;
    }

    char *in_ptr = (char *)in;
    char *ucs2_ptr = ucs2_buf;
    size_t in_left = in_len;
    size_t ucs2_left = ucs2_size;
    iconv_gb2312_to_ucs2(&in_ptr, &in_left, &ucs2_ptr, &ucs2_left);
    size_t ucs2_len = ucs2_size - ucs2_left;

    if (ucs2_len == 0) {
        luat_heap_free(ucs2_buf);
        lua_pushlstring(L, "", 0);
        return 1;
    }

    /* Step 2: UCS2 → UTF8
       Worst case: each UCS2 CJK char (0x800-0xFFFF) → 3 bytes UTF8 */
    size_t utf8_size = (ucs2_len / 2) * 3 + 1;
    char *utf8_buf = (char *)luat_heap_malloc(utf8_size);
    if (!utf8_buf) {
        luat_heap_free(ucs2_buf);
        LLOGE("oom utf8 buf");
        return 0;
    }

    char *ucs2_src = ucs2_buf;
    char *utf8_ptr = utf8_buf;
    size_t ucs2_src_left = ucs2_len;
    size_t utf8_left = utf8_size;
    iconv_ucs2_to_utf8(&ucs2_src, &ucs2_src_left, &utf8_ptr, &utf8_left);
    size_t utf8_len = utf8_size - utf8_left;

    luat_heap_free(ucs2_buf);
    lua_pushlstring(L, utf8_buf, utf8_len);
    luat_heap_free(utf8_buf);
    return 1;
}

/*
UTF8编码字符串转GB2312编码（快捷函数）
@api iconv.utf82gb(str)
@string 待转换的UTF8编码字符串
@return string 成功返回GB2312编码字符串，失败返回nil
@usage
local gbstr = iconv.utf82gb("\xE4\xBD\xA0\xE5\xA5\xBD")  -- 你好
log.info("iconv", "utf82gb", gbstr:toHex())
*/
static int l_iconv_utf82gb(lua_State *L) {
    size_t in_len = 0;
    const char *in = luaL_checklstring(L, 1, &in_len);

    if (in_len == 0) {
        lua_pushlstring(L, "", 0);
        return 1;
    }

    /* Step 1: UTF8 → UCS2 (little-endian)
       Worst case: N single-byte ASCII chars → N UCS2 chars → N*2 bytes */
    size_t ucs2_size = in_len * 2;
    char *ucs2_buf = (char *)luat_heap_malloc(ucs2_size);
    if (!ucs2_buf) {
        LLOGE("oom ucs2 buf");
        return 0;
    }

    char *in_ptr = (char *)in;
    char *ucs2_ptr = ucs2_buf;
    size_t in_left = in_len;
    size_t ucs2_left = ucs2_size;
    iconv_utf8_to_ucs2(&in_ptr, &in_left, &ucs2_ptr, &ucs2_left);
    size_t ucs2_len = ucs2_size - ucs2_left;

    if (ucs2_len == 0) {
        luat_heap_free(ucs2_buf);
        lua_pushlstring(L, "", 0);
        return 1;
    }

    /* Step 2: UCS2 → GB2312
       Each UCS2 char → at most 2 bytes GB2312 */
    size_t gb_size = ucs2_len;
    char *gb_buf = (char *)luat_heap_malloc(gb_size);
    if (!gb_buf) {
        luat_heap_free(ucs2_buf);
        LLOGE("oom gb2312 buf");
        return 0;
    }

    char *ucs2_src = ucs2_buf;
    char *gb_ptr = gb_buf;
    size_t ucs2_src_left = ucs2_len;
    size_t gb_left = gb_size;
    iconv_ucs2_to_gb2312(&ucs2_src, &ucs2_src_left, &gb_ptr, &gb_left);
    size_t gb_len = gb_size - gb_left;

    luat_heap_free(ucs2_buf);
    lua_pushlstring(L, gb_buf, gb_len);
    luat_heap_free(gb_buf);
    return 1;
}

static const rotable_Reg_t inconvFuncs[] = {
    { "open",   ROREG_FUNC(Liconv_open)},
    { "new",    ROREG_FUNC(Liconv_open)},
    { "iconv",  ROREG_FUNC(Liconv)},
    //{ "gb2utf8", ROREG_FUNC(l_iconv_gb2utf8)},
    //{ "utf82gb", ROREG_FUNC(l_iconv_utf82gb)},
    { "ERROR_NO_MEMORY",  ROREG_INT(ERROR_NO_MEMORY)},
    { "ERROR_INVALID",    ROREG_INT(ERROR_INVALID)},
    { "ERROR_INCOMPLETE", ROREG_INT(ERROR_INCOMPLETE)},
    { "ERROR_UNKNOWN",    ROREG_INT(ERROR_UNKNOWN)},
    { NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_iconv(lua_State *L) {
    luat_newlib2(L, inconvFuncs);

    luaL_newmetatable(L, ICONV_TYPENAME);
    lua_pushliteral(L, "__index");
    lua_pushvalue(L, -3);
    lua_settable(L, -3);
    lua_pushliteral(L, "__gc");
    lua_pushcfunction(L, Liconv_close);
    lua_settable(L, -3);
    lua_pop(L, 1);

    return 1;
}
