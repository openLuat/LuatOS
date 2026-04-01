
#define _DEFAULT_SOURCE
#include "luat_base.h"
#include "luat_fs.h"
#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

#define TAG "luat.fs"

#ifdef LUA_USE_VFS_FILENAME_OFFSET
#define FILENAME_OFFSET (filename[0] == '/' ? 1 : 0)
#else
#define FILENAME_OFFSET 0
#endif


// fs的默认实现, 指向poisx的stdio.h声明的方法
FILE* luat_vfs_posix_fopen(void* userdata, const char *filename, const char *mode) {
    (void)userdata;
    char tmp[16] = {0};
    int flag = 0;
    for (size_t i = 0; i < strlen(mode); i++)
    {
        if (mode[i] == 'b') {
            flag = 1;
            break;
        }
    }
    memcpy(tmp, mode, strlen(mode));
    if (!flag)
        tmp[strlen(mode)] = 'b';
    mode = tmp;

    // LLOGD("fopen %s %s", filename + FILENAME_OFFSET, mode);
    FILE* fd = fopen(filename + FILENAME_OFFSET, mode);
    if (!fd) {
        // LLOGW("fopen %s %s fail", filename + FILENAME_OFFSET, mode);
    }
    return fd;
}

int luat_vfs_posix_getc(void* userdata, FILE* stream) {
    //LLOGD("posix_getc %p", stream);
    (void)userdata;
    #ifdef LUAT_FS_NO_POSIX_GETC
    uint8_t buff = 0;
    int ret = luat_fs_fread(&buff, 1, 1, stream);
    if (ret == 1) {
        return buff;
    }
    return -1;
    #else
    return getc(stream);
    #endif
}

int luat_vfs_posix_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    (void)userdata;
    return fseek(stream, offset, origin);
}

int luat_vfs_posix_ftell(void* userdata, FILE* stream) {
    (void)userdata;
    return ftell(stream);
}

int luat_vfs_posix_fclose(void* userdata, FILE* stream) {
    (void)userdata;
    return fclose(stream);
}
int luat_vfs_posix_feof(void* userdata, FILE* stream) {
    (void)userdata;
    return feof(stream);
}
int luat_vfs_posix_ferror(void* userdata, FILE *stream) {
    (void)userdata;
    return ferror(stream);
}
size_t luat_vfs_posix_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    int ret = fread(ptr, size, nmemb, stream);
    // LLOGD("fread %p %d %d", stream, size * nmemb, ret);
    if (ret <= 0)
        return 0;
    return ret;
}
size_t luat_vfs_posix_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    (void)userdata;
    int ret = fwrite(ptr, size, nmemb, stream);
    // LLOGD("fwrite %p %d %d", stream, size * nmemb, ret);
    if (ret <= 0)
        return 0;
    fflush(stream);
    return size * nmemb;
}

int luat_vfs_posix_fflush(void* userdata, FILE *stream) {
    return fflush(stream);
}

int luat_vfs_posix_remove(void* userdata, const char *filename) {
    (void)userdata;
    return remove(filename + FILENAME_OFFSET);
}
int luat_vfs_posix_rename(void* userdata, const char *old_filename, const char *new_filename) {
    (void)userdata;
#if LUA_USE_VFS_FILENAME_OFFSET
    return rename(old_filename + (old_filename[0] == '/' ? 1 : 0), new_filename + (new_filename[0] == '/' ? 1 : 0));
#else
    return rename(old_filename, new_filename);
#endif
}
int luat_vfs_posix_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_posix_fopen(userdata, filename + FILENAME_OFFSET, "rb");
    if (fd) {
        luat_vfs_posix_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_posix_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_posix_fopen(userdata, filename + FILENAME_OFFSET, "rb");
    if (fd) {
        luat_vfs_posix_fseek(userdata, fd, 0, SEEK_END);
        size = luat_vfs_posix_ftell(userdata, fd); 
        luat_vfs_posix_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_posix_mkfs(void* userdata, luat_fs_conf_t *conf) {
    (void)userdata;
    (void)conf;
    LLOGE("not support yet : mkfs");
    return -1;
}
int luat_vfs_posix_mount(void** userdata, luat_fs_conf_t *conf) {
    (void)userdata;
    (void)conf;
    //LLOGE("not support yet : mount");
    return 0;
}
int luat_vfs_posix_umount(void* userdata, luat_fs_conf_t *conf) {
    (void)userdata;
    (void)conf;
    //LLOGE("not support yet : umount");
    return 0;
}

#if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS) || defined(LUA_USE_MACOSX)
#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <sys/stat.h>
#endif
#if defined(LUA_USE_LINUX) || defined(LUA_USE_MACOSX)
#include <unistd.h>
#endif

static int luat_vfs_posix_dir_path(const char* dir_name, char* buff, size_t buff_size) {
    size_t dir_name_len;
    if (dir_name == NULL || buff == NULL || buff_size == 0) {
        return -1;
    }
    dir_name_len = strlen(dir_name);
    if (dir_name_len == 0) {
        if (buff_size < 2) {
            return -1;
        }
        buff[0] = '.';
        buff[1] = 0;
    }
    else if (dir_name[0] == '/') {
        if (dir_name_len + 2 > buff_size) {
            return -1;
        }
        buff[0] = '.';
        memcpy(buff + 1, dir_name, dir_name_len + 1);
    }
    else {
        if (dir_name_len + 1 > buff_size) {
            return -1;
        }
        memcpy(buff, dir_name, dir_name_len + 1);
    }
#if defined(LUA_USE_WINDOWS)
    for (size_t i = 0; buff[i] != 0; i++)
    {
        if (buff[i] == '/') {
            buff[i] = '\\';
        }
    }
#endif
    return 0;
}

int luat_vfs_posix_mkdir(void* userdata, char const* filename) {
    (void)userdata;
#if defined(LUA_USE_WINDOWS)
    printf("mkdir %s\n", filename + FILENAME_OFFSET);
    return mkdir(filename + FILENAME_OFFSET);
#elif defined(LUA_USE_LINUX) || defined(LUA_USE_MACOSX)
    return mkdir(filename + FILENAME_OFFSET, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
#else
    return -1;
#endif
}
int luat_vfs_posix_rmdir(void* userdata, char const* filename) {
    (void)userdata;
#if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS) || defined(LUA_USE_MACOSX)
    return rmdir(filename + FILENAME_OFFSET);
#else
    return -1;
#endif
}
int luat_vfs_posix_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    (void)userdata;
    (void)path;
    (void)conf;
    memcpy(conf->filesystem, "posix", strlen("posix")+1);
    conf->type = 0;
    conf->total_block = 0;
    conf->block_used = 0;
    conf->block_size = 512;
    return 0;
}

#if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS) || defined(LUA_USE_MACOSX)
void* luat_vfs_posix_opendir(void* fsdata, char const* _DirName) {
    char buff[256] = {0};
    (void)fsdata;
    if (luat_vfs_posix_dir_path(_DirName, buff, sizeof(buff))) {
        LLOGW("dir name too long %s", _DirName);
        return NULL;
    }
    return opendir(buff);
}

int luat_vfs_posix_closedir(void* fsdata, void* dir) {
    (void)fsdata;
    if (dir == NULL) {
        return -1;
    }
    return closedir((DIR*)dir);
}

int luat_vfs_posix_lsdir(void* fsdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    (void)fsdata;
    DIR *dp;
    struct dirent *ep;
    int index = 0;

    // LLOGD("opendir file %s %d %d", _DirName, offset, len);
    char buff[256] = {0};
    if (luat_vfs_posix_dir_path(_DirName, buff, sizeof(buff))) {
        LLOGW("dir name too long %s", _DirName);
        return 0;
    }

    dp = opendir (buff);
    if (dp != NULL)
    {
        while ((ep = readdir (dp)) != NULL) {
            //LLOGW("offset %d len %d", offset, len);
            if (offset > 0) {
                offset --;
                continue;
            }
            // 如果名称是 . 和 .. 就跳过
            if (strcmp(ep->d_name, ".") == 0 || strcmp(ep->d_name, "..") == 0) {
                continue;
            }
            if (len > 0) {
                memcpy(ents[index].d_name, ep->d_name, strlen(ep->d_name) + 1);
                if (ep->d_type == DT_REG) {
                    ents[index].d_type = 0;
                }
                else {
                    ents[index].d_type = 1;
                }
                index++;
                len --;
            }
            else {
                break;
            }
        }

        (void) closedir (dp);
        return index;
    }
    else {
        LLOGW("opendir file %s failed", _DirName);
    }
    return 0;
}
#else
void* luat_vfs_posix_opendir(void* fsdata, char const* _DirName) {
    return NULL;
}

int luat_vfs_posix_closedir(void* fsdata, void* dir) {
    return -1;
}

int luat_vfs_posix_lsdir(void* fsdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    return 0;
}
#endif

#ifdef AIR302
int luat_vfs_posix_truncate(void* fsdata, char const* path, size_t len) {
    return -1;
}
#else
#if !defined(LUA_USE_WINDOWS)
int truncate(const char *path, off_t length);
#endif

int luat_vfs_posix_truncate(void* fsdata, char const* filename, size_t len) {
    (void)fsdata;
    #if defined(LUA_USE_WINDOWS)
    FILE* fd = fopen(filename + FILENAME_OFFSET, "w+b");
    if (fd) {
        _chsize( fileno(fd), len);
        fclose(fd);
    }
    #else
    truncate(filename + FILENAME_OFFSET, len);
    #endif
    return 0;
}
#endif

#define T(name) .name = luat_vfs_posix_##name
const struct luat_vfs_filesystem vfs_fs_posix = {
    .name = "posix",
    .opts = {
        .mkfs = NULL,
        T(mount),
        T(umount),
        T(mkdir),
        T(rmdir),
        T(lsdir),
        T(remove),
        T(rename),
        T(fsize),
        T(fexist),
        T(info),
        T(opendir),
        T(closedir),
        T(truncate)
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
        T(fwrite),
        T(fflush)
    }
};




