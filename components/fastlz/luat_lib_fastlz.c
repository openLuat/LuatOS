/*
@module  fastlz
@summary FastLZ压缩
@version 1.0
@date    2023.7.38
@tag LUAT_USE_FASTLZ
@usage
-- 与miniz库的差异
-- 内存需求量小很多, miniz库接近200k, fastlz只需要32k+原始数据大小
-- 压缩比, miniz的压缩比要好于fastlz

-- 准备好数据
local bigdata = "123jfoiq4hlkfjbnasdilfhuqwo;hfashfp9qw38hrfaios;hfiuoaghfluaeisw"
-- 压缩之
local cdata = fastlz.compress(bigdata) 
-- lua 的 字符串相当于有长度的char[],可存放包括0x00的一切数据
if cdata then
    -- 检查压缩前后的数据大小
    log.info("fastlz", "before", #bigdata, "after", #cdata)
    log.info("fastlz", "cdata as hex", cdata:toHex())

    -- 解压, 得到原文
    local udata = fastlz.uncompress(cdata)
    log.info("fastlz", "udata", udata)
end
*/
#include "luat_base.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "fastlz"
#include "luat_log.h"

#include "fastlz.h"

#define HASH_LOG 13
#define HASH_SIZE (1 << HASH_LOG)
#define HASH_MASK (HASH_SIZE - 1)

/*
快速压缩
@api fastlz.compress(data, level)
@string 待压缩的数据, 少于400字节的数据不建议压缩, 且压缩后的数据不能大于32k
@int 压缩级别,默认1, 可选1或者2, 2的压缩比更高(有时候)
@return string 若压缩成功,返回数据字符串, 否则返回nil
@usage
-- 注意, 压缩过程的内存消耗如下
-- 系统内存, 固定32k
-- lua内存, 原始数据的大小的1.05倍,最小占用1024字节.
*/
static int l_fastlz_compress(lua_State* L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    int level = luaL_optinteger(L, 2, 1);
    luaL_Buffer buff;
    luaL_buffinitsize(L, &buff, len > 512 ? (int)(len * 1.05) : (1024));
    uint32_t *htab = luat_heap_malloc( sizeof(uint32_t) * HASH_SIZE);
    if (htab) {
        int ret = fastlz_compress_level(level, data, len, buff.b, htab);
        luat_heap_free(htab);
        if (ret > 0) {
            luaL_pushresultsize(&buff, ret);
            return 1;
        }
    }
    return 0;
}

/*
快速解压
@api fastlz.uncompress(data, maxout)
@string 待解压的数据
@int 解压后的最大大小, 默认是4k, 可按需调整
@return string 若解压成功,返回数据字符串, 否则返回nil
*/
static int l_fastlz_uncompress(lua_State* L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    size_t maxout = luaL_optinteger(L, 2, 4096);
    luaL_Buffer buff;
    luaL_buffinitsize(L, &buff, maxout);
    uint32_t *htab = luat_heap_malloc( sizeof(uint32_t) * HASH_SIZE);
    if (htab) {
        int ret = fastlz_decompress(data, len, buff.b, maxout);
        luat_heap_free(htab);
        if (ret > 0) {
            luaL_pushresultsize(&buff, ret);
            return 1;
        }
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_fastlz[] = {
    {"compress", ROREG_FUNC(l_fastlz_compress)},
    {"uncompress", ROREG_FUNC(l_fastlz_uncompress)},
    {NULL, ROREG_INT(0)}
};


LUAMOD_API int luaopen_fastlz( lua_State *L ) {
    luat_newlib2(L, reg_fastlz);
    return 1;
}
