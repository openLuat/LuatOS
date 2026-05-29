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
#include "luat_mcu.h"

#define LUAT_LOG_TAG "miniz"
#include "luat_log.h"

#include "miniz.h"
#ifdef LUAT_USE_PGFS_COMPONENT
#include "luat_pgfs.h"
#endif

#define LUAT_MINIZ_DEBUG_LOGI(debug, ...) do { if (debug) { LLOGI(__VA_ARGS__); } } while (0)
#define LUAT_MINIZ_DEBUG_LOGD(debug, ...) do { if (debug) { LLOGD(__VA_ARGS__); } } while (0)
#define LUAT_MINIZ_DEBUG_LOGW(debug, ...) do { if (debug) { LLOGW(__VA_ARGS__); } } while (0)

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
static int luat_mkdir_recursive(const char* path) {
    size_t len = strlen(path);
    int need_sep = 0;
    if (len == 0) return 0;

    if (path[len - 1] != '/' && path[len - 1] != '\\') {
        need_sep = 1;
    }

    char* temp_path = (char*)luat_heap_malloc(len + need_sep + 1);
    if (!temp_path) return -1;

    memcpy(temp_path, path, len);
    if (need_sep) {
        temp_path[len++] = '/';
    }
    temp_path[len] = '\0';

    for (size_t i = 0; i < len; i++) {
        if (temp_path[i] == '\\') {
            temp_path[i] = '/';
        }
    }

    char* p = temp_path;
    while (*p) {
        if (*p == '/') {
            char next = *(p + 1);
            if (p != temp_path) {
                *(p + 1) = '\0';
                if (luat_fs_mkdir(temp_path) != 0 && !luat_fs_dexist(temp_path)) {
                    luat_heap_free(temp_path);
                    return -1;
                }
                *(p + 1) = next;
            }
        }
        p++;
    }

    luat_heap_free(temp_path);
    return 0;
}

static int luat_miniz_is_valid_target_dir(const char* target_dir) {
    size_t len;

    if (target_dir == NULL) {
        return 0;
    }
    len = strlen(target_dir);
    if (len == 0) {
        return 0;
    }
    return target_dir[len - 1] == '/';
}

static int luat_miniz_is_unsafe_path(const char* path) {
    const char* segment = path;
    const char* cursor = path;
    size_t segment_len;

    if (path == NULL || path[0] == 0) {
        return 1;
    }
    if (path[0] == '/' || path[0] == '\\') {
        return 1;
    }
    if ((((path[0] >= 'A') && (path[0] <= 'Z')) || ((path[0] >= 'a') && (path[0] <= 'z'))) && path[1] == ':') {
        return 1;
    }
    while (1) {
        if (*cursor == '/' || *cursor == '\\' || *cursor == 0) {
            segment_len = cursor - segment;
            if (segment_len == 2 && segment[0] == '.' && segment[1] == '.') {
                return 1;
            }
            if (*cursor == 0) {
                break;
            }
            segment = cursor + 1;
        }
        cursor++;
    }
    return 0;
}

static char* luat_miniz_join_path(const char* base_path, const char* entry_path) {
    size_t base_len = strlen(base_path);
    size_t entry_len = strlen(entry_path);
    char* full_path = luat_heap_malloc(base_len + entry_len + 1);
    if (full_path == NULL) {
        return NULL;
    }
    memcpy(full_path, base_path, base_len);
    memcpy(full_path + base_len, entry_path, entry_len + 1);
    // 将路径分隔符统一为 '/'
    for (size_t i = 0; i < base_len + entry_len; i++) {
        if (full_path[i] == '\\') {
            full_path[i] = '/';
        }
    }
    return full_path;
}

static int luat_miniz_ensure_parent_dir(const char* full_path) {
    const char* slash = strrchr(full_path, '/');
    const char* backslash = strrchr(full_path, '\\');
    const char* last_sep = slash;
    char* dir_path;
    size_t dir_len;
    int ret;

    if (backslash != NULL && (last_sep == NULL || backslash > last_sep)) {
        last_sep = backslash;
    }
    if (last_sep == NULL) {
        return 0;
    }
    dir_len = last_sep - full_path;
    if (dir_len == 0) {
        return 0;
    }
    dir_path = luat_heap_malloc(dir_len + 1);
    if (dir_path == NULL) {
        return -1;
    }
    memcpy(dir_path, full_path, dir_len);
    dir_path[dir_len] = 0;
    ret = luat_mkdir_recursive(dir_path);
    luat_heap_free(dir_path);
    return ret;
}

static size_t luat_miniz_file_read_func(void *pOpaque, mz_uint64 file_ofs, void *pBuf, size_t n) {
    FILE* f = (FILE*)pOpaque;
    luat_fs_fseek(f, (size_t)file_ofs, SEEK_SET);
    // printf("读取文件 %p 偏移 %llu 读取 %zu 字节\n", f, file_ofs, n);
    return (size_t)luat_fs_fread(pBuf, 1, n, f);
}

typedef struct {
    FILE* out_f;
    const char* entry_name;
    int debug;
    size_t total_written;
    size_t next_log_threshold;
    uint64_t unzip_start_tick_ms;
    uint32_t timeout_ms;
    int timed_out;
} luat_miniz_extract_ctx_t;

static size_t luat_miniz_file_write_func(void *pOpaque, mz_uint64 file_ofs, const void *pBuf, size_t n) {
    luat_miniz_extract_ctx_t* ctx = (luat_miniz_extract_ctx_t*)pOpaque;
    uint64_t now_tick_ms;
    uint64_t elapsed_ms;
    size_t wrote;
    if (!ctx || !ctx->out_f) {
        return 0;
    }
    if (ctx->timeout_ms > 0) {
        now_tick_ms = luat_mcu_tick64_ms();
        elapsed_ms = (now_tick_ms >= ctx->unzip_start_tick_ms)
            ? (now_tick_ms - ctx->unzip_start_tick_ms)
            : (ctx->unzip_start_tick_ms - now_tick_ms);
        if (elapsed_ms >= ctx->timeout_ms) {
            ctx->timed_out = 1;
            return 0;
        }
    }
    luat_fs_fseek(ctx->out_f, (size_t)file_ofs, SEEK_SET);
    wrote = (size_t)luat_fs_fwrite(pBuf, 1, n, ctx->out_f);
    ctx->total_written += wrote;
    if (ctx->debug && ctx->total_written >= ctx->next_log_threshold) {
        LUAT_MINIZ_DEBUG_LOGI(ctx->debug, "Extracting %s: wrote %u bytes",
            ctx->entry_name ? ctx->entry_name : "(unknown)",
            (unsigned int)ctx->total_written);
        ctx->next_log_threshold += (32u * 1024u);
    }
    return wrote;
}

typedef struct {
    char* entry_name;
    char* stage_path;
    uint8_t* mem_data;
    size_t mem_len;
    uint8_t is_dir;
    uint8_t use_mem;
} luat_miniz_stage_entry_t;

static int luat_miniz_should_stage_target(const char* target_dir) {
    if (!target_dir) {
        return 0;
    }
    return strncmp(target_dir, "/lfs2n/", 7) == 0 || strcmp(target_dir, "/lfs2n") == 0;
}

static int luat_miniz_should_use_pgfs_batch(const char* target_dir) {
#ifdef LUAT_USE_PGFS_COMPONENT
    luat_fs_info_t fsinfo;
    if (!target_dir) {
        return 0;
    }
    memset(&fsinfo, 0, sizeof(fsinfo));
    if (luat_fs_info(target_dir, &fsinfo) != 0) {
        return 0;
    }
    return strcmp(fsinfo.filesystem, "pgfs") == 0;
#else
    (void)target_dir;
    return 0;
#endif
}

static int luat_miniz_copy_file(const char* src_path, const char* dst_path) {
    FILE* in_f = luat_fs_fopen(src_path, "rb");
    FILE* out_f;
    uint8_t* buf;
    size_t read_len;
    if (!in_f) {
        return -1;
    }
    out_f = luat_fs_fopen(dst_path, "wb+");
    if (!out_f) {
        luat_fs_fclose(in_f);
        return -1;
    }
    buf = (uint8_t*)luat_heap_malloc(4096);
    if (!buf) {
        luat_fs_fclose(in_f);
        luat_fs_fclose(out_f);
        return -1;
    }
    while ((read_len = luat_fs_fread(buf, 1, 4096, in_f)) > 0) {
        if (luat_fs_fwrite(buf, 1, read_len, out_f) != read_len) {
            luat_heap_free(buf);
            luat_fs_fclose(in_f);
            luat_fs_fclose(out_f);
            return -1;
        }
    }
    luat_heap_free(buf);
    luat_fs_fclose(in_f);
    return luat_fs_fclose(out_f);
}

static void luat_miniz_stage_cleanup(luat_miniz_stage_entry_t* entries, mz_uint num_files) {
    mz_uint i;
    if (!entries) {
        return;
    }
    for (i = 0; i < num_files; i++) {
        if (entries[i].mem_data) {
            luat_heap_free(entries[i].mem_data);
            entries[i].mem_data = NULL;
        }
        if (entries[i].entry_name) {
            luat_heap_free(entries[i].entry_name);
            entries[i].entry_name = NULL;
        }
        if (entries[i].stage_path) {
            if (!entries[i].is_dir && !entries[i].use_mem) {
                luat_fs_remove(entries[i].stage_path);
            }
            luat_heap_free(entries[i].stage_path);
            entries[i].stage_path = NULL;
        }
    }
    luat_heap_free(entries);
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
@api miniz.unzip(zip_file_path, target_dir, debug, timeout_ms)
@string zip_file_path ZIP文件的完整路径
@string target_dir 目标解压目录的完整路径, 必须以 / 结尾
@boolean debug 可选, 是否输出解压过程日志, 默认为false
@int timeout_ms 可选, 整个unzip过程的超时时间(毫秒), 默认30000
@return boolean 成功返回true，失败返回false
@usage
local success = miniz.unzip("/test/csdk.zip", "/output/", true)
if success then
    log.info("unzip", "解压成功")
else
    log.error("unzip", "解压失败")
end
*/
static int l_miniz_unzip(lua_State* L) {
    const char* zip_file_path = luaL_checkstring(L, 1);
    const char* target_dir = luaL_checkstring(L, 2);
    int debug = lua_toboolean(L, 3);
    uint32_t timeout_ms = (uint32_t)luaL_optinteger(L, 4, 30000);
    size_t stage_mem_limit = (size_t)luaL_optinteger(L, 5, 256 * 1024);
    int enable_stage = luat_miniz_should_stage_target(target_dir) && stage_mem_limit > 0;
    char stage_root[64] = {0};
    luat_miniz_stage_entry_t* stage_entries = NULL;
    size_t stage_mem_used = 0;
    uint64_t unzip_start_tick_ms = luat_mcu_tick64_ms();
    uint64_t now_tick_ms;
    uint64_t elapsed_ms;
    size_t zip_file_size = 0;
    mz_uint num_files = 0;
    FILE* f = NULL;
    mz_zip_archive zip_archive = {0};
    int zip_reader_inited = 0;
    int success = 1;
#ifdef LUAT_USE_PGFS_COMPONENT
    uint32_t pgfs_batch_id = 0;
    int pgfs_batch_started = 0;
    int pgfs_batch_need_abort = 0;
#endif

    zip_file_size = luat_fs_fsize(zip_file_path);
    if (zip_file_size == 0) {
        LLOGE("ZIP file is empty: %s", zip_file_path);
        success = 0;
        goto unzip_finish;
    }
    LUAT_MINIZ_DEBUG_LOGI(debug, "ZIP file size: %u bytes", (unsigned int)zip_file_size);
    if (!luat_miniz_is_valid_target_dir(target_dir)) {
        LLOGE("target_dir must end with '/': %s", target_dir);
        success = 0;
        goto unzip_finish;
    }
#ifdef LUAT_USE_PGFS_COMPONENT
    if (luat_miniz_should_use_pgfs_batch(target_dir)) {
        if (luat_pgfs_begin_batch(&pgfs_batch_id) != 0) {
            LLOGE("Failed to begin pgfs batch for unzip target: %s", target_dir);
            success = 0;
            goto unzip_finish;
        }
        pgfs_batch_started = 1;
        pgfs_batch_need_abort = 1;
        LUAT_MINIZ_DEBUG_LOGI(debug, "PGFS batch begin id=%u target=%s", (unsigned int)pgfs_batch_id, target_dir);
    }
#endif
    if (luat_mkdir_recursive(target_dir) != 0) {
        LLOGE("Failed to create target directory: %s", target_dir);
        success = 0;
        goto unzip_finish;
    }
    f = luat_fs_fopen(zip_file_path, "rb");
    if (!f) {
        LLOGE("Failed to open ZIP file: %s", zip_file_path);
        success = 0;
        goto unzip_finish;
    }
    
    // Initialize ZIP reader
    zip_archive.m_pRead = luat_miniz_file_read_func;
    zip_archive.m_pIO_opaque = f;
    zip_archive.m_archive_size = zip_file_size;
    zip_archive.m_pAlloc = luat_mz_alloc_func;
    zip_archive.m_pFree = luat_mz_free_func;
    zip_archive.m_pRealloc = luat_mz_realloc_func;

    if (!mz_zip_reader_init(&zip_archive, zip_file_size, 0)) {
        LLOGE("Failed to initialize ZIP reader err %d", zip_archive.m_last_error);
        success = 0;
        goto unzip_finish;
    }
    zip_reader_inited = 1;

    num_files = mz_zip_reader_get_num_files(&zip_archive);
    LUAT_MINIZ_DEBUG_LOGI(debug, "ZIP file contains %u files", num_files);
    if (enable_stage) {
        snprintf(stage_root, sizeof(stage_root), "/_miniz_stage_%u/", (unsigned int)(unzip_start_tick_ms & 0xFFFFFFFFu));
        if (luat_mkdir_recursive(stage_root) != 0) {
            LLOGE("Failed to create stage directory: %s", stage_root);
            success = 0;
        } else {
            stage_entries = (luat_miniz_stage_entry_t*)luat_heap_opt_calloc(LUAT_HEAP_PSRAM, num_files, sizeof(luat_miniz_stage_entry_t));
            if (!stage_entries) {
                LLOGE("Out of memory for stage entries");
                success = 0;
            }
            LUAT_MINIZ_DEBUG_LOGI(debug, "Stage mode enabled target=%s mem_limit=%u stage_root=%s",
                target_dir, (unsigned int)stage_mem_limit, stage_root);
        }
    }

    for (mz_uint i = 0; i < num_files; i++) {
        mz_zip_archive_file_stat file_stat;
        char* full_path = NULL;
        luat_miniz_stage_entry_t* stage_entry = NULL;
        int is_stage_file = 0;

        if (!success) {
            break;
        }
        if (timeout_ms > 0) {
            now_tick_ms = luat_mcu_tick64_ms();
            elapsed_ms = (now_tick_ms >= unzip_start_tick_ms)
                ? (now_tick_ms - unzip_start_tick_ms)
                : (unzip_start_tick_ms - now_tick_ms);
            if (elapsed_ms >= timeout_ms) {
                LLOGE("Unzip timeout before file #%u, timeout=%u ms elapsed=%u ms",
                    (unsigned int)i, (unsigned int)timeout_ms, (unsigned int)elapsed_ms);
                success = 0;
                break;
            }
        }
        if (!mz_zip_reader_file_stat(&zip_archive, i, &file_stat)) {
            LUAT_MINIZ_DEBUG_LOGW(debug, "Failed to get file stats for entry %u", i);
            success = 0;
            continue;
        }
        if (luat_miniz_is_unsafe_path(file_stat.m_filename)) {
            LLOGE("Unsafe ZIP entry path: %s", file_stat.m_filename);
            success = 0;
            continue;
        }

        if (enable_stage) {
            stage_entry = &stage_entries[i];
            stage_entry->entry_name = luat_miniz_join_path("", file_stat.m_filename);
            if (!stage_entry->entry_name) {
                LLOGE("Out of memory when storing stage entry name: %s", file_stat.m_filename);
                success = 0;
                continue;
            }
            stage_entry->is_dir = file_stat.m_is_directory ? 1 : 0;
            if (stage_entry->is_dir) {
                continue;
            }
            is_stage_file = 1;
            if (timeout_ms == 0 &&
                file_stat.m_uncomp_size <= (mz_uint64)(stage_mem_limit - stage_mem_used) &&
                file_stat.m_uncomp_size <= (mz_uint64)SIZE_MAX) {
                stage_entry->mem_len = (size_t)file_stat.m_uncomp_size;
                if (stage_entry->mem_len > 0) {
                    stage_entry->mem_data = (uint8_t*)luat_heap_opt_malloc(LUAT_HEAP_PSRAM, stage_entry->mem_len);
                    if (!stage_entry->mem_data) {
                        is_stage_file = 0;
                    }
                }
                if (is_stage_file) {
                    if (stage_entry->mem_len > 0 &&
                        !mz_zip_reader_extract_to_mem(&zip_archive, i, stage_entry->mem_data, stage_entry->mem_len, 0)) {
                        LLOGE("Failed to extract to memory: %s err=%d", file_stat.m_filename, zip_archive.m_last_error);
                        success = 0;
                        continue;
                    }
                    stage_entry->use_mem = 1;
                    stage_mem_used += stage_entry->mem_len;
                    LUAT_MINIZ_DEBUG_LOGI(debug, "Stage mem [%u/%u]: %s (%u bytes, used=%u/%u)",
                        (unsigned int)(i + 1u), (unsigned int)num_files, file_stat.m_filename,
                        (unsigned int)stage_entry->mem_len, (unsigned int)stage_mem_used, (unsigned int)stage_mem_limit);
                    continue;
                }
            }
            stage_entry->stage_path = luat_miniz_join_path(stage_root, file_stat.m_filename);
            if (!stage_entry->stage_path) {
                LLOGE("Out of memory when creating stage path: %s", file_stat.m_filename);
                success = 0;
                continue;
            }
            if (luat_miniz_ensure_parent_dir(stage_entry->stage_path) != 0) {
                LLOGE("Failed to create stage parent directory for: %s", stage_entry->stage_path);
                success = 0;
                continue;
            }
            {
                FILE* out_f = luat_fs_fopen(stage_entry->stage_path, "wb+");
                luat_miniz_extract_ctx_t extract_ctx;
                if (!out_f) {
                    LLOGE("Failed to create stage file: %s", stage_entry->stage_path);
                    success = 0;
                    continue;
                }
                extract_ctx.out_f = out_f;
                extract_ctx.entry_name = file_stat.m_filename;
                extract_ctx.debug = debug;
                extract_ctx.total_written = 0;
                extract_ctx.next_log_threshold = 32u * 1024u;
                extract_ctx.unzip_start_tick_ms = unzip_start_tick_ms;
                extract_ctx.timeout_ms = timeout_ms;
                extract_ctx.timed_out = 0;
                if (!mz_zip_reader_extract_to_callback(&zip_archive, i, luat_miniz_file_write_func, &extract_ctx, 0)) {
                    if (extract_ctx.timed_out) {
                        LLOGE("Stage extract timeout: %s timeout=%u ms wrote=%u",
                            file_stat.m_filename, (unsigned int)timeout_ms, (unsigned int)extract_ctx.total_written);
                    }
                    LLOGE("Failed to extract to stage file: %s err=%d wrote=%u",
                        file_stat.m_filename, zip_archive.m_last_error, (unsigned int)extract_ctx.total_written);
                    success = 0;
                }
                luat_fs_fclose(out_f);
            }
            continue;
        }

        full_path = luat_miniz_join_path(target_dir, file_stat.m_filename);
        if (full_path == NULL) {
            LLOGE("Out of memory when joining target path: %s", file_stat.m_filename);
            success = 0;
            continue;
        }

        if (file_stat.m_is_directory) {
            if (luat_mkdir_recursive(full_path) != 0) {
                LLOGE("Failed to create directory: %s", full_path);
                success = 0;
            }
            else {
                LUAT_MINIZ_DEBUG_LOGI(debug, "Created directory: %s", full_path);
            }
            luat_heap_free(full_path);
            continue;
        }
        if (luat_miniz_ensure_parent_dir(full_path) != 0) {
            LLOGE("Failed to create parent directory for: %s", full_path);
            luat_heap_free(full_path);
            success = 0;
            continue;
        }
        LUAT_MINIZ_DEBUG_LOGI(debug, "Processing file [%u/%u]: %s -> %s",
            (unsigned int)(i + 1u), (unsigned int)num_files, file_stat.m_filename, full_path);
        
        // Extract file to disk
        FILE* out_f = luat_fs_fopen(full_path, "wb+");
        if (!out_f) {
            LLOGE("Failed to create output file: %s", full_path);
            luat_heap_free(full_path);
            success = 0;
            continue;
        }
        luat_miniz_extract_ctx_t extract_ctx = {
            .out_f = out_f,
            .entry_name = file_stat.m_filename,
            .debug = debug,
            .total_written = 0,
            .next_log_threshold = 32u * 1024u,
            .unzip_start_tick_ms = unzip_start_tick_ms,
            .timeout_ms = timeout_ms,
            .timed_out = 0
        };
        if (!mz_zip_reader_extract_to_callback(&zip_archive, i, luat_miniz_file_write_func, &extract_ctx, 0)) {
            if (extract_ctx.timed_out) {
                LLOGE("Failed to extract file: %s timeout=%u ms wrote=%u",
                    file_stat.m_filename, (unsigned int)timeout_ms, (unsigned int)extract_ctx.total_written);
            }
            LLOGE("Failed to extract file: %s err=%d wrote=%u",
                file_stat.m_filename, zip_archive.m_last_error, (unsigned int)extract_ctx.total_written);
            success = 0;
        } else {
            LUAT_MINIZ_DEBUG_LOGI(debug, "Extracted done: %s (%u bytes)",
                file_stat.m_filename, (unsigned int)extract_ctx.total_written);
        }
        luat_fs_fclose(out_f);
        luat_heap_free(full_path);
    }

    if (success && enable_stage && stage_entries) {
        for (mz_uint i = 0; i < num_files; i++) {
            char* full_path;
            luat_miniz_stage_entry_t* entry = &stage_entries[i];
            if (!entry->entry_name) {
                continue;
            }
            full_path = luat_miniz_join_path(target_dir, entry->entry_name);
            if (!full_path) {
                success = 0;
                break;
            }
            if (entry->is_dir) {
                if (luat_mkdir_recursive(full_path) != 0) {
                    LLOGE("Failed to create target directory: %s", full_path);
                    luat_heap_free(full_path);
                    success = 0;
                    break;
                }
                luat_heap_free(full_path);
                continue;
            }
            if (luat_miniz_ensure_parent_dir(full_path) != 0) {
                LLOGE("Failed to create parent directory for staged file: %s", full_path);
                luat_heap_free(full_path);
                success = 0;
                break;
            }
            if (entry->use_mem) {
                FILE* out_f = luat_fs_fopen(full_path, "wb+");
                if (!out_f) {
                    LLOGE("Failed to open staged target file: %s", full_path);
                    luat_heap_free(full_path);
                    success = 0;
                    break;
                }
                if (entry->mem_len > 0 &&
                    luat_fs_fwrite(entry->mem_data, 1, entry->mem_len, out_f) != entry->mem_len) {
                    LLOGE("Failed to write staged memory file: %s", full_path);
                    luat_fs_fclose(out_f);
                    luat_heap_free(full_path);
                    success = 0;
                    break;
                }
                if (luat_fs_fclose(out_f) != 0) {
                    LLOGE("Failed to close staged memory file: %s", full_path);
                    luat_heap_free(full_path);
                    success = 0;
                    break;
                }
            } else if (entry->stage_path) {
                if (luat_fs_rename(entry->stage_path, full_path) != 0) {
                    if (luat_miniz_copy_file(entry->stage_path, full_path) != 0) {
                        LLOGE("Failed to move staged file to target: %s", full_path);
                        luat_heap_free(full_path);
                        success = 0;
                        break;
                    }
                    luat_fs_remove(entry->stage_path);
                }
            }
            LUAT_MINIZ_DEBUG_LOGI(debug, "Staged commit [%u/%u]: %s", (unsigned int)(i + 1u), (unsigned int)num_files, full_path);
            luat_heap_free(full_path);
        }
    }

unzip_finish:
    if (zip_reader_inited) {
        mz_zip_reader_end(&zip_archive);
    }
    if (f != NULL) {
        luat_fs_fclose(f);
    }
    if (stage_entries) {
        luat_miniz_stage_cleanup(stage_entries, num_files);
        stage_entries = NULL;
    }

#ifdef LUAT_USE_PGFS_COMPONENT
    if (pgfs_batch_started) {
        if (success) {
            if (luat_pgfs_commit_batch(pgfs_batch_id) != 0) {
                LLOGE("Failed to commit pgfs batch id=%u target=%s", (unsigned int)pgfs_batch_id, target_dir);
                success = 0;
            } else {
                pgfs_batch_need_abort = 0;
                LUAT_MINIZ_DEBUG_LOGI(debug, "PGFS batch commit id=%u target=%s", (unsigned int)pgfs_batch_id, target_dir);
            }
        }
        if (!success && pgfs_batch_need_abort) {
            if (luat_pgfs_abort_batch(pgfs_batch_id) != 0) {
                LLOGE("Failed to abort pgfs batch id=%u target=%s", (unsigned int)pgfs_batch_id, target_dir);
            } else {
                LUAT_MINIZ_DEBUG_LOGI(debug, "PGFS batch abort id=%u target=%s", (unsigned int)pgfs_batch_id, target_dir);
            }
            pgfs_batch_need_abort = 0;
        }
    }
#endif

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
