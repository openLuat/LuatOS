/*
@module  miniz
@summary 简易zlib压缩
@version 1.0
@date    2022.8.11
@tag LUAT_USE_MINIZ
@usage
-- 准备好数据
local bigdata = "123jfoiq4hlkfjbnasdilfhuqwo;hfashfp9qw38hrfaios;hfiuoaghfluaeisw"
-- 压缩之, 压缩得到的数据是zlib兼容的,其他语言可通过zlib相关的库进行解压
local cdata = miniz.compress(bigdata) 
-- lua 的 字符串相当于有长度的char[],可存放包括0x00的一切数据
if cdata then
    -- 检查压缩前后的数据大小
    log.info("miniz", "before", #bigdata, "after", #cdata)
    log.info("miniz", "cdata as hex", cdata:toHex())

    -- 解压, 得到原文
    local udata = miniz.uncompress(cdata)
    log.info("miniz", "udata", udata)
end
*/
#include "luat_base.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "miniz"
#include "luat_log.h"

#include "miniz.h"

static mz_bool luat_output_buffer_putter(const void *pBuf, int len, void *pUser) {
    luaL_addlstring((luaL_Buffer*)pUser, pBuf, len);
    return MZ_TRUE;
}

/*
快速压缩,需要165kb的系统内存和32kb的LuaVM内存
@api miniz.compress(data, flags)
@string 待压缩的数据, 少于400字节的数据不建议压缩, 且压缩后的数据不能大于32k.
@flags 压缩参数,默认是 miniz.WRITE_ZLIB_HEADER , 即写入zlib头部
@return string 若压缩成功,返回数据字符串, 否则返回nil
@usage

local bigdata = "123jfoiq4hlkfjbnasdilfhuqwo;hfashfp9qw38hrfaios;hfiuoaghfluaeisw"
local cdata = miniz.compress(bigdata)
if cdata then
    log.info("miniz", "before", #bigdata, "after", #cdata)
    log.info("miniz", "cdata as hex", cdata:toHex())
end

*/
static int l_miniz_compress(lua_State* L) {
    size_t len = 0;
    tdefl_compressor *pComp;
    mz_bool succeeded;
    const char* data = luaL_checklstring(L, 1, &len);
    int flags = luaL_optinteger(L, 2, TDEFL_WRITE_ZLIB_HEADER);
    if (len > 32* 1024) {
        LLOGE("only 32k data is allow");
        return 0;
    }
    luaL_Buffer buff;
    if (NULL == luaL_buffinitsize(L, &buff, 4096)) {
        LLOGE("out of memory when malloc dst buff");
        return 0;
    }
    pComp = (tdefl_compressor *)luat_heap_malloc(sizeof(tdefl_compressor));
    if (!pComp) {
        LLOGE("out of memory when malloc tdefl_compressor size 0x%04X", sizeof(tdefl_compressor));
        return 0;
    }
    succeeded = (tdefl_init(pComp, luat_output_buffer_putter, &buff, flags) == TDEFL_STATUS_OKAY);
    succeeded = succeeded && (tdefl_compress_buffer(pComp, data, len, TDEFL_FINISH) == TDEFL_STATUS_DONE);
    luat_heap_free(pComp);
    if (!succeeded) {
        LLOGW("compress fail ret=0");
        return 0;
    }
    luaL_pushresult(&buff);
    return 1;
}

/*
快速解压,需要32kb的LuaVM内存
@api miniz.uncompress(data, flags)
@string 待解压的数据, 解压后的数据不能大于32k
@flags 解压参数,默认是 miniz.PARSE_ZLIB_HEADER , 即解析zlib头部
@return string 若解压成功,返回数据字符串, 否则返回nil
@usage

local bigdata = "123jfoiq4hlkfjbnasdilfhuqwo;hfashfp9qw38hrfaios;hfiuoaghfluaeisw"
local cdata = miniz.compress(bigdata)
if cdata then
    log.info("miniz", "before", #bigdata, "after", #cdata)
    log.info("miniz", "cdata as hex", cdata:toHex())

    local udata = miniz.uncompress(cdata)
    log.info("miniz", "udata", udata)
end
*/
static int l_miniz_uncompress(lua_State* L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    int flags = luaL_optinteger(L, 2, TINFL_FLAG_PARSE_ZLIB_HEADER);
    if (len > 32* 1024) {
        LLOGE("only 32k data is allow");
        return 0;
    }
    luaL_Buffer buff;
    char* dst = luaL_buffinitsize(L, &buff, TDEFL_OUT_BUF_SIZE);
    if (dst == NULL) {
        LLOGE("out of memory when malloc dst buff");
        return 0;
    }
    size_t out_buf_len = TDEFL_OUT_BUF_SIZE;
    tinfl_status status;
    tinfl_decompressor *decomp = luat_heap_malloc(sizeof(tinfl_decompressor));
    if (decomp == NULL) {
        LLOGE("out of memory when malloc tinfl_decompressor");
        return 0;
    }
    tinfl_init(decomp);
    status = tinfl_decompress(decomp, (const mz_uint8 *)data, &len, (mz_uint8 *)dst, (mz_uint8 *)dst, &out_buf_len, (flags & ~TINFL_FLAG_HAS_MORE_INPUT) | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    size_t ret = (status != TINFL_STATUS_DONE) ? TINFL_DECOMPRESS_MEM_TO_MEM_FAILED : out_buf_len;
    luat_heap_free(decomp);
    if (ret == TINFL_DECOMPRESS_MEM_TO_MEM_FAILED) {
        LLOGW("decompress fail");
        return 0;
    }
    luaL_pushresultsize(&buff, ret);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_miniz[] = {
    {"compress", ROREG_FUNC(l_miniz_compress)},
    {"uncompress", ROREG_FUNC(l_miniz_uncompress)},
    // {"inflate", ROREG_FUNC(l_miniz_inflate)},
    // {"deflate", ROREG_FUNC(l_miniz_deflate)},

    // 放些常量
    // 压缩参数-------------------------
    //@const WRITE_ZLIB_HEADER int 压缩参数,是否写入zlib头部数据,compress函数的默认值
    {"WRITE_ZLIB_HEADER", ROREG_INT(TDEFL_WRITE_ZLIB_HEADER)},
    //@const COMPUTE_ADLER32 int 压缩/解压参数,是否计算/校验adler-32
    {"COMPUTE_ADLER32", ROREG_INT(TDEFL_COMPUTE_ADLER32)},
    //@const GREEDY_PARSING_FLAG int 压缩参数,是否快速greedy处理, 默认使用较慢的处理模式
    {"GREEDY_PARSING_FLAG", ROREG_INT(TDEFL_GREEDY_PARSING_FLAG)},
    //@const NONDETERMINISTIC_PARSING_FLAG int 压缩参数,是否快速初始化压缩器
    {"NONDETERMINISTIC_PARSING_FLAG", ROREG_INT(TDEFL_NONDETERMINISTIC_PARSING_FLAG)},
    //@const RLE_MATCHES int 压缩参数, 仅扫描RLE
    {"RLE_MATCHES", ROREG_INT(TDEFL_RLE_MATCHES)},
    //@const FILTER_MATCHES int 压缩参数,过滤少于5次的字符
    {"FILTER_MATCHES", ROREG_INT(TDEFL_FILTER_MATCHES)},
    //@const FORCE_ALL_STATIC_BLOCKS int 压缩参数,是否禁用优化过的Huffman表
    {"FORCE_ALL_STATIC_BLOCKS", ROREG_INT(TDEFL_FORCE_ALL_STATIC_BLOCKS)},
    //@const FORCE_ALL_RAW_BLOCKS int 压缩参数,是否只要raw块
    {"FORCE_ALL_RAW_BLOCKS", ROREG_INT(TDEFL_FORCE_ALL_RAW_BLOCKS)},

    // 解压参数
    //@const PARSE_ZLIB_HEADER int 解压参数,是否处理zlib头部,uncompress函数的默认值
    {"PARSE_ZLIB_HEADER", ROREG_INT(TINFL_FLAG_PARSE_ZLIB_HEADER)},
    //@const HAS_MORE_INPUT int 解压参数,是否还有更多数据,仅流式解压可用,暂不支持
    {"HAS_MORE_INPUT", ROREG_INT(TINFL_FLAG_HAS_MORE_INPUT)},
    //@const USING_NON_WRAPPING_OUTPUT_BUF int 解压参数,解压区间是否够全部数据,,仅流式解压可用,暂不支持
    {"USING_NON_WRAPPING_OUTPUT_BUF", ROREG_INT(TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF)},
    //@const COMPUTE_ADLER32 int 解压参数,是否强制校验adler-32
    // {"COMPUTE_ADLER32", ROREG_INT(TINFL_FLAG_COMPUTE_ADLER32)},
    

    {NULL, ROREG_INT(0)}
};


LUAMOD_API int luaopen_miniz( lua_State *L ) {
    luat_newlib2(L, reg_miniz);
    return 1;
}
