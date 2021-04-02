/*
@module  zbuff
@summary c内存数据操作库
@version 0.1
@date    2021.03.31
*/
#include "luat_base.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "luat.zbuff"
#include "luat_log.h"

#define LUAT_ZBUFF_TYPE "ZBUFF*"

#define tozbuff(L) ((luat_zbuff *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE))

/**
创建zbuff
@api zbuff.create(length,data)
@int 字节数
@any 可选参数，number时为填充数据，string时为填充字符串
@return object zbuff对象，如果创建失败会返回nil
@usage
-- 创建zbuff
local buff = zbuff.create(1024) -- 空白的
local buff = zbuff.create(1024, 0x33) --创建一个初值全为0x33的内存区域
local buff = zbuff.create(1024, "123321456654") -- 创建，并填充一个已有字符串的内容
 */
static int l_zbuff_create(lua_State *L)
{
    size_t len = luaL_checkinteger(L, 1);
    if (len <= 0)
    {
        return 0;
    }

    luat_zbuff *buff = (luat_zbuff *)lua_newuserdata(L, sizeof(luat_zbuff));
    if (buff == NULL)
    {
        return 0;
    }
    buff->addr = (uint8_t *)luat_heap_malloc(len);
    if (buff->addr == NULL)
    {
        lua_pushnil(L);
        lua_pushstring(L,"memory not enough");
        return 2;
    }

    buff->len = len;
    buff->cursor = 0;

    if(lua_isinteger(L,2)){
        memset(buff->addr, luaL_checkinteger(L,2) % 0x100, len);
    }
    else if (lua_isstring(L, 2))
    {
        char *data = luaL_optlstring(L, 2, "", &len);
        if(len > buff->len)//防止越界
        {
            len = buff->len;
        }
        memcpy(buff->addr, data, len);
        buff->cursor = len;
    }
    else{
        memset(buff->addr, 0, len);
    }

    luaL_setmetatable(L, LUAT_ZBUFF_TYPE);
    return 1;
}

/**
zbuff写数据
@api buff:write(para,...)
@any 写入buff的数据，string时为一个参数，number时可为多个参数
@return number 数据成功写入的长度
@usage
-- 类file的读写操作
local len = buff:write("123") -- 写入数据, 指针相应地往后移动，返回写入的数据长度
local len = buff:write(0x1a,0x30,0x31,0x32,0x00,0x01)  -- 按数值写入多个字节数据
 */
static int l_zbuff_write(lua_State *L)
{
    if(lua_isinteger(L,2)){
        int len = 0,data;
        luat_zbuff *buff = tozbuff(L);
        while(lua_isinteger(L,2+len) && buff->cursor < buff->len){
            data = luaL_checkinteger(L,2+len);
            *(uint8_t*)(buff->addr+buff->cursor) = data % 0x100;
            buff->cursor++;
            len++;
        }
        lua_pushinteger(L, len);
        return 1;
    }
    else{
        size_t len;
        char *data = luaL_checklstring(L, 2, &len);
        luat_zbuff *buff = tozbuff(L);
        if(len + buff->cursor > buff->len)//防止越界
        {
            len = buff->len - buff->cursor;
        }
        memcpy(buff->addr+buff->cursor, data, len);
        buff->cursor = buff->cursor + len;
        lua_pushinteger(L, len);
        return 1;
    }
}

/**
zbuff读数据
@api buff:read(length)
@int 读取buff中的字节数
@return string 读取结果
@usage
-- 类file的读写操作
local str = buff:read(3)
 */
static int l_zbuff_read(lua_State *L)
{
    luat_zbuff *buff = tozbuff(L);
    int read_num = luaL_optinteger(L, 2, 1);
    if(read_num > buff->len - buff->cursor)//防止越界
    {
        read_num = buff->len - buff->cursor;
    }
    if(read_num <= 0)
    {
        lua_pushlstring(L, NULL, 0);
        return 1;
    }
    char *return_str = (char *)luat_heap_malloc(read_num);
    if(return_str == NULL)
    {
        return 0;
    }
    memcpy(return_str, buff->addr+buff->cursor, read_num);
    lua_pushlstring(L, return_str, read_num);
    buff->cursor += read_num;
    return 1;
}

/**
zbuff设置光标位置
@api buff:seek(base,offset)
@int 偏移长度
@int whence, 基点，默认zbuff.SEEK_SET<br>zbuff.SEEK_SET: 基点为 0 （文件开头）<br>zbuff.SEEK_CUR: 基点为当前位置<br>zbuff.SEEK_END: 基点为文件尾
@return int 设置光标后从buff开头计算起的光标的位置
@usage
buff:seek(0,zbuff.SEEK_SET) -- 把光标设置到指定位置
buff:seek(5,zbuff.SEEK_CUR)
buff:seek(-3,zbuff.SEEK_END)
 */
static int l_zbuff_seek(lua_State *L)
{
    luat_zbuff *buff = tozbuff(L);

    int offset = luaL_checkinteger(L, 2);
    int whence = luaL_optinteger(L,3,ZBUFF_SEEK_SET);
    switch (whence)
    {
    case ZBUFF_SEEK_SET:
        break;
    case ZBUFF_SEEK_CUR:
        offset = buff->cursor + offset;
        break;
    case ZBUFF_SEEK_END:
        offset = buff->len + offset;
        break;
    default:
        return 0;
    }
    if(offset <= 0) offset = 0;
    if(offset > buff->len) offset = buff->len;
    buff->cursor = offset;
    lua_pushinteger(L, buff->cursor);
    return 1;
}

//code from https://github.com/LuaDist/lpack/blob/master/lpack.c
#define	OP_STRING	'A'
#define	OP_FLOAT	'f'
#define	OP_DOUBLE	'd'
#define	OP_NUMBER	'n'
#define	OP_CHAR		'c'
#define	OP_BYTE		'b'
#define	OP_SHORT	'h'
#define	OP_USHORT	'H'
#define	OP_INT		'i'
#define	OP_UINT		'I'
#define	OP_LONG		'l'
#define	OP_ULONG	'L'
#define	OP_LITTLEENDIAN	'<'
#define	OP_BIGENDIAN	'>'
#define	OP_NATIVE	'='

/**
将一系列数据按照格式字符转化，并写入
@api buff:pack(format,val1, val2,...)
@string 后面数据的格式（符号含义见下面的例子）
@val  传入的数据，可以为多个数据
@return int 成功写入的数据长度
@usage
buff:pack(">IIH", 0x1234, 0x4567, 0x12) -- 按格式写入几个数据
-- A：string
-- f：float
-- d：double
-- n：Lua number
-- c：char  int8
-- b：byte  uint8
-- h：int16
-- H：uint16
-- i：int32
-- I：uint32
-- l：int64
-- L：uint64
-- <：little endian
-- >：big endian
-- =：native endian
 */
static int l_zbuff_pack(lua_State *L)
{

    return 0;
}


/**
将一系列数据按照格式字符读取出来
@api buff:unpack(format)
@string 数据的格式（符号含义见上面pack接口的例子）
@return any 按格式读出来的数据，如果某数据读取失败，就是nil
@usage
local a,b,c,s = buff:unpack(">IIHA10") -- 按格式读取几个数据
 */
static int l_zbuff_unpack(lua_State *L)
{
    return 0;
}

/**
以下标形式进行数据读写
@api buff[n]
@int 第几个数据，以0开始的下标（C标准）
@return number 该位置的数据
@usage
buff[0] = 0xc8
local data = buff[0]
 */
static int l_zbuff_index(lua_State *L)
{
    LLOGD("l_zbuff_index!");
    luat_zbuff *buff = tozbuff(L);
    LLOGD("buff->len %d",buff->len);
    int o = luaL_checkinteger(L,2);
    LLOGD("o %d",o);
    if(o > buff->len) return 0;
    lua_pushinteger(L,buff->addr[o]);
    return 1;
}

static int l_zbuff_newindex(lua_State *L)
{
    LLOGD("l_zbuff_newindex!");
    luat_zbuff *buff = tozbuff(L);
    if(lua_isinteger(L,2)){
        int o = luaL_checkinteger(L,2);
        int n = luaL_checkinteger(L,3) % 256;
        if(o > buff->len) return 0;
        buff->addr[o] = n;
    }
    return 0;
}

// __gc
static int l_zbuff_gc(lua_State *L)
{
    luat_zbuff *buff = tozbuff(L);
    luat_heap_free(buff->addr);
    return 0;
}

static const luaL_Reg lib_zbuff[] = {
    {"write", l_zbuff_write},
    {"read", l_zbuff_read},
    {"seek", l_zbuff_seek},
    {"pack", l_zbuff_pack},
    {"unpack", l_zbuff_unpack},
    {"get", l_zbuff_index},
    {"__newindex", l_zbuff_newindex},
    {"__gc", l_zbuff_gc},
    {NULL, NULL}};

static void createmeta(lua_State *L)
{
    luaL_newmetatable(L, LUAT_ZBUFF_TYPE); /* create metatable for file handles */
    lua_pushvalue(L, -1);                  /* push metatable */
    lua_setfield(L, -2, "__index");        /* metatable.__index = metatable */
    luaL_setfuncs(L, lib_zbuff, 0);        /* add file methods to new metatable */
    lua_pop(L, 1);                         /* pop new metatable */
}

#include "rotable.h"
static const rotable_Reg reg_zbuff[] =
    {
        {"create", l_zbuff_create, 0},
        {"SEEK_SET", NULL, ZBUFF_SEEK_SET},
        {"SEEK_CUR", NULL, ZBUFF_SEEK_CUR},
        {"SEEK_END", NULL, ZBUFF_SEEK_END},
        {NULL, NULL, 0}};

LUAMOD_API int luaopen_zbuff(lua_State *L)
{
    rotable_newlib(L, reg_zbuff);
    createmeta(L);
    return 1;
}
