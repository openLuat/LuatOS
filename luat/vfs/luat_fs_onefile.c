#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

typedef struct luat_fs_onefile
{
    char* ptr;
    uint32_t  size;
    uint32_t  offset;
}luat_fs_onefile_t;


// fs的默认实现, 指向poisx的stdio.h声明的方法
#ifdef LUAT_USE_FS_VFS

// #define PRINT_IT LLOGD("fd %p offset %d size %d", fd, fd->offset, fd->size)

FILE* luat_vfs_onefile_fopen(void* userdata, const char *filename, const char *mode) {
    //LLOGD("open onefile %s", filename);
    if (!strcmp("r", mode) || !strcmp("rb", mode)) {
        luat_fs_onefile_t* fd = luat_heap_malloc(sizeof(luat_fs_onefile_t));
        if (fd == NULL) {
            LLOGE("out of memory when malloc luat_fs_onefile_t");
            return NULL;
        }
        //LLOGD("fd %p userdata %p", fd, userdata);
        memcpy(fd, userdata, sizeof(luat_fs_onefile_t));
        fd->offset = 0;
        return (FILE*)fd;
    }
    return NULL;
}

int luat_vfs_onefile_getc(void* userdata, FILE* stream) {
    //LLOGD("getc %p %p", userdata, stream);
    luat_fs_onefile_t* fd = (luat_fs_onefile_t*)stream;
    //LLOGD("getc %p %p %d %d", userdata, stream, fd->offset, fd->size);
    if (fd->offset < fd->size) {
        uint8_t c = (uint8_t)fd->ptr[fd->offset];
        fd->offset ++;
        //LLOGD("getc %02X", c);
        return c;
    }
    return -1;
}

int luat_vfs_onefile_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    //LLOGD("fseek %p %p %d %d", userdata, stream, offset, origin);
    luat_fs_onefile_t* fd = (luat_fs_onefile_t*)stream;
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

int luat_vfs_onefile_ftell(void* userdata, FILE* stream) {
    luat_fs_onefile_t* fd = (luat_fs_onefile_t*)stream;
    //LLOGD("tell %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset;
}

int luat_vfs_onefile_fclose(void* userdata, FILE* stream) {
    luat_fs_onefile_t* fd = (luat_fs_onefile_t*)stream;
    //LLOGD("fclose %p %p %d %d", userdata, stream, fd->size, fd->offset);
    luat_heap_free(fd);
    return 0;
}
int luat_vfs_onefile_feof(void* userdata, FILE* stream) {
    luat_fs_onefile_t* fd = (luat_fs_onefile_t*)stream;
    //LLOGD("feof %p %p %d %d", userdata, stream, fd->size, fd->offset);
    return fd->offset >= fd->size ? 1 : 0;
}
int luat_vfs_onefile_ferror(void* userdata, FILE *stream) {
    return 0;
}
size_t luat_vfs_onefile_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_fs_onefile_t* fd = (luat_fs_onefile_t*)stream;
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
size_t luat_vfs_onefile_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    return 0;
}
int luat_vfs_onefile_remove(void* userdata, const char *filename) {
    return -1;
}
int luat_vfs_onefile_rename(void* userdata, const char *old_filename, const char *new_filename) {
    return -1;
}
int luat_vfs_onefile_fexist(void* userdata, const char *filename) {
    return 1;
}

size_t luat_vfs_onefile_fsize(void* userdata, const char *filename) {
    luat_fs_onefile_t *fd = (luat_fs_onefile_t*)(userdata);
    //LLOGD("fsize %p %p %d %d", userdata, fd);
    return fd->size;
}

int luat_vfs_onefile_mkfs(void* userdata, luat_fs_conf_t *conf) {
    return -1;
}
int luat_vfs_onefile_mount(void** userdata, luat_fs_conf_t *conf) {
    *userdata = (luat_fs_onefile_t*)conf->busname;
    return 0;
}
int luat_vfs_onefile_umount(void* userdata, luat_fs_conf_t *conf) {
    return 0;
}

int luat_vfs_onefile_mkdir(void* userdata, char const* _DirName) {
    return -1;
}
int luat_vfs_onefile_rmdir(void* userdata, char const* _DirName) {
    return -1;
}
int luat_vfs_onefile_info(void* userdata, const char* path, luat_fs_info_t *conf) {

    memcpy(conf->filesystem, "onefile", strlen("onefile")+1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 512;
    return 0;
}

#define T(name) .name = luat_vfs_onefile_##name
const struct luat_vfs_filesystem vfs_fs_onefile = {
    .name = "onefile",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
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

