/*
@module  pinyin
@summary 拼音输入法核心库
@version 1.0
@date    2025.01
@tag     LUAT_USE_PINYIN
@usage
-- 查询拼音对应的候选字
local pinyin = require "pinyin"
local codes = pinyin.query("zhong")
-- codes = {0x4E2D, 0x949F, ...}  -- Unicode码点数组
*/

#include "luat_base.h"
#include "luat_pinyin.h"

#define LUAT_LOG_TAG "pinyin"
#include "luat_log.h"

// codepoint_to_utf8 函数已移至 luat_pinyin.h 作为内联函数

/*
查询拼音对应的候选字Unicode码点数组
@api pinyin.query(pinyin_string)
@string pinyin_string 拼音字符串，如 "zhong"
@return table Unicode码点数组，如 {0x4E2D, 0x949F, ...}，如果无匹配返回空表 {}
@usage
local codes = pinyin.query("zhong")
-- codes = {0x4E2D, 0x949F, ...}  -- "中"、"钟"等
*/
static int l_pinyin_query(lua_State *L)
{
    size_t len = 0;
    const char *pinyin = luaL_checklstring(L, 1, &len);
    
    if (!pinyin || len == 0) {
        lua_newtable(L);  // 返回空表
        return 1;
    }
    
    const uint32_t *codepoints = NULL;
    uint16_t count = 0;
    
    int ret = luat_pinyin_query(pinyin, &codepoints, &count);
    
    if (ret != 0 || !codepoints || count == 0) {
        lua_newtable(L);  // 返回空表
        return 1;
    }
    
    // 返回码点数组
    lua_newtable(L);
    for (uint16_t i = 0; i < count; i++) {
        lua_pushinteger(L, codepoints[i]);
        lua_rawseti(L, -2, i + 1);
    }
    
    return 1;
}

/*
查询拼音对应的候选字UTF-8字符串数组
@api pinyin.queryUtf8(pinyin_string)
@string pinyin_string 拼音字符串，如 "zhong"
@return table UTF-8字符串数组，如 {"中", "钟", ...}，如果无匹配返回空表 {}
@usage
local chars = pinyin.queryUtf8("zhong")
-- chars = {"中", "钟", ...}  -- 直接返回UTF-8字符串数组
*/
static int l_pinyin_query_utf8(lua_State *L)
{
    size_t len = 0;
    const char *pinyin = luaL_checklstring(L, 1, &len);
    
    if (!pinyin || len == 0) {
        lua_newtable(L);  // 返回空表
        return 1;
    }
    
    // 查询码点
    const uint32_t *codepoints = NULL;
    uint16_t codepoint_count = 0;
    
    int ret = luat_pinyin_query(pinyin, &codepoints, &codepoint_count);
    
    if (ret != 0 || !codepoints || codepoint_count == 0) {
        lua_newtable(L);  // 返回空表
        return 1;
    }
    
    // 分配临时缓冲区存储UTF-8字符串（每个字符最多5字节）
    char utf8_buf[5];
    
    // 返回UTF-8字符串数组
    lua_newtable(L);
    for (uint16_t i = 0; i < codepoint_count; i++) {
        // 将码点转换为UTF-8字符串
        int utf8_len = luat_pinyin_codepoint_to_utf8(codepoints[i], utf8_buf);
        if (utf8_len > 0) {
            lua_pushlstring(L, utf8_buf, utf8_len);
            lua_rawseti(L, -2, i + 1);
        }
    }
    
    return 1;
}

/*
查询按键序列对应的音节列表（9键输入法）
@api pinyin.querySyllables(key_sequence)
@table key_sequence 按键序列，每个元素为1-8的数字（对应ABC-WXYZ）
@return table 音节字符串数组，按常用度排序，如 {"zhong", "zong", ...}
@usage
local pinyin = require "pinyin"
local syllables = pinyin.querySyllables({8, 3, 5, 5, 3})  -- WXYZ, GHI, MNO, MNO, GHI
-- 返回: {"zhong", "zong", ...}
*/
static int l_pinyin_query_syllables(lua_State *L)
{
    // 获取按键序列表
    if (!lua_istable(L, 1)) {
        luaL_argerror(L, 1, "expected table");
        lua_newtable(L);
        return 1;
    }
    
    int table_len = (int)luaL_len(L, 1);
    if (table_len == 0 || table_len > 5) {
        lua_newtable(L);  // 返回空表
        return 1;
    }
    
    // 读取按键序列
    uint8_t key_sequence[5];
    for (int i = 1; i <= table_len; i++) {
        lua_rawgeti(L, 1, i);
        int key_id = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        
        if (key_id < 1 || key_id > 8) {
            lua_newtable(L);  // 无效按键ID，返回空表
            return 1;
        }
        key_sequence[i - 1] = (uint8_t)key_id;
    }
    
    // 分配缓冲区存储音节（最多100个音节）
    char syllables[100][8];
    uint16_t actual_count = 0;
    
    int ret = luat_pinyin_query_syllables_by_keys(
        key_sequence,
        (uint8_t)table_len,
        syllables,
        100,
        &actual_count
    );
    
    if (ret != 0 || actual_count == 0) {
        lua_newtable(L);  // 返回空表
        return 1;
    }
    
    // 返回音节字符串数组
    lua_newtable(L);
    for (uint16_t i = 0; i < actual_count; i++) {
        lua_pushstring(L, syllables[i]);
        lua_rawseti(L, -2, i + 1);
    }
    
    return 1;
}

static const rotable_Reg_t reg_pinyin[] =
{
    {"query", ROREG_FUNC(l_pinyin_query)},
    {"queryUtf8", ROREG_FUNC(l_pinyin_query_utf8)},
    {"querySyllables", ROREG_FUNC(l_pinyin_query_syllables)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_pinyin(lua_State *L)
{
    luat_newlib2(L, reg_pinyin);
    return 1;
}

