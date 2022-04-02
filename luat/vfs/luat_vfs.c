

#include "luat_base.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "vfs"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

#ifdef getc
#undef getc
#endif

#ifdef feof
#undef feof
#endif

#ifdef ferror
#undef ferror
#endif

static luat_vfs_t vfs= {0};

int luat_vfs_init(void* params) {
    memset(&vfs, 0, sizeof(vfs));
    return 0;
}

int luat_vfs_reg(const struct luat_vfs_filesystem* fs) {
    for (size_t i = 0; i < LUAT_VFS_FILESYSTEM_MAX; i++)
    {
        if (vfs.fsList[i] == NULL) {
            vfs.fsList[i] = (struct luat_vfs_filesystem*)fs;
            //LLOGD("register fs %s", fs->name);
            return 0;
        }
        if (vfs.fsList[i] == fs) {
            return 0;
        }
    }
    LLOGE("too many filesystem !!!");
    return -1;
}

FILE* luat_vfs_add_fd(FILE* fd, luat_vfs_mount_t * mount) {
    for (size_t i = 1; i <= LUAT_VFS_FILESYSTEM_FD_MAX; i++)
    {
        if (vfs.fds[i].fsMount == NULL) {
            vfs.fds[i].fsMount = mount == NULL ? &vfs.mounted[0] : mount;
            vfs.fds[i].fd = fd;
            //LLOGD("luat_vfs_add_fd %p => %d", fd, i+1);
            return (FILE*)i;
        }
    }
    return NULL;
}

int luat_vfs_rm_fd(FILE* fd) {
    int _fd = (int)fd;
    if (_fd <= 0 || _fd > LUAT_VFS_FILESYSTEM_FD_MAX)
        return -1;
    //LLOGD("luat_vfs_rm_fd %d => %d", (int)fd, _fd);
    vfs.fds[_fd].fd = NULL;
    vfs.fds[_fd].fsMount = NULL;
    return -1;
}

luat_vfs_mount_t * getmount(const char* filename) {
    for (int j = LUAT_VFS_FILESYSTEM_MOUNT_MAX - 1; j >= 0; j--) {
        if (vfs.mounted[j].ok == 0)
            continue;
        if (strncmp(vfs.mounted[j].prefix, filename, strlen(vfs.mounted[j].prefix)) == 0) {
            return &vfs.mounted[j];
        }
    }
    LLOGW("not mount point match %s", filename);
    return NULL;
}

int luat_fs_mkfs(luat_fs_conf_t *conf) {
    for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++) {
        if (vfs.mounted[j].ok == 0)
            continue;
        if (strcmp(vfs.mounted[j].prefix, conf->mount_point) == 0 && vfs.mounted[j].fs->opts.mkfs != NULL) {
            return vfs.mounted[j].fs->opts.mkfs(vfs.mounted[j].userdata, conf);
        }
    }
    LLOGE("no such mount point %s", conf->mount_point);
    return -1;
}

int luat_fs_mount(luat_fs_conf_t *conf) {
    //LLOGD("mount %s %s", conf->filesystem, conf->mount_point);
    for (int i = 0; i < LUAT_VFS_FILESYSTEM_MAX; i++) {
        if (vfs.fsList[i] != NULL && strcmp(vfs.fsList[i]->name, conf->filesystem) == 0) {
            for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++)
            {
                if (vfs.mounted[j].fs == NULL) {
                    int ret = vfs.fsList[i]->opts.mount(&vfs.mounted[j].userdata, conf);
                    if (ret == 0) {
                        vfs.mounted[j].fs = vfs.fsList[i];
                        vfs.mounted[j].ok = 1;
                        memcpy(vfs.mounted[j].prefix, conf->mount_point, strlen(conf->mount_point) + 1);
                    }
                    else
                        LLOGD("mount error ret %d", ret);
                    return ret;
                }
            }
            LLOGE("too many filesystem mounted!!");
            return -2;
        }
    }
    LLOGE("no such filesystem %s", conf->filesystem);
    return -1;
}
int luat_fs_umount(luat_fs_conf_t *conf) {
    for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++) {
        if (vfs.mounted[j].ok == 0)
            continue;
        if (strcmp(vfs.mounted[j].prefix, conf->mount_point) == 0) {
            // TODO 关闭对应的FD
            return vfs.mounted[j].fs->opts.umount(vfs.mounted[j].userdata, conf);
        }
    }
    LLOGE("no such mount point %s", conf->mount_point);
    return -1;
}
int luat_fs_info(const char* path, luat_fs_info_t *conf) {
    for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++) {
        if (vfs.mounted[j].ok == 0)
            continue;
        if (strcmp(vfs.mounted[j].prefix, path) == 0) {
            return vfs.mounted[j].fs->opts.info(vfs.mounted[j].userdata, ((char*)path) + strlen(vfs.mounted[j].prefix), conf);
        }
    }
    LLOGE("no such mount point %s", path);
    return -1;
}

static luat_vfs_fd_t* getfd(FILE* fd) {
    int _fd = (int)fd;
    //LLOGD("search for vfs.fd = %d %p", _fd, fd);
    if (_fd <= 0 || _fd > LUAT_VFS_FILESYSTEM_FD_MAX) return NULL;
    if (vfs.fds[_fd].fsMount == NULL) {
        LLOGD("vfs.fds[%d] is nil", _fd);
        return NULL;
    }
    return &(vfs.fds[_fd]);
}

FILE* luat_fs_fopen(const char *filename, const char *mode) {
    
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->fopts.fopen == NULL) {
        LLOGD("fopen %s %s NOT matched mount", filename, mode);
        return NULL;
    }
    FILE* fd = mount->fs->fopts.fopen(mount->userdata, filename + strlen(mount->prefix), mode);
    if (fd) {
        for (size_t i = 1; i <= LUAT_VFS_FILESYSTEM_FD_MAX; i++)
        {
            if (vfs.fds[i].fsMount == NULL) {
                vfs.fds[i].fsMount = mount;
                vfs.fds[i].fd = fd;
                //LLOGD("fopen %s %s vfd=%ld fd=%ld", filename, mode, i, fd);
                return (FILE*)i;
            }
        }
        mount->fs->fopts.fclose(mount->userdata, fd);
        LLOGE("fopen %s %s too many open file!!!", filename, mode);
    }
    LLOGD("fopen %s %s not found", filename, mode);
    return NULL;
}

int luat_fs_feof(FILE* stream) {
    //LLOGD("call %s %d","feof", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) 
        return 1;
    return fd->fsMount->fs->fopts.feof(fd->fsMount->userdata, fd->fd);
}

int luat_fs_ferror(FILE* stream) {
    //LLOGD("call %s %d","ferror", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.ferror == NULL) 
        return 0;
    return fd->fsMount->fs->fopts.ferror(fd->fsMount->userdata, fd->fd);
}

int luat_fs_ftell(FILE* stream) {
    //LLOGD("call %s %d","ftell", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.ftell == NULL) 
        return 0;
    return fd->fsMount->fs->fopts.ftell(fd->fsMount->userdata, fd->fd);
}

int luat_fs_getc(FILE* stream) {
    //LLOGD("call %s %d","getc", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        LLOGD("FILE* stream is invaild!!!");
        return -1;
    }
    if (fd->fsMount->fs->fopts.getc == NULL) {
        LLOGD("miss getc");
        return -1;
    }
    return fd->fsMount->fs->fopts.getc(fd->fsMount->userdata, fd->fd);
}

// char luat_fs_getc(FILE* stream);
// int luat_fs_ftell(FILE* stream);
// int luat_fs_feof(FILE* stream);
// int luat_fs_ferror(FILE *stream);
int luat_fs_fclose(FILE* stream) {
    //LLOGD("fclose %d", (int)stream);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        return 0;
    }
    int ret = fd->fsMount->fs->fopts.fclose(fd->fsMount->userdata, fd->fd);
    int _fd = (int)stream;
    vfs.fds[_fd].fsMount = NULL;
    vfs.fds[_fd].fd = NULL;
    return ret;
}

int luat_fs_fseek(FILE* stream, long int offset, int origin) {
    //LLOGD("call %s %d","fseek", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fseek == NULL) 
        return -1;
    return fd->fsMount->fs->fopts.fseek(fd->fsMount->userdata, fd->fd, offset, origin);
}

size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    //LLOGD("call %s %d","vfs_fread", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fread == NULL) 
        return 0;
    return fd->fsMount->fs->fopts.fread(fd->fsMount->userdata, ptr, size, nmemb, fd->fd);
}
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fwrite == NULL) 
        return 0;
    return fd->fsMount->fs->fopts.fwrite(fd->fsMount->userdata, ptr, size, nmemb, fd->fd);
}



int luat_fs_remove(const char *filename) {
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->opts.remove == NULL) return -1;
    return mount->fs->opts.remove(mount->userdata, filename + strlen(mount->prefix));
}
int luat_fs_rename(const char *old_filename, const char *new_filename) {
    luat_vfs_mount_t *old_mount = getmount(old_filename);
    luat_vfs_mount_t *new_mount = getmount(new_filename);\
    if (old_filename == NULL || new_mount != old_mount || old_mount->fs->opts.rename == NULL) {
        return -1;
    }
    return old_mount->fs->opts.rename(old_mount->userdata, old_filename + strlen(old_mount->prefix),
                                      new_filename + strlen(old_mount->prefix));
}
size_t luat_fs_fsize(const char *filename) {
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->opts.fsize == NULL) return 0;
    return mount->fs->opts.fsize(mount->userdata, filename + strlen(mount->prefix));
}
int luat_fs_fexist(const char *filename) {
    //LLOGD("exist? %s", filename);
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->opts.fexist == NULL) return 0;
    return mount->fs->opts.fexist(mount->userdata,  filename + strlen(mount->prefix));
}
int luat_fs_readline(char * buf, int bufsize, FILE * stream){
    int get_len = 0;
    char buff[2];
    for (size_t i = 0; i <= bufsize; i++){
        memset(buff, 0, 2);
        int len = luat_fs_fread(buff, sizeof(char), 1, stream);
        if (len>0){
            get_len = get_len+len;
            memcpy(buf+i, buff, len);
            if (memcmp(buff, "\n", 1)==0){
                break;
            }
        }else{
            break;
        }
    }
    return get_len;
}

// TODO 文件夹相关的API
//int luat_fs_diropen(char const* _FileName);

int luat_fs_mkdir(char const* _DirName) {
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL || mount->fs->opts.mkdir == NULL) return 0;
    return mount->fs->opts.mkdir(mount->userdata,  _DirName + strlen(mount->prefix));
}
int luat_fs_rmdir(char const* _DirName) {
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL || mount->fs->opts.rmdir == NULL) return 0;
    return mount->fs->opts.rmdir(mount->userdata,  _DirName + strlen(mount->prefix));
}

int luat_fs_lsdir(char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    if (len == 0)
        return 0;
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL) {
        LLOGD("no such mount");
        return 0;
    }
    if (mount->fs->opts.lsdir == NULL) {
        LLOGD("such mount not support lsdir");
        return 0;
    }
    return mount->fs->opts.lsdir(mount->userdata,  _DirName + strlen(mount->prefix), ents, offset, len);
}

extern const struct luat_vfs_filesystem vfs_fs_luadb;
const char* luat_vfs_luadb_mmap(void* userdata, int fd);

const char* luat_vfs_mmap(FILE* stream) {
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL)
        return NULL;
    if (fd->fsMount->fs == &vfs_fs_luadb) {
        return luat_vfs_luadb_mmap(fd->fsMount->userdata, (int)fd->fd);
    }
    return NULL;
}

#endif
