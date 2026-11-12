/** @file luat_plcui_fs.c Read-only LVGL bridge to the LuatOS VFS. */
#include "luat_base.h"
#include "luat_plcui_platform.h"
#include "luat_plcui_perf.h"
#include "luat_plcui_fs.h"
#include "luat_fs.h"
#include <stdio.h>
#include <limits.h>
#include <string.h>

/* The descriptor outlives every LVGL file. lv_deinit removes the registration;
   each new PLCUI session registers it again after lv_init. */
static lv_fs_drv_t driver;

/* A scope owns one reference; every logical LVGL/native input borrows another.
 * Software decoders may retain their file until decoder_close, after scope_end.
 * Keep such owners linked until their last borrower returns the reference. */
typedef struct image_owner {
    FILE *file;
    size_t size;
    unsigned refs;
    struct image_owner *next;
} image_owner_t;

typedef struct {
    FILE *file;
    image_owner_t *owner;
    uint32_t position;
} file_lease_t;

static image_owner_t *owners;
static struct {
    bool active, failed;
    char key[PLCUI_PATH_MAX];
    image_owner_t *owner;
} scope;

static bool full_path(char *full, size_t size, const char *path)
{
    if (!path || !path[0]) return false;
    int length = snprintf(full, size, "%s%s", path[0] == '/' ? "" : "/", path);
    return length > 0 && (size_t)length < size;
}

static FILE *real_open(const char *path)
{
    const char *actual = luat_plcui_image_path(path);
    if (!actual) return NULL;
    uint32_t started = plcui_perf_now();
    FILE *file = luat_fs_fopen(actual, "rb");
    plcui_perf_add(PERF_REAL_OPEN, plcui_perf_now() - started, 0);
    return file;
}

static int real_close(FILE *file)
{
    uint32_t started = plcui_perf_now();
    int result = luat_fs_fclose(file);
    plcui_perf_add(PERF_REAL_CLOSE, plcui_perf_now() - started, 0);
    return result;
}

static int owner_release(image_owner_t *owner)
{
    if (--owner->refs) return 0;
    image_owner_t **link = &owners;
    while (*link && *link != owner) link = &(*link)->next;
    if (*link) *link = owner->next;
    int result = real_close(owner->file);
    lv_free(owner);
    return result;
}

bool plcui_fs_scope_begin(const char *key)
{
    if (scope.active || !full_path(scope.key, sizeof(scope.key), key)) return false;
    scope.active = true;
    scope.failed = false;
    scope.owner = NULL;
    return true;
}

void plcui_fs_scope_end(void)
{
    image_owner_t *owner = scope.owner;
    memset(&scope, 0, sizeof(scope));
    if (owner) owner_release(owner);
}

int plcui_fs_scope_acquire(const char *key, FILE **file, size_t *size)
{
    if (!file || !size) return -1;
    *file = NULL; *size = 0;
    char full[PLCUI_PATH_MAX];
    if (!scope.active || !full_path(full, sizeof(full), key) || strcmp(full, scope.key)) return 0;
    if (scope.failed) return -1;
    if (!scope.owner) {
        image_owner_t *owner = lv_malloc_zeroed(sizeof(*owner));
        if (!owner) { scope.failed = true; return -1; }
        owner->file = real_open(scope.key);
        uint32_t started = plcui_perf_now();
        long length = -1;
        if (owner->file && luat_fs_fseek(owner->file, 0, SEEK_END) == 0) length = luat_fs_ftell(owner->file);
        bool valid = length > 0 && (uint64_t)length <= PLCUI_MAX_IMAGE_BYTES;
        if (valid) valid = luat_fs_fseek(owner->file, 0, SEEK_SET) == 0;
        plcui_perf_add(PERF_SIZE, plcui_perf_now() - started, 0);
        if (!valid) {
            if (owner->file) real_close(owner->file);
            lv_free(owner); scope.failed = true; return -1;
        }
        owner->size = (size_t)length;
        owner->refs = 1;
        owner->next = owners; owners = owner;
        scope.owner = owner;
    }
    image_owner_t *owner = scope.owner;
    owner->refs++;
    *file = owner->file; *size = owner->size;
    return 1;
}

void plcui_fs_scope_release(FILE *file)
{
    for (image_owner_t *owner = owners; owner; owner = owner->next) {
        if (owner->file == file) { owner_release(owner); return; }
    }
}

static void *fs_open(lv_fs_drv_t *drv, const char *path, lv_fs_mode_t mode)
{
    (void)drv;
    if (!path || !path[0] || mode != LV_FS_MODE_RD) return NULL;
    char full[PLCUI_PATH_MAX];
    if (!full_path(full, sizeof(full), path)) return NULL;
    uint32_t started = plcui_perf_now();
    file_lease_t *lease = lv_malloc_zeroed(sizeof(*lease));
    if (!lease) return NULL;
    size_t size = 0;
    int shared = plcui_fs_scope_acquire(full, &lease->file, &size);
    if (shared == 1) {
        for (image_owner_t *owner = owners; owner; owner = owner->next) {
            if (owner->file == lease->file) { lease->owner = owner; break; }
        }
    } else if (shared == 0) {
        lease->file = real_open(full);
    }
    plcui_perf_add(PERF_LV_OPEN, plcui_perf_now() - started, 0);
    if (!lease->file) { lv_free(lease); return NULL; }
    return lease;
}

static lv_fs_res_t fs_close(lv_fs_drv_t *drv, void *file)
{
    (void)drv;
    uint32_t started = plcui_perf_now();
    file_lease_t *lease = file;
    int result = lease->owner ? owner_release(lease->owner) : real_close(lease->file);
    lv_free(lease);
    plcui_perf_add(PERF_LV_CLOSE, plcui_perf_now() - started, 0);
    return result == 0 ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t fs_read(lv_fs_drv_t *drv, void *file, void *buffer,
                         uint32_t requested, uint32_t *actual)
{
    (void)drv;
    uint32_t started = plcui_perf_now();
    file_lease_t *lease = file;
    *actual = 0;
    /* Native reads and other leases can move the same FILE. Restore this
       logical handle's position before touching its data. */
    if ((uint64_t)lease->position > LONG_MAX
        || luat_fs_fseek(lease->file, (long)lease->position, SEEK_SET) != 0) {
        plcui_perf_add(PERF_LV_READ, plcui_perf_now() - started, 0);
        return LV_FS_RES_FS_ERR;
    }
    *actual = (uint32_t)luat_fs_fread(buffer, 1, requested, lease->file);
    lease->position += *actual;
    plcui_perf_add(PERF_LV_READ, plcui_perf_now() - started, *actual);
    return luat_fs_ferror(lease->file) ? LV_FS_RES_FS_ERR : LV_FS_RES_OK;
}

static lv_fs_res_t fs_seek(lv_fs_drv_t *drv, void *file, uint32_t offset, lv_fs_whence_t whence)
{
    (void)drv;
    if ((uint64_t)offset > LONG_MAX) return LV_FS_RES_INV_PARAM;
    int origin = whence == LV_FS_SEEK_SET ? SEEK_SET : whence == LV_FS_SEEK_CUR ? SEEK_CUR : SEEK_END;
    uint32_t started = plcui_perf_now();
    file_lease_t *lease = file;
    int result = 0;
    if (whence == LV_FS_SEEK_CUR) {
        result = (uint64_t)lease->position <= LONG_MAX
            ? luat_fs_fseek(lease->file, (long)lease->position, SEEK_SET) : -1;
    }
    if (result == 0) result = luat_fs_fseek(lease->file, (long)offset, origin);
    if (result == 0) {
        long position = luat_fs_ftell(lease->file);
        if (position < 0 || (uint64_t)position > UINT32_MAX) result = -1;
        else lease->position = (uint32_t)position;
    }
    plcui_perf_add(PERF_LV_SEEK, plcui_perf_now() - started, 0);
    return result == 0 ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t fs_tell(lv_fs_drv_t *drv, void *file, uint32_t *offset)
{
    (void)drv;
    uint32_t started = plcui_perf_now();
    file_lease_t *lease = file;
    uint32_t position = lease->position;
    plcui_perf_add(PERF_LV_TELL, plcui_perf_now() - started, 0);
    *offset = position;
    return LV_FS_RES_OK;
}

int plcui_fs_init(void)
{
    if (lv_fs_get_drv('/')) return -1;
    plcui_fs_scope_end();
    lv_fs_drv_init(&driver);
    driver.letter = '/';
    driver.open_cb = fs_open;
    driver.close_cb = fs_close;
    driver.read_cb = fs_read;
    driver.seek_cb = fs_seek;
    driver.tell_cb = fs_tell;
    lv_fs_drv_register(&driver);
    return lv_fs_get_drv('/') == &driver ? 0 : -1;
}
