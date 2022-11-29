/*
@module  zlib
@summary zlib压缩/解压缩
@version 1.0
@date    2022.01.06
@tag LUAT_USE_ZLIB
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_fs.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include "zlib.h"

#define LUAT_LOG_TAG "zlib"
#include "luat_log.h"

#define CHUNK 4096

int zlib_compress(FILE *source, FILE *dest, int level){
    int ret, flush;
    unsigned have;
    z_stream strm;
    /* allocate deflate state */
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    ret = deflateInit(&strm, level);
    if (ret != Z_OK)
        return ret;
    char* in = (char*)luat_heap_malloc(CHUNK * sizeof(char));
    char* out = (char*)luat_heap_malloc(CHUNK * sizeof(char));
    /* compress until end of file */
    do {
        strm.avail_in = luat_fs_fread(in, 1, CHUNK, source);
        if (luat_fs_ferror(source)) {
            (void)deflateEnd(&strm);
            luat_heap_free(in);
            luat_heap_free(out);
            return Z_ERRNO;
        }
        flush = luat_fs_feof(source) ? Z_FINISH : Z_NO_FLUSH;
        strm.next_in = in;
        /* run deflate() on input until output buffer not full, finish
           compression if all of source has been read in */
        do {
            strm.avail_out = CHUNK;
            strm.next_out = out;
            ret = deflate(&strm, flush);    /* no bad return value */
            assert(ret != Z_STREAM_ERROR);  /* state not clobbered */
            have = CHUNK - strm.avail_out;
            if (luat_fs_fwrite(out, 1, have, dest) != have || luat_fs_ferror(dest)) {
                (void)deflateEnd(&strm);
                luat_heap_free(in);
                luat_heap_free(out);
                return Z_ERRNO;
            }
        } while (strm.avail_out == 0);
        assert(strm.avail_in == 0);     /* all input will be used */
        /* done when last data in file processed */
    } while (flush != Z_FINISH);
    assert(ret == Z_STREAM_END);        /* stream will be complete */
    /* clean up and return */
    (void)deflateEnd(&strm);
    luat_heap_free(in);
    luat_heap_free(out);
    return Z_OK;
}

int zlib_decompress(FILE *source, FILE *dest){
    int ret;
    unsigned have;
    z_stream strm;
    /* allocate inflate state */
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.avail_in = 0;
    strm.next_in = Z_NULL;
    ret = inflateInit(&strm);
    if (ret != Z_OK)
        return ret;
    char* in = (char*)luat_heap_malloc(CHUNK * sizeof(char));
    char* out = (char*)luat_heap_malloc(CHUNK * sizeof(char));
    /* decompress until deflate stream ends or end of file */
    do {
        strm.avail_in = luat_fs_fread(in, 1, CHUNK, source);
        if (luat_fs_ferror(source)) {
            (void)inflateEnd(&strm);
            luat_heap_free(in);
            luat_heap_free(out);
            return Z_ERRNO;
        }
        if (strm.avail_in == 0)
            break;
        strm.next_in = in;
        /* run inflate() on input until output buffer not full */
        do {
            strm.avail_out = CHUNK;
            strm.next_out = out;
            ret = inflate(&strm, Z_NO_FLUSH);
            assert(ret != Z_STREAM_ERROR);  /* state not clobbered */
            switch (ret) {
            case Z_NEED_DICT:
                ret = Z_DATA_ERROR;     /* and fall through */
            case Z_DATA_ERROR:
            case Z_MEM_ERROR:
                (void)inflateEnd(&strm);
                luat_heap_free(in);
                luat_heap_free(out);
                return ret;
            }
            have = CHUNK - strm.avail_out;
            if (luat_fs_fwrite(out, 1, have, dest) != have || luat_fs_ferror(dest)) {
                (void)inflateEnd(&strm);
                luat_heap_free(in);
                luat_heap_free(out);
                return Z_ERRNO;
            }
        } while (strm.avail_out == 0);
        /* done when inflate() says it's done */
    } while (ret != Z_STREAM_END);
    /* clean up and return */
    (void)inflateEnd(&strm);
    luat_heap_free(in);
    luat_heap_free(out);
    return ret == Z_STREAM_END ? Z_OK : Z_DATA_ERROR;
}

/* report a zlib or i/o error */
static void zerr(int ret){
    fputs("zpipe: ", stderr);
    switch (ret) {
    case Z_ERRNO:
        if (luat_fs_ferror(stdin))
            fputs("error reading stdin\n", stderr);
        if (luat_fs_ferror(stdout))
            fputs("error writing stdout\n", stderr);
        break;
    case Z_STREAM_ERROR:
        fputs("invalid compression level\n", stderr);
        break;
    case Z_DATA_ERROR:
        fputs("invalid or incomplete deflate data\n", stderr);
        break;
    case Z_MEM_ERROR:
        fputs("out of memory\n", stderr);
        break;
    case Z_VERSION_ERROR:
        fputs("zlib version mismatch!\n", stderr);
    }
}

/*
zlib压缩(需要大约270k内存，大部分mcu不支持)
@api zlib.c(input_file,output_file)
@string input_file  输入文件
@string output_file 输出文件
@return bool 正常返回 ture  失败返回 false
@usage
zlib.c("/sd/1.txt","/sd/zlib")
*/
static int luat_zlib_compress(lua_State *L){
    FILE *fd_in, *fd_out;
    int ret  = 0;
    size_t size = 0;
    const char* input_file = luaL_checklstring(L, 1, &size);
    const char* output_file = luaL_checklstring(L, 2, &size);

    fd_in = luat_fs_fopen(input_file, "r");
    if (fd_in == NULL){
        LLOGE("[zlib] open the input file : %s error!", input_file);
        ret = -1;
        goto _exit;
    }
    fd_out = luat_fs_fopen(output_file, "w+");
    if (fd_out == NULL){
        LLOGE("[zlib] open the output file : %s error!", output_file);
        ret = -1;
        goto _exit;
    }
    ret = zlib_compress(fd_in, fd_out, Z_BEST_COMPRESSION);
    if (ret != Z_OK){
        zerr(ret);
        LLOGE("[zlib] compress file error!\n");
        return ret;
    }
    luat_fs_fclose(fd_in);
    luat_fs_fclose(fd_out);
    lua_pushboolean(L, 1);
    return 1;

_exit:
    if(fd_in != NULL){
        luat_fs_fclose(fd_in);
    }
    if(fd_out != NULL){
        luat_fs_fclose(fd_out);
    }
    lua_pushboolean(L, 0);
    return 1;
}

/*
zlib解压缩(需要大约18k内存，大部分mcu都支持)
@api zlib.d(input_file,output_file)
@string input_file  输入文件
@string output_file 输出文件
@return bool 正常返回 ture  失败返回 false
@usage
zlib.d("/sd/zlib","/sd/1.txt")
*/
static int luat_zlib_decompress(lua_State *L){
    FILE *fd_in, *fd_out;
    int ret  = 0;
    size_t size = 0;
    const char* input_file = luaL_checklstring(L, 1, &size);
    const char* output_file = luaL_checklstring(L, 2, &size);

    fd_in = luat_fs_fopen(input_file, "r");
    if (fd_in == NULL){
        LLOGE("[zlib] open the input file : %s error!", input_file);
        ret = -1;
        goto _exit;
    }
    fd_out = luat_fs_fopen(output_file, "w+");
    if (fd_out == NULL){
        LLOGE("[zlib] open the output file : %s error!", output_file);
        ret = -1;
        goto _exit;
    }
    ret = zlib_decompress(fd_in, fd_out);
    if (ret != Z_OK)
    {
        zerr(ret);
        LLOGE("[zlib] decompress file error!");
        return ret;
    }
    luat_fs_fclose(fd_in);
    luat_fs_fclose(fd_out);
    lua_pushboolean(L, 1);
    return 1;

_exit:
    if(fd_in != NULL){
        luat_fs_fclose(fd_in);
    }
    if(fd_out != NULL){
        luat_fs_fclose(fd_out);
    }
    lua_pushboolean(L, 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_zlib[] =
{
    { "c",      ROREG_FUNC(luat_zlib_compress)},
    { "d",      ROREG_FUNC(luat_zlib_decompress)},
	{ NULL,     {}}
};

LUAMOD_API int luaopen_zlib( lua_State *L ) {
    luat_newlib2(L, reg_zlib);
    return 1;
}
