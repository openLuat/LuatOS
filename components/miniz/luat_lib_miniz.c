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
#include "luat_mem.h"
#include "luat_fs.h"

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
    int flags = (int)luaL_optinteger(L, 2, TDEFL_WRITE_ZLIB_HEADER);
    if (len > 32* 1024) {
        LLOGE("only 32k data is allow");
        return 0;
    }
    luaL_Buffer buff;
    if (NULL == luaL_buffinitsize(L, &buff, 8*1024)) {
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
    int flags = (int)luaL_optinteger(L, 2, TINFL_FLAG_PARSE_ZLIB_HEADER);
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

// 解压zip到指定目录
#if 0
static int luat_mkdir_recursive(const char* path) {
    size_t len = strlen(path);
    if (len == 0) return 0;
    
    char* temp_path = (char*)luat_heap_malloc(len + 1);
    if (!temp_path) return -1;
    
    strcpy(temp_path, path);
    
    // Remove trailing slash if present
    if (temp_path[len - 1] == '/' || temp_path[len - 1] == '\\') {
        temp_path[len - 1] = '\0';
    }
    
    // Create directories step by step
    char* p = temp_path;
    if (*p == '/' || *p == '\\') p++; // Skip root slash
    
    while (*p) {
        if (*p == '/' || *p == '\\') {
            *p = '\0';
            if (!luat_fs_dexist(temp_path)) {
                if (luat_fs_mkdir(temp_path) != 0) {
                    luat_heap_free(temp_path);
                    return -1;
                }
            }
            *p = '/';
        }
        p++;
    }
    
    // Create the final directory
    if (!luat_fs_dexist(temp_path)) {
        if (luat_fs_mkdir(temp_path) != 0) {
            luat_heap_free(temp_path);
            return -1;
        }
    }
    
    luat_heap_free(temp_path);
    return 0;
}
#endif

static size_t luat_miniz_file_read_func(void *pOpaque, mz_uint64 file_ofs, void *pBuf, size_t n) {
    FILE* f = (FILE*)pOpaque;
    luat_fs_fseek(f, (size_t)file_ofs, SEEK_SET);
    // printf("读取文件 %p 偏移 %llu 读取 %zu 字节\n", f, file_ofs, n);
    return (size_t)luat_fs_fread(pBuf, 1, n, f);
}

static size_t luat_miniz_file_write_func(void *pOpaque, mz_uint64 file_ofs, const void *pBuf, size_t n) {
    FILE* f = (FILE*)pOpaque;
    luat_fs_fseek(f, (size_t)file_ofs, SEEK_SET);
    return (size_t)luat_fs_fwrite(pBuf, 1, n, f);
}

static void* luat_mz_alloc_func(void *opaque, size_t items, size_t size) {
    (void)opaque;
    return luat_heap_opt_calloc(LUAT_HEAP_PSRAM, items, size);
}
static void luat_mz_free_func(void *opaque, void *address) {
    (void)opaque;
    luat_heap_opt_free(LUAT_HEAP_PSRAM, address);
}
static void* luat_mz_realloc_func(void *opaque, void *address, size_t items, size_t size) {
    (void)opaque;
    return luat_heap_opt_realloc(LUAT_HEAP_PSRAM, address, items * size);
}

/*
解压ZIP文件到指定目录
@api miniz.unzip(zip_file_path, target_dir)
@string zip_file_path ZIP文件的完整路径
@string target_dir 目标解压目录的完整路径
@return boolean 成功返回true，失败返回false
@usage
local success = miniz.unzip("/test/csdk.zip", "/output/")
if success then
    log.info("unzip", "解压成功")
else
    log.error("unzip", "解压失败")
end
*/
static int l_miniz_unzip(lua_State* L) {
    const char* zip_file_path = luaL_checkstring(L, 1);
    const char* target_dir = luaL_checkstring(L, 2);
    
    // Ensure target directory ends with slash
    char* normalized_target = (char*)target_dir;
    char tmpdst[256] = {0};
    
    size_t zip_file_size = 0;
    zip_file_size = luat_fs_fsize(zip_file_path);
    if (zip_file_size == 0) {
        LLOGE("ZIP file is empty: %s", zip_file_path);
        lua_pushboolean(L, 0);
        return 1;
    }
    else {
        LLOGI("ZIP file size: %zu bytes", zip_file_size);
    }
    FILE* f = luat_fs_fopen(zip_file_path, "rb");
    if (!f) {
        LLOGE("Failed to open ZIP file: %s", zip_file_path);
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // Initialize ZIP reader
    mz_zip_archive zip_archive = {0};
    zip_archive.m_pRead = luat_miniz_file_read_func;
    zip_archive.m_pIO_opaque = f;
    zip_archive.m_archive_size = zip_file_size;
    zip_archive.m_pAlloc = luat_mz_alloc_func;
    zip_archive.m_pFree = luat_mz_free_func;
    zip_archive.m_pRealloc = luat_mz_realloc_func;

    if(!mz_zip_reader_init(&zip_archive, zip_file_size, 0)) {
        LLOGE("Failed to initialize ZIP reader err %d", zip_archive.m_last_error);
        luat_fs_fclose(f);
        lua_pushboolean(L, 0);
        return 1;
    }
    
    mz_uint num_files = mz_zip_reader_get_num_files(&zip_archive);
    LLOGI("ZIP file contains %u files", num_files);
    
    int success = 1;
    
    
    for (mz_uint i = 0; i < num_files; i++) {
        mz_zip_archive_file_stat file_stat;
        if (!mz_zip_reader_file_stat(&zip_archive, i, &file_stat)) {
            LLOGW("Failed to get file stats for entry %u", i);
            success = 0;
            continue;
        }
        
        // Skip directories (they end with /)
        if (file_stat.m_is_directory) {
            #if 0
            // Create directory structure
            size_t full_path_len = strlen(normalized_target) + strlen(file_stat.m_filename);
            char* full_path = (char*)luat_heap_malloc(full_path_len + 1);
            if (full_path) {
                strcpy(full_path, normalized_target);
                strcat(full_path, file_stat.m_filename);
                luat_mkdir_recursive(full_path);
                luat_heap_free(full_path);
            }
            #endif
            LLOGI("Skipping directory: %s", file_stat.m_filename);
            continue;
        }
        
        // Construct full output path
        snprintf(tmpdst, sizeof(tmpdst), "%s%s", target_dir, file_stat.m_filename);
        LLOGI("Processing file: %s -> %s", file_stat.m_filename, tmpdst);
        
        // Extract file to disk
        FILE* out_f = luat_fs_fopen(tmpdst, "wb+");
        if (!out_f) {
            LLOGE("Failed to create output file: %s", tmpdst);
            success = 0;
            continue;
        }
        if (!mz_zip_reader_extract_to_callback(&zip_archive, i, luat_miniz_file_write_func, out_f, 0)) {
            LLOGE("Failed to extract file: %s", file_stat.m_filename);
            success = 0;
        } else {
            LLOGD("Extracted: %s (%zu bytes)", file_stat.m_filename, (size_t)file_stat.m_uncomp_size);
        }
        luat_fs_fclose(out_f);
    }

    luat_fs_fclose(f);
    
    mz_zip_reader_end(&zip_archive);
    
    if (normalized_target != target_dir) {
        luat_heap_free(normalized_target);
    }
    
    lua_pushboolean(L, success);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_miniz[] = {
    {"compress", ROREG_FUNC(l_miniz_compress)},
    {"uncompress", ROREG_FUNC(l_miniz_uncompress)},
    #ifndef LUAT_USE_MINIZ_LITE
    {"unzip", ROREG_FUNC(l_miniz_unzip)},
    #endif

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
