
/*
 * luat_fs_tfs.c — TFS VFS adapter for LuatOS
 *
 * Wraps TFS POSIX API into LuatOS VFS interface.
 */

#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "vfs.tfs"
#include "luat_log.h"

#ifdef LUAT_USE_FS_VFS

#include "../../components/tfs/inc/tfs.h"
#include "../../components/tfs/inc/tfs_port.h"
#include "../../components/tfs/inc/tfs_types.h"

/* Must match luat_little_flash_tfs.c layout */
typedef struct {
    void           *flash;
    uint32_t        offset, maxsize;
    char            dev_name[16];
    int             is_mounted, is_nand;
    void           *oob_ram;
    uint32_t        oob_per_chunk, total_chunks;
} luat_lf_tfs_ctx_t;

typedef struct { int tfs_fd; int is_dir; } luat_tfs_vfs_file_t;

/*===================================================================
 *  Path helper
 *===================================================================*/

static int tfs_make_path(luat_lf_tfs_ctx_t *ctx, const char *vfs_path,
                         char *buf, size_t size)
{
    int n = snprintf(buf, size, "/%s%s", ctx->dev_name,
                     (vfs_path[0] == '/') ? vfs_path : "");
    if (n < 0 || (size_t)n >= size) {
        return -1;
    }
    if (vfs_path[0] != '/') {
        size_t used = strlen(buf);
        if (used + 1 < size) {
            buf[used] = '/'; buf[used + 1] = '\0'; used++;
        }
        if (used + strlen(vfs_path) >= size) return -1;
        strcat(buf, vfs_path);
    }
    return 0;
}

static int tfs_mode_to_flags(const char *mode)
{
    if (!strcmp("r", mode) || !strcmp("rb", mode))     return TFS_O_RDONLY;
    if (!strcmp("r+", mode) || !strcmp("r+b", mode) || !strcmp("rb+", mode)) return TFS_O_RDWR | TFS_O_CREAT;
    if (!strcmp("w", mode) || !strcmp("wb", mode))     return TFS_O_RDWR | TFS_O_CREAT | TFS_O_TRUNC;
    if (!strcmp("w+", mode) || !strcmp("w+b", mode) || !strcmp("wb+", mode)) return TFS_O_RDWR | TFS_O_CREAT | TFS_O_TRUNC;
    if (!strcmp("a", mode) || !strcmp("ab", mode))     return TFS_O_APPEND | TFS_O_CREAT | TFS_O_WRONLY;
    if (!strcmp("a+", mode) || !strcmp("a+b", mode) || !strcmp("ab+", mode)) return TFS_O_APPEND | TFS_O_CREAT | TFS_O_RDWR;
    return -1;
}

/*===================================================================
 *  mount / umount / mkfs
 *===================================================================*/

static int luat_vfs_tfs_mount(void **userdata, luat_fs_conf_t *conf)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)conf->busname;
    if (!ctx || !ctx->is_mounted) { LLOGE("tfs: mount invalid ctx"); return -1; }
    *userdata = ctx;
    return 0;
}

static int luat_vfs_tfs_umount(void *userdata, luat_fs_conf_t *conf)
{
    (void)conf;
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    int rc;

    if (!ctx || !ctx->is_mounted) return -1;

    rc = tfs_unmount(ctx->dev_name);
    if (rc != TFS_OK) {
        LLOGE("tfs: unmount sync failed %d", rc);
        return -1;
    }

    tfs_remove_device(ctx->dev_name);
    ctx->is_mounted = 0;
    if (ctx->oob_ram) { luat_heap_free(ctx->oob_ram); ctx->oob_ram = NULL; }
    return 0;
}

static int luat_vfs_tfs_mkfs(void *userdata, luat_fs_conf_t *conf)
{
    (void)conf;
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    if (!ctx) return -1;
    return tfs_format(ctx->dev_name) == TFS_OK ? 0 : -1;
}

/*===================================================================
 *  File operations
 *===================================================================*/

static FILE *luat_vfs_tfs_fopen(void *userdata, const char *filename, const char *mode)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, filename, path, sizeof(path)) != 0) return NULL;

    int flags = tfs_mode_to_flags(mode);
    if (flags < 0) return NULL;
    int fd = tfs_open(path, flags, 0644);
    if (fd < 0) return NULL;

    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)luat_heap_malloc(sizeof(*vf));
    if (!vf) { tfs_close(fd); return NULL; }
    vf->tfs_fd = fd;
    vf->is_dir = 0;
    return (FILE *)vf;
}

static int luat_vfs_tfs_getc(void *userdata, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir) return -1;
    unsigned char c;
    return (tfs_read(vf->tfs_fd, &c, 1) == 1) ? (int)c : -1;
}

static int luat_vfs_tfs_fseek(void *userdata, FILE *stream, long off, int origin)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir) return -1;
    tfs_off_t pos = tfs_lseek(vf->tfs_fd, (tfs_off_t)off, origin);
    return (pos < 0) ? -1 : 0;
}

static int luat_vfs_tfs_ftell(void *userdata, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir) return -1;
    tfs_off_t pos = tfs_lseek(vf->tfs_fd, 0, TFS_SEEK_CUR);
    return (pos < 0) ? -1 : (int)pos;
}

static int luat_vfs_tfs_fclose(void *userdata, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf) return -1;
    int ret = vf->is_dir ? tfs_closedir(vf->tfs_fd) : tfs_close(vf->tfs_fd);
    luat_heap_free(vf);
    return (ret == TFS_OK) ? 0 : -1;
}

static int luat_vfs_tfs_feof(void *userdata, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir) return 1;
    tfs_stat_t st;
    tfs_off_t pos = tfs_lseek(vf->tfs_fd, 0, TFS_SEEK_CUR);
    return (pos >= 0 && tfs_fstat(vf->tfs_fd, &st) == TFS_OK)
           ? (pos >= st.st_size) : 1;
}

static int luat_vfs_tfs_ferror(void *userdata, FILE *stream)
{ (void)userdata; (void)stream; return 0; }

static size_t luat_vfs_tfs_fread(void *userdata, void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir || !ptr || size * nmemb == 0) return 0;
    int n = tfs_read(vf->tfs_fd, ptr, (int)(size * nmemb));
    return (n > 0) ? (size_t)n / size : 0;
}

static size_t luat_vfs_tfs_fwrite(void *userdata, const void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir || !ptr || size * nmemb == 0) return 0;
    size_t total = size * nmemb;
    if (total > (size_t)INT_MAX) total = (size_t)INT_MAX;
    int n = tfs_write(vf->tfs_fd, ptr, (int)total);
    return (n > 0) ? (size_t)n / size : 0;
}

static int luat_vfs_tfs_fflush(void *userdata, FILE *stream)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)stream;
    (void)userdata;
    if (!vf || vf->is_dir) return -1;
    return tfs_fsync(vf->tfs_fd) == TFS_OK ? 0 : -1;
}

/*===================================================================
 *  Filesystem operations
 *===================================================================*/

static int luat_vfs_tfs_remove(void *userdata, const char *filename)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, filename, path, sizeof(path)) != 0) return -1;
    return tfs_unlink(path) == TFS_OK ? 0 : -1;
}

static int luat_vfs_tfs_rename(void *userdata, const char *oldname, const char *newname)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char old[TFS_MAX_PATH_LEN], newp[TFS_MAX_PATH_LEN];
    if (!ctx) return -1;
    if (tfs_make_path(ctx, oldname, old, sizeof(old)) != 0) return -1;
    if (tfs_make_path(ctx, newname, newp, sizeof(newp)) != 0) return -1;
    return tfs_rename(old, newp) == TFS_OK ? 0 : -1;
}

static size_t luat_vfs_tfs_fsize(void *userdata, const char *filename)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    tfs_stat_t st;
    if (!ctx || tfs_make_path(ctx, filename, path, sizeof(path)) != 0) return 0;
    return (tfs_stat(path, &st) == TFS_OK) ? (size_t)st.st_size : 0;
}

static int luat_vfs_tfs_fexist(void *userdata, const char *filename)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    tfs_stat_t st;
    if (!ctx || tfs_make_path(ctx, filename, path, sizeof(path)) != 0) return 0;
    return (tfs_stat(path, &st) == TFS_OK) ? 1 : 0;
}

static int luat_vfs_tfs_mkdir(void *userdata, const char *dirname)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, dirname, path, sizeof(path)) != 0) return -1;
    return tfs_mkdir(path, 0755) == TFS_OK ? 0 : -1;
}

static int luat_vfs_tfs_rmdir(void *userdata, const char *dirname)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, dirname, path, sizeof(path)) != 0) return -1;
    return tfs_rmdir(path) == TFS_OK ? 0 : -1;
}

static void tfs_add_size_saturating(size_t *total, size_t add)
{
    if (!total) {
        return;
    }
    if (add > ((size_t)-1) - *total) {
        *total = (size_t)-1;
    } else {
        *total += add;
    }
}

static int tfs_join_path(char *out, size_t out_size,
                         const char *dir, const char *name)
{
    size_t len;
    const char *sep;
    int written;

    if (!out || out_size == 0 || !dir || !name) {
        return -1;
    }
    len = strlen(dir);
    sep = (len > 0 && dir[len - 1] == '/') ? "" : "/";
    written = snprintf(out, out_size, "%s%s%s", dir, sep, name);
    return (written > 0 && (size_t)written < out_size) ? 0 : -1;
}

static size_t tfs_dir_logical_bytes(const char *path, int depth, int *ok)
{
    enum { TFS_SCAN_MAX_DEPTH = 12 };
    int dfd;
    size_t total = 0;
    tfs_dirent_t de;

    if (!ok || *ok == 0) {
        return 0;
    }
    if (!path || depth > TFS_SCAN_MAX_DEPTH) {
        *ok = 0;
        return 0;
    }

    dfd = tfs_opendir(path);
    if (dfd < 0) {
        *ok = 0;
        return 0;
    }

    while (*ok && tfs_readdir(dfd, &de) > 0) {
        char child[TFS_MAX_PATH_LEN];

        de.d_name[sizeof(de.d_name) - 1] = '\0';
        if (de.d_name[0] == '\0' ||
            strcmp(de.d_name, ".") == 0 ||
            strcmp(de.d_name, "..") == 0) {
            continue;
        }
        if (tfs_join_path(child, sizeof(child), path, de.d_name) != 0) {
            *ok = 0;
            break;
        }

        if (de.d_type == TFS_DT_DIR) {
            tfs_add_size_saturating(&total,
                tfs_dir_logical_bytes(child, depth + 1, ok));
        } else {
            tfs_stat_t st;
            if (tfs_stat(child, &st) == TFS_OK) {
                tfs_add_size_saturating(&total, (size_t)st.st_size);
            } else {
                *ok = 0;
                break;
            }
        }
    }
    tfs_closedir(dfd);
    return total;
}

static int luat_vfs_tfs_info(void *userdata, const char *path, luat_fs_info_t *info)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    const size_t unit = 1024;
    tfs_off_t total;
    tfs_off_t free;
    tfs_off_t used;
    char root[TFS_MAX_PATH_LEN];
    int logical_ok = 1;
    size_t logical_used;

    if (!ctx || !info) return -1;

    (void)path;

    total = tfs_totalspace(ctx->dev_name);
    free = tfs_freespace(ctx->dev_name);
    if (total < 0 || free < 0) {
        return -1;
    }
    used = (total > free) ? (total - free) : 0;
    if (snprintf(root, sizeof(root), "/%s/", ctx->dev_name) > 0) {
        logical_used = tfs_dir_logical_bytes(root, 0, &logical_ok);
        if (logical_ok) {
            used = (tfs_off_t)logical_used;
        }
    }

    memset(info, 0, sizeof(*info));
    snprintf(info->filesystem, sizeof(info->filesystem), "tfs");
    info->total_block = (size_t)((total + (tfs_off_t)unit - 1) / (tfs_off_t)unit);
    info->block_used  = (size_t)((used + (tfs_off_t)unit - 1) / (tfs_off_t)unit);
    info->block_size  = unit;
    return 0;
}

static int luat_vfs_tfs_lsdir(void *userdata, const char *dirname,
                              luat_fs_dirent_t *ents, size_t offset, size_t len)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, dirname, path, sizeof(path)) != 0) return -1;

    int dfd = tfs_opendir(path);
    if (dfd < 0) return -1;

    tfs_dirent_t de;
    int count = 0;
    size_t skipped = 0;

    while (skipped < offset && tfs_readdir(dfd, &de) > 0) skipped++;
    while (count < (int)len && tfs_readdir(dfd, &de) > 0) {
        ents[count].d_type = (de.d_type == TFS_DT_DIR) ? 1 : 0;
        strncpy(ents[count].d_name, de.d_name, sizeof(ents[count].d_name) - 1);
        ents[count].d_name[sizeof(ents[count].d_name) - 1] = '\0';
        ents[count].d_size = 0;
        count++;
    }
    tfs_closedir(dfd);
    return count;
}

static int luat_vfs_tfs_truncate(void *userdata, const char *filename, size_t nsize)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, filename, path, sizeof(path)) != 0) return -1;
    return tfs_truncate(path, (tfs_off_t)nsize) == TFS_OK ? 0 : -1;
}

static void *luat_vfs_tfs_opendir(void *userdata, const char *dirname)
{
    luat_lf_tfs_ctx_t *ctx = (luat_lf_tfs_ctx_t *)userdata;
    char path[TFS_MAX_PATH_LEN];
    if (!ctx || tfs_make_path(ctx, dirname, path, sizeof(path)) != 0) return NULL;

    int dfd = tfs_opendir(path);
    if (dfd < 0) return NULL;

    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)luat_heap_malloc(sizeof(*vf));
    if (!vf) { tfs_closedir(dfd); return NULL; }
    vf->tfs_fd = dfd;
    vf->is_dir = 1;
    return vf;
}

static int luat_vfs_tfs_closedir(void *userdata, void *dir)
{
    luat_tfs_vfs_file_t *vf = (luat_tfs_vfs_file_t *)dir;
    (void)userdata;
    if (!vf) return -1;
    tfs_closedir(vf->tfs_fd);
    luat_heap_free(vf);
    return 0;
}

/*===================================================================
 *  Registration
 *===================================================================*/

#define T(name) .name = luat_vfs_tfs_##name

static const struct luat_vfs_filesystem vfs_fs_tfs = {
    .name = "tfs",
    .opts = {
        T(mkfs), T(mount), T(umount), T(mkdir), T(rmdir), T(lsdir),
        T(remove), T(rename), T(fsize), T(fexist), T(info), T(truncate),
        T(opendir), T(closedir)
    },
    .fopts = {
        T(fopen), T(getc), T(fseek), T(ftell), T(fclose),
        T(feof), T(ferror), T(fread), T(fwrite), T(fflush)
    }
};

void tfs_vfs_init(void)
{
    static int inited = 0;
    if (!inited) { luat_vfs_reg(&vfs_fs_tfs); inited = 1; }
}

#endif /* LUAT_USE_FS_VFS */
