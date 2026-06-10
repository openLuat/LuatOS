

#include "luat_base.h"
#include "luat_fs.h"
#include "luat_rtos_legacy.h"

#define LUAT_LOG_TAG "vfs"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

static void vfs_lock(luat_vfs_t *v) {
    if (v->vfs_mutex) luat_mutex_lock(v->vfs_mutex);
}
static void vfs_unlock(luat_vfs_t *v) {
    if (v->vfs_mutex) luat_mutex_unlock(v->vfs_mutex);
}

#ifdef getc
#undef getc
#endif

#ifdef feof
#undef feof
#endif

#ifdef ferror
#undef ferror
#endif

#ifdef __LUATOS__
extern const struct luat_vfs_filesystem vfs_fs_inline;
#endif

static luat_vfs_t vfs= {0};

int luat_vfs_init(void* params) {
    (void)params;
    memset(&vfs, 0, sizeof(vfs));
    vfs.vfs_mutex = luat_mutex_create();
#ifdef __LUATOS__
    luat_vfs_reg(&vfs_fs_inline);
#endif
    return 0;
}

int luat_vfs_reg(const struct luat_vfs_filesystem* fs) {
    vfs_lock(&vfs);
    for (size_t i = 0; i < LUAT_VFS_FILESYSTEM_MAX; i++)
    {
        if (vfs.fsList[i] == fs) {
            vfs_unlock(&vfs);
            return 0;
        }
        if (vfs.fsList[i] == NULL) {
            vfs.fsList[i] = (struct luat_vfs_filesystem*)fs;
            //LLOGD("register fs %s", fs->name);
            vfs_unlock(&vfs);
            return 0;
        }
    }
    LLOGE("too many filesystem !!!");
    vfs_unlock(&vfs);
    return -1;
}

FILE* luat_vfs_add_fd(FILE* fd, luat_vfs_mount_t * mount) {
    vfs_lock(&vfs);
    for (size_t i = 1; i <= LUAT_VFS_FILESYSTEM_FD_MAX; i++)
    {
        if (vfs.fds[i].fsMount == NULL) {
            vfs.fds[i].fsMount = mount == NULL ? &vfs.mounted[0] : mount;
            vfs.fds[i].fd = fd;
            //LLOGD("luat_vfs_add_fd %p => %d", fd, i+1);
            vfs_unlock(&vfs);
            return (FILE*)i;
        }
    }
    vfs_unlock(&vfs);
    return NULL;
}

int luat_vfs_rm_fd(FILE* fd) {
    vfs_lock(&vfs);
    int _fd = (int)fd;
    if (_fd <= 0 || _fd > LUAT_VFS_FILESYSTEM_FD_MAX) {
        vfs_unlock(&vfs);
        return -1;
    }
    //LLOGD("luat_vfs_rm_fd %d => %d", (int)fd, _fd);
    vfs.fds[_fd].fd = NULL;
    vfs.fds[_fd].fsMount = NULL;
    vfs_unlock(&vfs);
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
    vfs_lock(&vfs);
    for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++) {
        if (vfs.mounted[j].ok == 0)
            continue;
        if (strcmp(vfs.mounted[j].prefix, conf->mount_point) == 0 && vfs.mounted[j].fs->opts.mkfs != NULL) {
            int ret = vfs.mounted[j].fs->opts.mkfs(vfs.mounted[j].userdata, conf);
            vfs_unlock(&vfs);
            return ret;
        }
    }
    LLOGE("no such mount point %s", conf->mount_point);
    vfs_unlock(&vfs);
    return -1;
}

int luat_fs_mount(luat_fs_conf_t *conf) {
    vfs_lock(&vfs);
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
#ifdef __LUATOS__
                        if (j == 0) {
                            // 挂载内嵌文件系统
                            vfs.mounted[j+1].fs = (struct luat_vfs_filesystem*)&vfs_fs_inline;
                            vfs.mounted[j+1].ok = 1;
                            memcpy(vfs.mounted[j+1].prefix, "/lua/", strlen("/lua/") + 1);
                        }
#endif
                    }
                    else
                        LLOGD("mount error ret %d", ret);
                    vfs_unlock(&vfs);
                    return ret;
                }
            }
            LLOGE("too many filesystem mounted!!");
            vfs_unlock(&vfs);
            return -2;
        }
    }
    LLOGE("no such filesystem %s", conf->filesystem);
    vfs_unlock(&vfs);
    return -1;
}
int luat_fs_umount(luat_fs_conf_t *conf) {
    vfs_lock(&vfs);
    for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++) {
        if (vfs.mounted[j].ok == 0 || vfs.mounted[j].fs->opts.umount == NULL)
            continue;
        if (strcmp(vfs.mounted[j].prefix, conf->mount_point) == 0) {
            // TODO 关闭对应的FD
            int ret = vfs.mounted[j].fs->opts.umount(vfs.mounted[j].userdata, conf);
            vfs.mounted[j].fs = NULL;
            vfs.mounted[j].ok = 0;
            vfs_unlock(&vfs);
            return ret;
        }
    }
    LLOGE("no such mount point %s", conf->mount_point);
    vfs_unlock(&vfs);
    return -1;
}

int luat_fs_info(const char* path, luat_fs_info_t *conf) {
    vfs_lock(&vfs);
    luat_vfs_mount_t * mf = getmount(path);
    if (mf != NULL && mf->fs->opts.info != NULL) {
        int ret = mf->fs->opts.info(mf->userdata, ((char*)path) + strlen(mf->prefix), conf);
        vfs_unlock(&vfs);
        return ret;
    }
    LLOGE("no such mount point %s", path);
    vfs_unlock(&vfs);
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
    vfs_lock(&vfs);
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->fopts.fopen == NULL) {
        LLOGD("fopen %s %s NOT matched mount", filename, mode);
        vfs_unlock(&vfs);
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
                vfs_unlock(&vfs);
                return (FILE*)i;
            }
        }
        mount->fs->fopts.fclose(mount->userdata, fd);
        LLOGE("fopen %s %s too many open file!!!", filename, mode);
    }
    LLOGD("fopen %s %s not found", filename, mode);
    vfs_unlock(&vfs);
    return NULL;
}

int luat_fs_feof(FILE* stream) {
    vfs_lock(&vfs);
    //LLOGD("call %s %d","feof", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        vfs_unlock(&vfs);
        return 1;
    }
    int ret = fd->fsMount->fs->fopts.feof(fd->fsMount->userdata, fd->fd);
    vfs_unlock(&vfs);
    return ret;
}

int luat_fs_ferror(FILE* stream) {
    vfs_lock(&vfs);
    //LLOGD("call %s %d","ferror", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.ferror == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    int ret = fd->fsMount->fs->fopts.ferror(fd->fsMount->userdata, fd->fd);
    vfs_unlock(&vfs);
    return ret;
}

int luat_fs_ftell(FILE* stream) {
    vfs_lock(&vfs);
    //LLOGD("call %s %d","ftell", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.ftell == NULL)  {
        vfs_unlock(&vfs);
        return 0;
    }
    int ret = fd->fsMount->fs->fopts.ftell(fd->fsMount->userdata, fd->fd);
    vfs_unlock(&vfs);
    return ret;
}

int luat_fs_getc(FILE* stream) {
    vfs_lock(&vfs);
    //LLOGD("call %s %d","getc", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        LLOGD("FILE* stream is invaild!!!");
        vfs_unlock(&vfs);
        return -1;
    }
    if (fd->fsMount->fs->fopts.getc == NULL) {
        LLOGD("miss getc");
        vfs_unlock(&vfs);
        return -1;
    }
    int ret = fd->fsMount->fs->fopts.getc(fd->fsMount->userdata, fd->fd);
    vfs_unlock(&vfs);
    return ret;
}

// char luat_fs_getc(FILE* stream);
// int luat_fs_ftell(FILE* stream);
// int luat_fs_feof(FILE* stream);
// int luat_fs_ferror(FILE *stream);
int luat_fs_fclose(FILE* stream) {
    vfs_lock(&vfs);
    //LLOGD("fclose %d", (int)stream);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    int ret = fd->fsMount->fs->fopts.fclose(fd->fsMount->userdata, fd->fd);
    int _fd = (int)stream;
    vfs.fds[_fd].fsMount = NULL;
    vfs.fds[_fd].fd = NULL;
    vfs_unlock(&vfs);
    return ret;
}

int luat_fs_fseek(FILE* stream, long int offset, int origin) {
    vfs_lock(&vfs);
    //LLOGD("call %s %d","fseek", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fseek == NULL) {
        vfs_unlock(&vfs);
        return -1;
    }
    int ret = fd->fsMount->fs->fopts.fseek(fd->fsMount->userdata, fd->fd, offset, origin);
    vfs_unlock(&vfs);
    return ret;
}

size_t luat_fs_fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    vfs_lock(&vfs);
    //LLOGD("call %s %d","vfs_fread", ((int)stream) - 1);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fread == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    size_t ret = fd->fsMount->fs->fopts.fread(fd->fsMount->userdata, ptr, size, nmemb, fd->fd);
    vfs_unlock(&vfs);
    return ret;
}
size_t luat_fs_fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
    vfs_lock(&vfs);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fwrite == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    size_t ret = fd->fsMount->fs->fopts.fwrite(fd->fsMount->userdata, ptr, size, nmemb, fd->fd);
    vfs_unlock(&vfs);
    return ret;
}



int luat_fs_remove(const char *filename) {
    vfs_lock(&vfs);
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->opts.remove == NULL) {
        vfs_unlock(&vfs);
        return -1;
    }
    int ret = mount->fs->opts.remove(mount->userdata, filename + strlen(mount->prefix));
    vfs_unlock(&vfs);
    return ret;
}
int luat_fs_rename(const char *old_filename, const char *new_filename) {
    vfs_lock(&vfs);
    luat_vfs_mount_t *old_mount = getmount(old_filename);
    luat_vfs_mount_t *new_mount = getmount(new_filename);
    if (old_filename == NULL || new_mount != old_mount || old_mount->fs->opts.rename == NULL) {
        vfs_unlock(&vfs);
        return -1;
    }
    int ret = old_mount->fs->opts.rename(old_mount->userdata, old_filename + strlen(old_mount->prefix),
                                      new_filename + strlen(old_mount->prefix));
    vfs_unlock(&vfs);
    return ret;
}
size_t luat_fs_fsize(const char *filename) {
    vfs_lock(&vfs);
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->opts.fsize == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    size_t ret = mount->fs->opts.fsize(mount->userdata, filename + strlen(mount->prefix));
    vfs_unlock(&vfs);
    return ret;
}
int luat_fs_fexist(const char *filename) {
    vfs_lock(&vfs);
    //LLOGD("exist? %s", filename);
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL || mount->fs->opts.fexist == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    int ret = mount->fs->opts.fexist(mount->userdata,  filename + strlen(mount->prefix));
    vfs_unlock(&vfs);
    return ret;
}
int luat_fs_readline(char * buf, int bufsize, FILE * stream){
    // 直接使用后端 fread, 避免双重加锁 (readline → fread)
    vfs_lock(&vfs);
    int get_len = 0;
    char buff[2];
    if (buf == NULL || bufsize < 1) {
        vfs_unlock(&vfs);
        return 0;
    }
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL || fd->fsMount->fs->fopts.fread == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    size_t tmp = (size_t)bufsize;
    for (size_t i = 0; i <= tmp; i++){
        memset(buff, 0, 2);
        int len = fd->fsMount->fs->fopts.fread(fd->fsMount->userdata, buff, sizeof(char), 1, fd->fd);
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
    vfs_unlock(&vfs);
    return get_len;
}

int luat_fs_mkdir(char const* _DirName) {
    vfs_lock(&vfs);
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL || mount->fs->opts.mkdir == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    int ret = mount->fs->opts.mkdir(mount->userdata,  _DirName + strlen(mount->prefix));
    vfs_unlock(&vfs);
    return ret;
}
int luat_fs_rmdir(char const* _DirName) {
    vfs_lock(&vfs);
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL || mount->fs->opts.rmdir == NULL) {
        vfs_unlock(&vfs);
        return 0;
    }
    int ret = mount->fs->opts.rmdir(mount->userdata,  _DirName + strlen(mount->prefix));
    vfs_unlock(&vfs);
    return ret;
}

int luat_fs_lsdir(char const* _DirName, luat_fs_dirent_t* ents, size_t offset, size_t len) {
    vfs_lock(&vfs);
    if (len == 0) {
        vfs_unlock(&vfs);
        return 0;
    }
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL) {
        LLOGD("no such mount");
        vfs_unlock(&vfs);
        return 0;
    }
    if (mount->fs->opts.lsdir == NULL) {
        LLOGD("such mount not support lsdir");
        vfs_unlock(&vfs);
        return 0;
    }
    // LLOGD("luat_fs_lsdir _DirName:%s mount->prefix:%s dir:%s", _DirName,mount->prefix,_DirName + strlen(mount->prefix));
    int ret = mount->fs->opts.lsdir(mount->userdata,  _DirName + strlen(mount->prefix), ents, offset, len);
    if (ret <= 0) {
        vfs_unlock(&vfs);
        return 0;
    }

    char file_path[256] = {0};
    size_t file_path_len = strlen(_DirName);
    memcpy(file_path, _DirName, file_path_len + 1);
    if (strlen(_DirName + strlen(mount->prefix))!=1){
        file_path[file_path_len] = '/';
        file_path[file_path_len + 1] = 0;
        file_path_len++;
    }
    for (size_t i = 0; i < ret; i++){
        if (ents[i].d_type==0){
            memcpy(file_path+file_path_len, ents[i].d_name, strlen(ents[i].d_name) + 1);
            // 注意: 这里调用 luat_fs_fsize 会导致递归加锁死锁
            // lsdir 已持有 vfs_lock, 而 fsize 也会尝试 vfs_lock
            // 作为快速修复, 直接从相同 mount 获取大小 (不通过公共 API)
            if (mount->fs->opts.fsize) {
                ents[i].d_size = mount->fs->opts.fsize(mount->userdata, file_path + strlen(mount->prefix));
            }
        }
    }
    vfs_unlock(&vfs);
    return ret;
}

int luat_fs_dexist(const char *_DirName){
    vfs_lock(&vfs);
    // LLOGD("dexist? %s", _DirName);
    luat_vfs_mount_t *mount = getmount(_DirName);
    if (mount == NULL) {
        LLOGD("no such mount");
        vfs_unlock(&vfs);
        return 0;
    }
    if (strlen(mount->prefix) == strlen(_DirName)){
        vfs_unlock(&vfs);
        return 1;
    }
    if (mount->fs->opts.opendir == NULL) {
        LLOGD("such mount not support opendir");
        vfs_unlock(&vfs);
        return 0;
    }
    void* dir = mount->fs->opts.opendir(mount->userdata, _DirName + strlen(mount->prefix));
    // LLOGD("opendir dir:%p",dir);
    if (dir != NULL && mount->fs->opts.closedir != NULL) {
        mount->fs->opts.closedir(mount->userdata, dir);
    }
    int ret = dir == NULL ? 0 : 1;
    vfs_unlock(&vfs);
    return ret;
}


void* luat_fs_mmap(FILE* stream) {
    vfs_lock(&vfs);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        vfs_unlock(&vfs);
        return NULL;
    }
    void* ret = NULL;
    if (fd->fsMount->fs->fopts.mmap != NULL) {
        ret = fd->fsMount->fs->fopts.mmap(fd->fsMount->userdata, fd->fd);
    }
    vfs_unlock(&vfs);
    return ret;
}

luat_vfs_t* luat_vfs_self(void) {
    return &vfs;
}

int luat_fs_truncate(const char* filename, size_t len) {
    vfs_lock(&vfs);
    luat_vfs_mount_t *mount = getmount(filename);
    if (mount == NULL ) {
        vfs_unlock(&vfs);
        return -1;
    }
    if (mount->fs->opts.truncate) {
        int ret = mount->fs->opts.truncate(mount->userdata, filename, len);
        vfs_unlock(&vfs);
        return ret;
    }
    vfs_unlock(&vfs);
    return -1;
}

int luat_fs_fflush(FILE *stream) {
    vfs_lock(&vfs);
    luat_vfs_fd_t* fd = getfd(stream);
    if (fd == NULL) {
        vfs_unlock(&vfs);
        return -1;
    }
    if (fd->fsMount->fs->fopts.fflush != NULL) {
        int ret = fd->fsMount->fs->fopts.fflush(fd->fsMount->userdata, fd->fd);
        vfs_unlock(&vfs);
        return ret;
    }
    vfs_unlock(&vfs);
    return -1;
}



#endif
