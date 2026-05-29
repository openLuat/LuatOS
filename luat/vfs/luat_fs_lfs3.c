
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "vfs.lfs3"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

#include "lfs3.h"

FILE* luat_vfs_lfs3_fopen(void* userdata, const char *filename, const char *mode) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t *file = (lfs3_file_t*)luat_heap_malloc(sizeof(lfs3_file_t));
    if (file == NULL) {
        LLOGD("out of memory when open file %s", filename);
        return NULL;
    }
    memset(file, 0, sizeof(lfs3_file_t));
    uint32_t flag = 0;
    if (!strcmp("r+", mode) || !strcmp("r+b", mode) || !strcmp("rb+", mode)) {
        flag = LFS3_O_RDWR | LFS3_O_CREAT;
    }
    else if(!strcmp("w+", mode) || !strcmp("w+b", mode) || !strcmp("wb+", mode)) {
        flag = LFS3_O_RDWR | LFS3_O_CREAT | LFS3_O_TRUNC;
    }
    else if(!strcmp("a+", mode) || !strcmp("a+b", mode) || !strcmp("ab+", mode)) {
        flag = LFS3_O_APPEND | LFS3_O_CREAT | LFS3_O_WRONLY;
    }
    else if(!strcmp("w", mode) || !strcmp("wb", mode)) {
        flag = LFS3_O_RDWR | LFS3_O_CREAT | LFS3_O_TRUNC;
    }
    else if(!strcmp("r", mode) || !strcmp("rb", mode)) {
        flag = LFS3_O_RDONLY;
    }
    else if(!strcmp("a", mode) || !strcmp("ab", mode)) {
        flag = LFS3_O_APPEND | LFS3_O_CREAT | LFS3_O_WRONLY;
    }
    else {
        LLOGW("bad file open mode %s, fallback to 'r'", mode);
        flag = LFS3_O_RDONLY;
    }
    int ret = lfs3_file_open(fs, file, filename, flag);
    if (ret < 0) {
        luat_heap_free(file);
        return NULL;
    }
    return (FILE*)file;
}

int luat_vfs_lfs3_getc(void* userdata, FILE* stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    char buff = 0;
    lfs3_ssize_t ret = lfs3_file_read(fs, file, &buff, 1);
    if (ret != 1)
        return -1;
    return (int)(unsigned char)buff;
}

int luat_vfs_lfs3_fseek(void* userdata, FILE* stream, long int offset, int origin) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    lfs3_soff_t ret = lfs3_file_seek(fs, file, (lfs3_soff_t)offset, (uint32_t)origin);
    return ret < 0 ? -1 : 0;
}

int luat_vfs_lfs3_ftell(void* userdata, FILE* stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    lfs3_soff_t ret = lfs3_file_tell(fs, file);
    return ret < 0 ? -1 : (int)ret;
}

int luat_vfs_lfs3_fclose(void* userdata, FILE* stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    lfs3_file_close(fs, file);
    if (file != NULL)
        luat_heap_free(file);
    return 0;
}

int luat_vfs_lfs3_feof(void* userdata, FILE* stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    if (lfs3_file_size(fs, file) <= lfs3_file_tell(fs, file))
        return 1;
    return 0;
}

int luat_vfs_lfs3_ferror(void* userdata, FILE *stream) {
    return 0;
}

size_t luat_vfs_lfs3_fread(void* userdata, void *ptr, size_t size, size_t nmemb, FILE *stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    lfs3_ssize_t ret = lfs3_file_read(fs, file, ptr, (lfs3_size_t)(size * nmemb));
    return ret < 0 ? 0 : (size_t)ret;
}

size_t luat_vfs_lfs3_fwrite(void* userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    lfs3_ssize_t ret = lfs3_file_write(fs, file, ptr, (lfs3_size_t)(size * nmemb));
    return ret < 0 ? 0 : (size_t)ret;
}

int luat_vfs_lfs3_fflush(void* userdata, FILE *stream) {
    lfs3_t* fs = (lfs3_t*)userdata;
    lfs3_file_t* file = (lfs3_file_t*)stream;
    int ret = lfs3_file_sync(fs, file);
    return ret < 0 ? ret : 0;
}

int luat_vfs_lfs3_remove(void* userdata, const char *filename) {
    lfs3_t* fs = (lfs3_t*)userdata;
    return lfs3_remove(fs, filename);
}

int luat_vfs_lfs3_rename(void* userdata, const char *old_filename, const char *new_filename) {
    lfs3_t* fs = (lfs3_t*)userdata;
    return lfs3_rename(fs, old_filename, new_filename);
}

int luat_vfs_lfs3_fexist(void* userdata, const char *filename) {
    FILE* fd = luat_vfs_lfs3_fopen(userdata, filename, "rb");
    if (fd) {
        luat_vfs_lfs3_fclose(userdata, fd);
        return 1;
    }
    return 0;
}

size_t luat_vfs_lfs3_fsize(void* userdata, const char *filename) {
    FILE *fd;
    size_t size = 0;
    fd = luat_vfs_lfs3_fopen(userdata, filename, "rb");
    if (fd) {
        lfs3_soff_t ret = lfs3_file_size((lfs3_t*)userdata, (lfs3_file_t*)fd);
        size = ret < 0 ? 0 : (size_t)ret;
        luat_vfs_lfs3_fclose(userdata, fd);
    }
    return size;
}

int luat_vfs_lfs3_mkfs(void* userdata, luat_fs_conf_t *conf) {
    lfs3_t* fs = (lfs3_t*)userdata;
    if (fs != NULL && fs->cfg != NULL) {
        int ret = lfs3_format(fs, 0, fs->cfg);
        if (ret < 0)
            return ret;
        return lfs3_mount(fs, 0, fs->cfg);
    }
    return -1;
}

int luat_vfs_lfs3_mount(void** userdata, luat_fs_conf_t *conf) {
    *userdata = (void*)conf->busname;
    return 0;
}

int luat_vfs_lfs3_umount(void* userdata, luat_fs_conf_t *conf) {
    LLOGE("not support yet : umount");
    return 0;
}

static int dir2name(char* buff, char const* _DirName) {
    size_t dirlen = strlen(_DirName);
    if (dirlen > 63) {
        LLOGE("dir too long!! %s", _DirName);
        return -1;
    }
    else if (dirlen < 1) {
        LLOGE("dir too short!! %s", _DirName);
        return -1;
    }
    memcpy(buff, _DirName, dirlen);
    if (buff[dirlen - 1] == '/') {
        buff[dirlen - 1] = 0;
    }
    return 0;
}

int luat_vfs_lfs3_mkdir(void* userdata, char const* _DirName) {
    lfs3_t* fs = (lfs3_t*)userdata;
    char buff[64] = {0};
    if (_DirName == NULL) {
        return -1;
    }
    if (_DirName[0] == 0) {
        return 0;
    }
    if (dir2name(buff, _DirName)) {
        return -1;
    }
    if (buff[0] == 0) {
        return 0;
    }
    int ret = lfs3_mkdir(fs, buff);
    return ret == LFS3_ERR_OK ? 0 : -1;
}

int luat_vfs_lfs3_rmdir(void* userdata, char const* _DirName) {
    lfs3_t* fs = (lfs3_t*)userdata;
    char buff[64] = {0};
    if (dir2name(buff, _DirName)) {
        return -1;
    }
    int ret = lfs3_remove(fs, buff);
    return ret == LFS3_ERR_OK ? 0 : -1;
}

int luat_vfs_lfs3_lsdir(void* userdata, char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    lfs3_t* fs = (lfs3_t*)userdata;
    int ret, num = 0;
    lfs3_dir_t *dir;
    struct lfs3_info info;
    char buff[64] = {0};
    if (strlen(_DirName) == 0) {
        // root dir, OK
    }
    else if (dir2name(buff, _DirName)) {
        return -1;
    }

    dir = luat_heap_malloc(sizeof(lfs3_dir_t));
    if (dir == NULL) {
        return 0;
    }
    ret = lfs3_dir_open(fs, dir, buff);
    if (ret < 0) {
        luat_heap_free(dir);
        return 0;
    }

    // Skip `offset` entries
    for (size_t i = 0; i < offset; i++) {
        ret = lfs3_dir_read(fs, dir, &info);
        if (ret == LFS3_ERR_NOENT || ret < 0) {
            lfs3_dir_close(fs, dir);
            luat_heap_free(dir);
            return 0;
        }
    }

    while (num < (int)len) {
        ret = lfs3_dir_read(fs, dir, &info);
        if (ret == LFS3_ERR_NOENT) {
            break; // end of directory
        }
        if (ret < 0) {
            lfs3_dir_close(fs, dir);
            luat_heap_free(dir);
            return 0;
        }
        // skip . and ..
        if (info.type == LFS3_TYPE_DIR &&
            (memcmp(info.name, ".", 2) == 0 || memcmp(info.name, "..", 3) == 0))
            continue;
        ents[num].d_type = info.type - 1; // lfs3: REG=1->0, DIR=2->1
        strcpy(ents[num].d_name, info.name);
        num++;
    }
    lfs3_dir_close(fs, dir);
    luat_heap_free(dir);
    return num;
}

int luat_vfs_lfs3_info(void* userdata, const char* path, luat_fs_info_t *conf) {
    lfs3_t* fs = (lfs3_t*)userdata;
    struct lfs3_fsinfo fsinfo = {0};
    memcpy(conf->filesystem, "lfs3", strlen("lfs3") + 1);
    conf->type = 0;
    int ret = lfs3_fs_stat(fs, &fsinfo);
    if (ret == 0) {
        conf->total_block = (uint32_t)fsinfo.block_count;
        conf->block_size  = (uint32_t)fsinfo.block_size;
    } else {
        conf->total_block = fs->cfg->block_count;
        conf->block_size  = fs->cfg->block_size;
    }
    lfs3_sblock_t used = lfs3_fs_usage(fs);
    conf->block_used = (uint32_t)(used < 0 ? 0 : used);
    return 0;
}

int luat_vfs_lfs3_truncate(void* userdata, const char *filename, size_t len) {
    FILE *fd;
    int ret = -1;
    fd = luat_vfs_lfs3_fopen(userdata, filename, "wb");
    if (fd) {
        ret = lfs3_file_truncate((lfs3_t*)userdata, (lfs3_file_t*)fd, (lfs3_off_t)len);
        luat_vfs_lfs3_fclose(userdata, fd);
    }
    return ret;
}

void* luat_vfs_lfs3_opendir(void* userdata, const char *_DirName) {
    lfs3_dir_t *dir = (lfs3_dir_t*)luat_heap_malloc(sizeof(lfs3_dir_t));
    if (dir == NULL) {
        LLOGD("out of memory when opendir %s", _DirName);
        return NULL;
    }
    memset(dir, 0, sizeof(lfs3_dir_t));
    int ret = lfs3_dir_open((lfs3_t*)userdata, dir, _DirName);
    if (ret < 0) {
        luat_heap_free(dir);
        return NULL;
    }
    return (void*)dir;
}

int luat_vfs_lfs3_closedir(void* userdata, void* dir) {
    lfs3_dir_close((lfs3_t*)userdata, (lfs3_dir_t*)dir);
    if (dir) luat_heap_free(dir);
    return 0;
}

#define T(name) .name = luat_vfs_lfs3_##name

extern const struct luat_vfs_filesystem vfs_fs_lfs3;

void lfs3_vfs_init(void) {
    luat_vfs_reg(&vfs_fs_lfs3);
}

const struct luat_vfs_filesystem vfs_fs_lfs3 = {
    .name = "lfs3",
    .opts = {
        T(mkfs),
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
        T(truncate),
        T(opendir),
        T(closedir)
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

#endif
