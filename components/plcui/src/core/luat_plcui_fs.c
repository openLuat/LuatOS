/** @file luat_plcui_fs.c Read-only LVGL bridge to the LuatOS VFS. */
#include "luat_base.h"
#include "luat_plcui_platform.h"
#include "luat_fs.h"
#include <stdio.h>
#include <limits.h>

/* The descriptor outlives every LVGL file. lv_deinit removes the registration;
   each new PLCUI session registers it again after lv_init. */
static lv_fs_drv_t driver;

static void *fs_open(lv_fs_drv_t *drv, const char *path, lv_fs_mode_t mode)
{
    (void)drv;
    if (!path || !path[0] || mode != LV_FS_MODE_RD) return NULL;
    char full[384];
    int n = snprintf(full, sizeof(full), "%s%s", path[0] == '/' ? "" : "/", path);
    if (n < 0 || (size_t)n >= sizeof(full)) return NULL;
    return luat_fs_fopen(full, "rb");
}

static lv_fs_res_t fs_close(lv_fs_drv_t *drv, void *file)
{
    (void)drv;
    return luat_fs_fclose(file) == 0 ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t fs_read(lv_fs_drv_t *drv, void *file, void *buffer,
                         uint32_t requested, uint32_t *actual)
{
    (void)drv;
    *actual = (uint32_t)luat_fs_fread(buffer, 1, requested, file);
    return luat_fs_ferror(file) ? LV_FS_RES_FS_ERR : LV_FS_RES_OK;
}

static lv_fs_res_t fs_seek(lv_fs_drv_t *drv, void *file, uint32_t offset, lv_fs_whence_t whence)
{
    (void)drv;
    if ((uint64_t)offset > LONG_MAX) return LV_FS_RES_INV_PARAM;
    int origin = whence == LV_FS_SEEK_SET ? SEEK_SET : whence == LV_FS_SEEK_CUR ? SEEK_CUR : SEEK_END;
    return luat_fs_fseek(file, (long)offset, origin) == 0 ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t fs_tell(lv_fs_drv_t *drv, void *file, uint32_t *offset)
{
    (void)drv;
    long position = luat_fs_ftell(file);
    if (position < 0 || (uint64_t)position > UINT32_MAX) return LV_FS_RES_FS_ERR;
    *offset = (uint32_t)position;
    return LV_FS_RES_OK;
}

int plcui_fs_init(void)
{
    if (lv_fs_get_drv('/')) return -1;
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
