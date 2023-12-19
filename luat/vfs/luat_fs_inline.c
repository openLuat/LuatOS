#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#include "luat_luadb.h"

typedef struct luat_fs_inline
{
    const char* ptr;
    uint32_t  size;
    uint32_t  offset;
}luat_fs_inline_t;

#ifdef LUAT_CONF_VM_64bit
extern const luadb_file_t luat_inline2_libs_64bit_size64[];
extern const luadb_file_t luat_inline2_libs_64bit_size32[];
#else
extern const luadb_file_t luat_inline2_libs[];
#endif
extern const luadb_file_t luat_inline2_libs_source[];

#ifdef LUAT_USE_FS_VFS

FILE* luat_vfs_inline_fopen(void* userdata, const char *filename, const char *mode) {
    //LLOGD("open inline %s", filename);
    const luadb_file_t* file = NULL;
#ifdef LUAT_CONF_USE_LIBSYS_SOURCE
    file = luat_inline2_libs_source;
#else
#ifdef LUAT_CONF_VM_64bit
    #if defined(LUA_USE_LINUX) || (defined(LUA_USE_WINDOWS) && defined(__XMAKE_BUILD__))
    file = luat_inline2_libs_64bit_size64;
    #else
    file = luat_inline2_libs_64bit_size32;
    #endif
#else
    file = luat_inline2_libs;
#endif
#endif

    if (!strcmp("r", mode) || !strcmp("rb", mode)) {
        luat_fs_inline_t* fd = luat_heap_malloc(sizeof(luat_fs_inline_t));
        if (fd == NULL) {
            LLOGE("out of memory when malloc luat_fs_inline_t");
            return NULL;
        }
        while (file != NULL && file->ptr != NULL) {
            if (!memcmp(file->name, filename, strlen(filename)+1)) {
                break;
            }
            file ++;
        }
        if (file == NULL || file->ptr == NULL) {
            //LLOGD("Not Found %s", filename);
            return NULL;
        }
        fd->ptr = file->ptr;
        fd->size = file->size;
        fd->offset = 0;
        return (FILE*)fd;
    }
    //LLOGD("Not Found %s", filename);
    return NULL;
}

int luat_vfs_inline_getc(void* userdata, FILE* stream) {
    //LLOGD("getc %p %p", userdata, stream);
    luat_fs_inline_t* fd = (luat_fs_inline_t*)stream;
    //LLOGD("getc %p %p %d %d", userdata, stream, fd->offset, fd->size);
    if (fd->offset < fd->size) {
        uint8_t c = (uint8_t)fd->ptr[fd->offset];
        fd->offset ++;
        //LLOGD("getc %02X", c);
        return c;
    }
    return -1;
}

int luat_vfs_inline_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    //LLOGD("fseek %p %p %d %d", userdata, stream, offset, origin);
    luat_fs_inline_t* fd = (luat_fs_inline_t*)stream;
    if (origin == SEEK_CUR) {
        fd->offset += offset;
        return 0;
    }
    else if (origin == SEEK_SET) {
        fd->offset = offset;
        return 0;
    }
    else {
        fd->offset = fd->size - offset;
        return 0;
    }
}

int luat_vfs_inline_ftell(void* userdata, FILE* stream) {
    luat_fs_inline_t* fd = (luat_fs_inline_t*)stream;
    //LLOGD("tell %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset;
}

int luat_vfs_inline_fclose(void* userdata, FILE* stream) {
    luat_fs_inline_t* fd = (luat_fs_inline_t*)stream;
    //LLOGD("fclose %p %p %d %d", userdata, stream, fd->size, fd->offset);
    luat_heap_free(fd);
    return 0;
}
int luat_vfs_inline_feof(void* userdata, FILE* stream) {
    luat_fs_inline_t* fd = (luat_fs_inline_t*)stream;
    //LLOGD("feof %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset >= fd->size ? 1 : 0;
}
int luat_vfs_inline_ferror(void* userdata, FILE *stream) {
    return 0;
}
size_t luat_vfs_inline_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_fs_inline_t* fd = (luat_fs_inline_t*)stream;
    //LLOGD("fread %p %p %d %d", userdata, stream, fd->size, fd->offset);
    //LLOGD("fread2 %p %p %d %d", userdata, stream, size * nmemb, fd->offset);
    size_t read_size = size*nmemb;
    if (fd->offset + read_size > fd->size) {
        read_size = fd->size - fd->offset;
    }
    memcpy(ptr, fd->ptr + fd->offset, read_size);
    fd->offset += read_size;
    return read_size;
}

int luat_vfs_inline_fexist(void* userdata, const char *filename) {
    const luadb_file_t* file = NULL;
#ifdef LUAT_CONF_VM_64bit
    #if defined(LUA_USE_LINUX) || (defined(LUA_USE_WINDOWS) && defined(__XMAKE_BUILD__))
    file = luat_inline2_libs_64bit_size64;
    #else
    file = luat_inline2_libs_64bit_size32;
    #endif
#else
    file = luat_inline2_libs;
#endif

    while (file != NULL && file->ptr != NULL) {
        if (!memcmp(file->name, filename, strlen(filename)+1)) {
            return 1;
        }
        file ++;
    }
    //LLOGD("Not Found %s", filename);
    return 0;
}

size_t luat_vfs_inline_fsize(void* userdata, const char *filename) {
    luat_fs_inline_t *fd = (luat_fs_inline_t*)(userdata);
    //LLOGD("fsize %p %p %d %d", userdata, fd);
    return fd->size;
}

int luat_vfs_inline_mount(void** userdata, luat_fs_conf_t *conf) {
    *userdata = (luat_fs_inline_t*)conf->busname;
    return 0;
}

int luat_vfs_inline_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    memcpy(conf->filesystem, "inline", strlen("inline")+1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 512;
    return 0;
}

#define T(name) .name = luat_vfs_inline_##name
const struct luat_vfs_filesystem vfs_fs_inline = {
    .name = "inline",
    .opts = {
        .mkfs = NULL,
        T(mount),
        .umount = NULL,
        .mkdir = NULL,
        .rmdir = NULL,
        .lsdir = NULL,
        .remove = NULL,
        .rename = NULL,
        T(fsize),
        T(fexist),
        T(info)
    },
    .fopts = {
        T(fopen),
        T(getc),
        T(fseek),
        T(ftell),
        T(fclose),
        T(feof),
        T(ferror),
        T(fread),
        .fwrite = NULL
    }
};
#endif

