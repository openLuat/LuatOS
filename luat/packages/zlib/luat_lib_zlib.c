/*
@module  sfud
@summary SPI FLASH sfud软件包
@version 1.0
@date    2021.09.23
*/

#include "luat_base.h"
#include "luat_malloc.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include "zlib.h"

#define LUAT_LOG_TAG "zlib"
#include "luat_log.h"

#define CHUNK 4096
static char in[CHUNK];
static char out[CHUNK];

/* Compress from file source to file dest until EOF on source.
   def() returns Z_OK on success, Z_MEM_ERROR if memory could not be
   allocated for processing, Z_STREAM_ERROR if an invalid compression
   level is supplied, Z_VERSION_ERROR if the version of zlib.h and the
   version of the library linked do not match, or Z_ERRNO if there is
   an error reading or writing the files. */
int def(FILE *source, FILE *dest, int level)
{
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

    /* compress until end of file */
    do {
        strm.avail_in = fread(in, 1, CHUNK, source);
        if (ferror(source)) {
            (void)deflateEnd(&strm);
            return Z_ERRNO;
        }
        flush = feof(source) ? Z_FINISH : Z_NO_FLUSH;
        strm.next_in = in;

        /* run deflate() on input until output buffer not full, finish
           compression if all of source has been read in */
        do {
            strm.avail_out = CHUNK;
            strm.next_out = out;
            ret = deflate(&strm, flush);    /* no bad return value */
            assert(ret != Z_STREAM_ERROR);  /* state not clobbered */
            have = CHUNK - strm.avail_out;
            if (fwrite(out, 1, have, dest) != have || ferror(dest)) {
                (void)deflateEnd(&strm);
                return Z_ERRNO;
            }
        } while (strm.avail_out == 0);
        assert(strm.avail_in == 0);     /* all input will be used */

        /* done when last data in file processed */
    } while (flush != Z_FINISH);
    assert(ret == Z_STREAM_END);        /* stream will be complete */

    /* clean up and return */
    (void)deflateEnd(&strm);
    return Z_OK;
}

/* Decompress from file source to file dest until stream ends or EOF.
   inf() returns Z_OK on success, Z_MEM_ERROR if memory could not be
   allocated for processing, Z_DATA_ERROR if the deflate data is
   invalid or incomplete, Z_VERSION_ERROR if the version of zlib.h and
   the version of the library linked do not match, or Z_ERRNO if there
   is an error reading or writing the files. */
int inf(FILE *source, FILE *dest)
{
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

    /* decompress until deflate stream ends or end of file */
    do {
        strm.avail_in = fread(in, 1, CHUNK, source);
        if (ferror(source)) {
            (void)inflateEnd(&strm);
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
                return ret;
            }
            have = CHUNK - strm.avail_out;
            if (fwrite(out, 1, have, dest) != have || ferror(dest)) {
                (void)inflateEnd(&strm);
                return Z_ERRNO;
            }
        } while (strm.avail_out == 0);

        /* done when inflate() says it's done */
    } while (ret != Z_STREAM_END);

    /* clean up and return */
    (void)inflateEnd(&strm);
    return ret == Z_STREAM_END ? Z_OK : Z_DATA_ERROR;
}

/* report a zlib or i/o error */
void zerr(int ret)
{
    fputs("zpipe: ", stderr);
    switch (ret) {
    case Z_ERRNO:
        if (ferror(stdin))
            fputs("error reading stdin\n", stderr);
        if (ferror(stdout))
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

static int luat_zlib_compress(lua_State *L){
    FILE *fd_in, *fd_out;
    int ret  = 0;
    size_t size = 0;
    const char* input_file = luaL_checklstring(L, 1, &size);
    const char* output_file = luaL_checklstring(L, 2, &size);

    fd_in = fopen(input_file, "r");
    if (fd_in == NULL){
        LLOGE("[zlib] open the input file : %s error!", input_file);
        ret = -1;
        goto _exit;
    }
    fd_out = fopen(output_file, "w+");
    if (fd_out == NULL){
        LLOGE("[zlib] open the output file : %s error!", output_file);
        ret = -1;
        goto _exit;
    }
    ret = def(fd_in, fd_out, Z_BEST_COMPRESSION);
    if (ret != Z_OK){
        zerr(ret);
        LLOGE("[zlib] compress file error!\n");
        return ret;
    }
    lua_pushboolean(L, 1);
    return 1;

_exit:
    if(fd_in != NULL){
        fclose(fd_in);
    }
    if(fd_out != NULL){
        fclose(fd_out);
    }
    lua_pushboolean(L, 0);
    return 1;
}

static int luat_zlib_dcompress(lua_State *L){
    FILE *fd_in, *fd_out;
    int ret  = 0;
    size_t size = 0;
    const char* input_file = luaL_checklstring(L, 1, &size);
    const char* output_file = luaL_checklstring(L, 2, &size);

    fd_in = fopen(input_file, "r");
    if (fd_in == NULL){
        LLOGE("[zlib] open the input file : %s error!", input_file);
        ret = -1;
        goto _exit;
    }
    fd_out = fopen(output_file, "w+");
    if (fd_out == NULL){
        LLOGE("[zlib] open the output file : %s error!", output_file);
        ret = -1;
        goto _exit;
    }
    ret = inf(fd_in, fd_out);
    if (ret != Z_OK)
    {
        zerr(ret);
        LLOGE("[zlib] decompress file error!");
        return ret;
    }
    lua_pushboolean(L, 1);
    return 1;

_exit:
    if(fd_in != NULL){
        fclose(fd_in);
    }
    if(fd_out != NULL){
        fclose(fd_out);
    }
    lua_pushboolean(L, 0);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_zlib[] =
{
    { "c",      luat_zlib_compress,    0},
    { "d",      luat_zlib_dcompress,   0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_zlib( lua_State *L ) {
    luat_newlib(L, reg_zlib);
    return 1;
}
