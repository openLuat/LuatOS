#define LUAT_LOG_TAG "easylvgl.fs"
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_log.h"
#include "luat_mem.h"
#include "../lvgl9/lvgl.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define EASYLVGL_LOG_TAG "easylvgl.fs"

static bool g_easylvgl_fs_registered = false;
static lv_fs_drv_t g_easylvgl_fs_drv_letter_L;
static lv_fs_drv_t g_easylvgl_fs_drv_letter_slash;

static bool easylvgl_fs_ready_cb(lv_fs_drv_t *drv) {
    (void)drv;
    return true;
}

static const char * easylvgl_fs_mode_to_str(lv_fs_mode_t mode) {
    bool rd = (mode & LV_FS_MODE_RD) != 0;
    bool wr = (mode & LV_FS_MODE_WR) != 0;

    if (rd && wr) {
        return "r+b";
    }
    if (wr) {
        return "wb";
    }
    return "rb";
}

static void easylvgl_fs_build_path(const char *real_path, char *out, size_t out_size) {
    if (out_size == 0) {
        return;
    }

    if (real_path == NULL || real_path[0] == '\0') {
        if (out_size >= 2) {
            out[0] = '/';
            out[1] = '\0';
        }
        else {
            out[0] = '\0';
        }
        return;
    }

    if (real_path[0] == '/') {
        size_t len = strlen(real_path);
        if (len >= out_size) {
            len = out_size - 1;
        }
        memcpy(out, real_path, len);
        out[len] = '\0';
        return;
    }

    if (out_size < 2) {
        out[0] = '\0';
        return;
    }

    out[0] = '/';
    size_t max_copy = out_size - 2;
    size_t copy_len = strlen(real_path);
    if (copy_len > max_copy) {
        copy_len = max_copy;
    }
    memcpy(out + 1, real_path, copy_len);
    out[1 + copy_len] = '\0';
}

static FILE * easylvgl_fs_fopen(const char *path, lv_fs_mode_t mode) {
    FILE *fd = NULL;
    const char *mode_str = NULL;

    if ((mode & LV_FS_MODE_RD) && (mode & LV_FS_MODE_WR)) {
        mode_str = "r+b";
        fd = luat_fs_fopen(path, mode_str);
        if (fd == NULL) {
            fd = luat_fs_fopen(path, "w+b");
        }
    }
    else if (mode & LV_FS_MODE_WR) {
        mode_str = "wb";
        fd = luat_fs_fopen(path, mode_str);
    }
    else {
        mode_str = "rb";
        fd = luat_fs_fopen(path, mode_str);
    }

    if (fd == NULL) {
        LLOGW("failed to open %s (%s)", path, mode_str);
    }
    return fd;
}

static void * easylvgl_fs_open(lv_fs_drv_t *drv, const char *path, lv_fs_mode_t mode) {
    char file_path[256] = {0};
    easylvgl_fs_build_path(path, file_path, sizeof(file_path));
    FILE *fd = easylvgl_fs_fopen(file_path, mode);
    return fd;
}

static lv_fs_res_t easylvgl_fs_close(lv_fs_drv_t *drv, void *file_p) {
    (void)drv;
    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }
    FILE *fd = file_p;
    if (luat_fs_fclose(fd) == 0) {
        return LV_FS_RES_OK;
    }
    return LV_FS_RES_FS_ERR;
}

static lv_fs_res_t easylvgl_fs_read(lv_fs_drv_t *drv, void *file_p, void *buf, uint32_t btr, uint32_t *br) {
    (void)drv;
    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }
    FILE *fd = file_p;
    size_t read = luat_fs_fread(buf, 1, btr, fd);
    if (br != NULL) {
        *br = read;
    }
    if (read == 0 && btr > 0 && !feof(fd)) {
        return LV_FS_RES_FS_ERR;
    }
    return LV_FS_RES_OK;
}

static lv_fs_res_t easylvgl_fs_write(lv_fs_drv_t *drv, void *file_p, const void *buf, uint32_t btw, uint32_t *bw) {
    (void)drv;
    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }
    FILE *fd = file_p;
    size_t written = luat_fs_fwrite(buf, 1, btw, fd);
    if (bw != NULL) {
        *bw = written;
    }
    if (written != btw) {
        return LV_FS_RES_FS_ERR;
    }
    return LV_FS_RES_OK;
}

static lv_fs_res_t easylvgl_fs_seek(lv_fs_drv_t *drv, void *file_p, uint32_t pos, lv_fs_whence_t whence) {
    (void)drv;
    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }
    int origin = SEEK_SET;
    if (whence == LV_FS_SEEK_CUR) {
        origin = SEEK_CUR;
    }
    else if (whence == LV_FS_SEEK_END) {
        origin = SEEK_END;
    }
    FILE *fd = file_p;
    return (luat_fs_fseek(fd, pos, origin) == 0) ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t easylvgl_fs_tell(lv_fs_drv_t *drv, void *file_p, uint32_t *pos_p) {
    (void)drv;
    if (file_p == NULL || pos_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }
    FILE *fd = file_p;
    int pos = luat_fs_ftell(fd);
    if (pos < 0) {
        return LV_FS_RES_FS_ERR;
    }
    *pos_p = (uint32_t)pos;
    return LV_FS_RES_OK;
}

static void easylvgl_fs_register_drv(lv_fs_drv_t *drv, char letter) {
    lv_fs_drv_init(drv);
    drv->letter = letter;
    drv->cache_size = 0;
    drv->ready_cb = easylvgl_fs_ready_cb;
    drv->open_cb = easylvgl_fs_open;
    drv->close_cb = easylvgl_fs_close;
    drv->read_cb = easylvgl_fs_read;
    drv->write_cb = easylvgl_fs_write;
    drv->seek_cb = easylvgl_fs_seek;
    drv->tell_cb = easylvgl_fs_tell;
    lv_fs_drv_register(drv);
}

void easylvgl_fs_init(void) {
    if (g_easylvgl_fs_registered) {
        return;
    }
    easylvgl_fs_register_drv(&g_easylvgl_fs_drv_letter_L, 'L');
    easylvgl_fs_register_drv(&g_easylvgl_fs_drv_letter_slash, '/');
    g_easylvgl_fs_registered = true;
}

