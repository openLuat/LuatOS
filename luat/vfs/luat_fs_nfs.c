/*
 * luat_fs_nfs.c — NFS VFS adapter for LuatOS
 *
 * Wraps the NFS POSIX API (nfs_open/read/write/close/...) into the
 * LuatOS VFS interface (luat_vfs_filesystem_t).
 *
 * Path mapping:  VFS strips the mount prefix (e.g. "/nfs").
 * We prepend the NFS device path:  "/<dev_name>/<vfs_path>".
 *
 * FILE mapping:  A luat_nfs_vfs_file_t struct is heap-allocated per
 * open file; its pointer is cast to FILE* for VFS consumption.
 */

#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include <limits.h>

#define LUAT_LOG_TAG "vfs.nfs"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

#include "../../components/nfs/inc/nfs.h"
#include "../../components/nfs/inc/nfs_port.h"
#include "../../components/nfs/inc/nfs_types.h"

/* Context struct — defined in luat_little_flash_nfs.c, redeclared here
 * with matching layout so the VFS layer can access dev_name/is_mounted.
 * The flash and OOB pointers are opaque to the VFS layer. */
typedef struct {
    void           *flash;
    uint32_t        offset;
    uint32_t        maxsize;
    char            dev_name[16];
    int             is_mounted;
    int             is_nand;
    void           *oob_ram;
    uint32_t        oob_per_chunk;
    uint32_t        total_chunks;
} luat_lf_nfs_ctx_t;

/*===================================================================
 *  FILE wrapper — maps between NFS fd and VFS FILE*
 *===================================================================*/

typedef struct {
    int nfs_fd;    /* NFS file descriptor (>= 0) or dir handle */
    int is_dir;    /* 1 = directory handle (nfs_opendir dfd)   */
} luat_nfs_vfs_file_t;

/*===================================================================
 *  Path helper — build "/<dev_name>/<vfs_path>"
 *===================================================================*/

static int luat_nfs_make_path(luat_lf_nfs_ctx_t *ctx, const char *vfs_path,
                              char *buf, size_t buf_size)
{
    int len;
    if (ctx == NULL || vfs_path == NULL || buf == NULL || buf_size == 0)
        return -1;

    len = snprintf(buf, buf_size, "/%s%s",
                   ctx->dev_name,
                   (vfs_path[0] == '/') ? vfs_path : "");
    if (len < 0 || (size_t)len >= buf_size)
        return -1;

    /* If vfs_path doesn't start with /, append it after a slash */
    if (vfs_path[0] != '/') {
        /* Find the null terminator and append */
        size_t used = strlen(buf);
        if (buf[used - 1] != '/') {
            if (used + 1 < buf_size) {
                buf[used] = '/';
                buf[used + 1] = '\0';
                used++;
            }
        }
        if (used + strlen(vfs_path) >= buf_size)
            return -1;
        strcat(buf, vfs_path);
    }

    return 0;
}

/*===================================================================
 *  Mode string → NFS flags
 *===================================================================*/

static int luat_nfs_mode_to_flags(const char *mode)
{
    if (!strcmp("r", mode) || !strcmp("rb", mode))
        return NFS_O_RDONLY;
    if (!strcmp("r+", mode) || !strcmp("r+b", mode) || !strcmp("rb+", mode))
        return NFS_O_RDWR | NFS_O_CREAT;
    if (!strcmp("w", mode) || !strcmp("wb", mode))
        return NFS_O_RDWR | NFS_O_CREAT | NFS_O_TRUNC;
    if (!strcmp("w+", mode) || !strcmp("w+b", mode) || !strcmp("wb+", mode))
        return NFS_O_RDWR | NFS_O_CREAT | NFS_O_TRUNC;
    if (!strcmp("a", mode) || !strcmp("ab", mode))
        return NFS_O_APPEND | NFS_O_CREAT | NFS_O_WRONLY;
    if (!strcmp("a+", mode) || !strcmp("a+b", mode) || !strcmp("ab+", mode))
        return NFS_O_APPEND | NFS_O_CREAT | NFS_O_WRONLY;

    LLOGW("nfs: bad file open mode '%s', fallback to 'r'", mode);
    return NFS_O_RDONLY;
}

/*===================================================================
 *  VFS mount / umount / mkfs
 *===================================================================*/

static int luat_vfs_nfs_mount(void **userdata, luat_fs_conf_t *conf)
{
    luat_lf_nfs_ctx_t *ctx;

    if (conf == NULL || conf->busname == NULL) {
        LLOGE("nfs mount: conf or busname is null");
        return -1;
    }

    ctx = (luat_lf_nfs_ctx_t *)conf->busname;
    if (!ctx->is_mounted) {
        LLOGE("nfs mount: device '%s' is not mounted", ctx->dev_name);
        return -1;
    }

    *userdata = ctx;
    LLOGD("nfs mount: '%s' ok, dev='%s'", conf->mount_point, ctx->dev_name);
    return 0;
}

static int luat_vfs_nfs_umount(void *userdata, luat_fs_conf_t *conf)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    (void)conf;

    if (ctx == NULL || !ctx->is_mounted)
        return -1;

    nfs_unmount(ctx->dev_name);
    nfs_remove_device(ctx->dev_name);
    ctx->is_mounted = 0;

    /* Release OOB RAM buffer allocated by the bridge */
    if (ctx->oob_ram) {
        luat_heap_free(ctx->oob_ram);
        ctx->oob_ram = NULL;
    }

    LLOGD("nfs umount: '%s' done", ctx->dev_name);
    return 0;
}

static int luat_vfs_nfs_mkfs(void *userdata, luat_fs_conf_t *conf)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    (void)conf;

    if (ctx == NULL)
        return -1;

    return nfs_format(ctx->dev_name) == NFS_OK ? 0 : -1;
}

/*===================================================================
 *  VFS file operations
 *===================================================================*/

static FILE *luat_vfs_nfs_fopen(void *userdata, const char *filename, const char *mode)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];
    luat_nfs_vfs_file_t *vf;
    int flags;
    int fd;

    if (ctx == NULL || filename == NULL || mode == NULL)
        return NULL;

    if (luat_nfs_make_path(ctx, filename, nfs_path, sizeof(nfs_path)) != 0) {
        LLOGE("nfs: path too long '%s'", filename);
        return NULL;
    }

    flags = luat_nfs_mode_to_flags(mode);
    fd = nfs_open(nfs_path, flags, 0644);
    if (fd < 0) {
        int err = nfs_get_error();
        LLOGD("nfs: open '%s' failed fd=%d nfs_err=%d", nfs_path, fd, err);
        return NULL;
    }

    vf = (luat_nfs_vfs_file_t *)luat_heap_malloc(sizeof(*vf));
    if (vf == NULL) {
        nfs_close(fd);
        return NULL;
    }
    vf->nfs_fd = fd;
    vf->is_dir = 0;
    return (FILE *)vf;
}

static int luat_vfs_nfs_getc(void *userdata, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    unsigned char c;
    int ret;

    (void)userdata;
    if (vf == NULL || vf->is_dir)
        return -1;

    ret = nfs_read(vf->nfs_fd, &c, 1);
    return (ret == 1) ? (int)c : -1;
}

static int luat_vfs_nfs_fseek(void *userdata, FILE *stream, long int offset, int origin)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    (void)userdata;

    if (vf == NULL || vf->is_dir)
        return -1;

    return (int)nfs_lseek(vf->nfs_fd, (nfs_off_t)offset, origin);
}

static int luat_vfs_nfs_ftell(void *userdata, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    nfs_off_t pos;
    (void)userdata;

    if (vf == NULL || vf->is_dir)
        return -1;

    pos = nfs_lseek(vf->nfs_fd, 0, NFS_SEEK_CUR);
    return (pos < 0) ? -1 : (int)pos;
}

static int luat_vfs_nfs_fclose(void *userdata, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    int ret = 0;
    (void)userdata;

    if (vf == NULL)
        return -1;

    if (vf->is_dir) {
        ret = nfs_closedir(vf->nfs_fd);
    } else {
        ret = nfs_close(vf->nfs_fd);
    }
    luat_heap_free(vf);
    return (ret == NFS_OK) ? 0 : -1;
}

static int luat_vfs_nfs_feof(void *userdata, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    nfs_off_t pos, size;
    nfs_stat_t st;
    (void)userdata;

    if (vf == NULL || vf->is_dir)
        return 1;

    pos = nfs_lseek(vf->nfs_fd, 0, NFS_SEEK_CUR);
    if (pos < 0)
        return 1;

    if (nfs_fstat(vf->nfs_fd, &st) != NFS_OK)
        return 1;

    size = st.st_size;
    return (pos >= size) ? 1 : 0;
}

static int luat_vfs_nfs_ferror(void *userdata, FILE *stream)
{
    (void)userdata;
    (void)stream;
    return 0;
}

static size_t luat_vfs_nfs_fread(void *userdata, void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    size_t total = size * nmemb;
    int ret;
    (void)userdata;

    if (vf == NULL || vf->is_dir || ptr == NULL || total == 0)
        return 0;

    ret = nfs_read(vf->nfs_fd, ptr, (int)total);
    if (ret <= 0)
        return 0;

    return (size_t)ret / size;  /* return number of items, per fread contract */
}

static size_t luat_vfs_nfs_fwrite(void *userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    size_t total = size * nmemb;
    int ret;
    (void)userdata;

    if (vf == NULL || vf->is_dir || ptr == NULL || total == 0)
        return 0;

    if (total > (size_t)INT_MAX)
        total = (size_t)INT_MAX;

    ret = nfs_write(vf->nfs_fd, ptr, (int)total);
    if (ret < 0)
        return 0;

    return (size_t)ret / size;
}

static int luat_vfs_nfs_fflush(void *userdata, FILE *stream)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)stream;
    (void)userdata;

    if (vf == NULL || vf->is_dir)
        return -1;

    return nfs_fsync(vf->nfs_fd) == NFS_OK ? 0 : -1;
}

/*===================================================================
 *  VFS filesystem operations
 *===================================================================*/

static int luat_vfs_nfs_remove(void *userdata, const char *filename)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];

    if (ctx == NULL)
        return -1;

    if (luat_nfs_make_path(ctx, filename, nfs_path, sizeof(nfs_path)) != 0)
        return -1;

    return nfs_unlink(nfs_path) == NFS_OK ? 0 : -1;
}

static int luat_vfs_nfs_rename(void *userdata, const char *oldname, const char *newname)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char old_path[NFS_MAX_PATH_LEN];
    char new_path[NFS_MAX_PATH_LEN];

    if (ctx == NULL)
        return -1;

    if (luat_nfs_make_path(ctx, oldname, old_path, sizeof(old_path)) != 0)
        return -1;
    if (luat_nfs_make_path(ctx, newname, new_path, sizeof(new_path)) != 0)
        return -1;

    return nfs_rename(old_path, new_path) == NFS_OK ? 0 : -1;
}

static size_t luat_vfs_nfs_fsize(void *userdata, const char *filename)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];
    nfs_stat_t st;

    if (ctx == NULL)
        return 0;

    if (luat_nfs_make_path(ctx, filename, nfs_path, sizeof(nfs_path)) != 0)
        return 0;

    if (nfs_stat(nfs_path, &st) != NFS_OK)
        return 0;

    return (size_t)st.st_size;
}

static int luat_vfs_nfs_fexist(void *userdata, const char *filename)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];
    nfs_stat_t st;

    if (ctx == NULL)
        return 0;

    if (luat_nfs_make_path(ctx, filename, nfs_path, sizeof(nfs_path)) != 0)
        return 0;

    return (nfs_stat(nfs_path, &st) == NFS_OK) ? 1 : 0;
}

static int luat_vfs_nfs_mkdir(void *userdata, const char *dirname)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];

    if (ctx == NULL)
        return -1;

    if (luat_nfs_make_path(ctx, dirname, nfs_path, sizeof(nfs_path)) != 0)
        return -1;

    return nfs_mkdir(nfs_path, 0755) == NFS_OK ? 0 : -1;
}

static int luat_vfs_nfs_rmdir(void *userdata, const char *dirname)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];

    if (ctx == NULL)
        return -1;

    if (luat_nfs_make_path(ctx, dirname, nfs_path, sizeof(nfs_path)) != 0)
        return -1;

    return nfs_rmdir(nfs_path) == NFS_OK ? 0 : -1;
}

static int luat_vfs_nfs_info(void *userdata, const char *path, luat_fs_info_t *info)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    (void)path;

    if (ctx == NULL || info == NULL)
        return -1;

    memset(info, 0, sizeof(*info));
    snprintf(info->filesystem, sizeof(info->filesystem), "nfs");

    /* NFS doesn't give per-device block info easily; report totals */
    info->total_block = (size_t)nfs_totalspace(ctx->dev_name);
    info->block_used  = info->total_block - (size_t)nfs_freespace(ctx->dev_name);
    info->block_size  = 1;  /* byte-level granularity */
    return 0;
}

static int luat_vfs_nfs_lsdir(void *userdata, const char *dirname,
                              luat_fs_dirent_t *ents, size_t offset, size_t len)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];
    int dfd;
    int count = 0;
    size_t skipped = 0;
    nfs_dirent_t de;

    if (ctx == NULL || ents == NULL)
        return -1;

    if (luat_nfs_make_path(ctx, dirname, nfs_path, sizeof(nfs_path)) != 0)
        return -1;

    dfd = nfs_opendir(nfs_path);
    if (dfd < 0)
        return -1;

    while (skipped < offset) {
        int r = nfs_readdir(dfd, &de);
        if (r <= 0)
            break;
        skipped++;
    }

    while (count < (int)len) {
        int r = nfs_readdir(dfd, &de);
        if (r <= 0)
            break;

        /* NFS_DT_DIR=4, NFS_DT_REG=8, NFS_DT_LNK=10 */
        ents[count].d_type = (de.d_type == NFS_DT_DIR) ? 1 : 0;
        strncpy(ents[count].d_name, de.d_name, sizeof(ents[count].d_name) - 1);
        ents[count].d_name[sizeof(ents[count].d_name) - 1] = '\0';
        ents[count].d_size = 0;  /* dirent doesn't carry size; caller can stat */
        count++;
    }

    nfs_closedir(dfd);
    return count;
}

static int luat_vfs_nfs_truncate(void *userdata, const char *filename, size_t nsize)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];

    if (ctx == NULL)
        return -1;

    if (luat_nfs_make_path(ctx, filename, nfs_path, sizeof(nfs_path)) != 0)
        return -1;

    return nfs_truncate(nfs_path, (nfs_off_t)nsize) == NFS_OK ? 0 : -1;
}

static void *luat_vfs_nfs_opendir(void *userdata, const char *dirname)
{
    luat_lf_nfs_ctx_t *ctx = (luat_lf_nfs_ctx_t *)userdata;
    char nfs_path[NFS_MAX_PATH_LEN];
    luat_nfs_vfs_file_t *vf;
    int dfd;

    if (ctx == NULL || dirname == NULL)
        return NULL;

    if (luat_nfs_make_path(ctx, dirname, nfs_path, sizeof(nfs_path)) != 0)
        return NULL;

    dfd = nfs_opendir(nfs_path);
    if (dfd < 0)
        return NULL;

    vf = (luat_nfs_vfs_file_t *)luat_heap_malloc(sizeof(*vf));
    if (vf == NULL) {
        nfs_closedir(dfd);
        return NULL;
    }
    vf->nfs_fd = dfd;
    vf->is_dir = 1;
    return (void *)vf;
}

static int luat_vfs_nfs_closedir(void *userdata, void *dir)
{
    luat_nfs_vfs_file_t *vf = (luat_nfs_vfs_file_t *)dir;
    (void)userdata;

    if (vf == NULL)
        return -1;

    nfs_closedir(vf->nfs_fd);
    luat_heap_free(vf);
    return 0;
}

/*===================================================================
 *  VFS registration
 *===================================================================*/

#define T(name) .name = luat_vfs_nfs_##name

static const struct luat_vfs_filesystem vfs_fs_nfs = {
    .name = "nfs",
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

void nfs_vfs_init(void)
{
    static int inited = 0;
    if (!inited) {
        luat_vfs_reg(&vfs_fs_nfs);
        inited = 1;
        LLOGD("nfs vfs registered");
    }
}

#endif /* LUAT_USE_FS_VFS */
