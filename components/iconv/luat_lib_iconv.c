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
#include <stdlib.h>


#include "luat_base.h"
#include "luat_mem.h"

#define LIB_NAME                "iconv"
#define LIB_VERSION             LIB_NAME " r5"
#define ICONV_TYPENAME          "iconv_t"

#define LUAT_LOG_TAG "iconv"
#include "luat_log.h"

/* Emulates lua_(un)boxpointer from Lua 5.0 (don't exists on Lua 5.1) */
#define boxptr(L, p)   (*(void**)(lua_newuserdata(L, sizeof(void*))) = (p))
#define unboxptr(L, i) (*(void**)(lua_touserdata(L, i)))

/* Table assumed on top */
#define tblseticons(L, c, v)    \
    lua_pushliteral(L, c);      \
    lua_pushnumber(L, v);       \
    lua_settable(L, -3);



#define ERROR_NO_MEMORY     1
#define ERROR_INVALID       2
#define ERROR_INCOMPLETE    3
#define ERROR_UNKNOWN       4

#if 1
#include "iconv.h"

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
    // LLOGD("转换前的各种参数 ibleft %d obleft %d", ibleft, obleft);
    ret = iconv_convert(cd, &inbuf, &ibleft, &outbuf, &obleft);
    // LLOGD("转换后的各种参数 ibleft %d obleft %d", ibleft, obleft);
    if (ret == 0) {
        lua_pushlstring(L, outbufs, obsize - obleft);
    }
    else {
        lua_pushstring(L, "");
    }

    luat_heap_free(outbufs);
    return 1;   /* Done */
}



#ifdef HAS_ICONVLIST /* a GNU extension? */

static int push_one(unsigned int cnt, char *names[], void *data) {
    lua_State *L = (lua_State*) data;
    int n = (int) lua_tonumber(L, -1);
    int i;

    /* Stack: <tbl> n */
    lua_remove(L, -1);
    for (i = 0; i < cnt; i++) {
        /* Stack> <tbl> */
        lua_pushnumber(L, n++);
        lua_pushstring(L, names[i]);
        /* Stack: <tbl> n <str> */
        lua_settable(L, -3);
    }
    lua_pushnumber(L, n);
    /* Stack: <tbl> n */
    return 0;
}


static int Liconvlist(lua_State *L) {
    lua_newtable(L);
    lua_pushnumber(L, 1);

    /* Stack:   <tbl> 1 */
    iconvlist(push_one, (void*) L);

    /* Stack:   <tbl> n */
    lua_remove(L, -1);
    return 1;
}

#endif

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

// #include "rotable.h"
#include "rotable2.h"
static const rotable_Reg_t inconvFuncs[] = {
    { "open",   ROREG_FUNC(Liconv_open)},
    { "new",    ROREG_FUNC(Liconv_open)},
    { "iconv",  ROREG_FUNC(Liconv)},
#ifdef HAS_ICONVLIST
    { "list",   ROREG_FUNC(Liconvlist)},
#endif
    { "ERROR_NO_MEMORY",  ROREG_INT(ERROR_NO_MEMORY)},
    { "ERROR_INVALID",    ROREG_INT(ERROR_INVALID)},
    { "ERROR_INCOMPLETE", ROREG_INT(ERROR_INCOMPLETE)},
    { "ERROR_UNKNOWN",    ROREG_INT(ERROR_UNKNOWN)},
    { NULL, ROREG_INT(0)}
};


// static const rotable_Reg iconvMT[] = {
//     { "__gc", Liconv_close , 0},
//     { NULL, NULL, NULL}
// };


LUAMOD_API int luaopen_iconv(lua_State *L) {
    luat_newlib2(L, inconvFuncs);

    // luaL_newmetatable(L, ICONV_TYPENAME);
    // lua_pushliteral(L, "__index");
    // rotable_newidx(L, iconvMT);
    // lua_settable(L, -3);
    // lua_pop(L, 1);


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

#else
#include "rotable.h"
static const rotable_Reg iconvMT[] = {
    { NULL, NULL, NULL}
};
#endif
