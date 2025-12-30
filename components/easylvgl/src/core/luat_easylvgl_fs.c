/**
 * @file luat_easylvgl_fs.c
 * @summary EasyLVGL 文件系统驱动实现
 * @responsible LVGL 文件系统驱动注册和回调实现，支持平台抽象接口
 */

#include "luat_easylvgl.h"
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_log.h"
#include <string.h>
#include <stdio.h>

#define LUAT_LOG_TAG "easylvgl.fs"

/*********************
 *      DEFINES
 *********************/

/** 文件路径最大长度 */
#define EASYLVGL_FS_PATH_MAX 256

/*********************
 *  STATIC FUNCTIONS
 *********************/

/**
 * 文件系统就绪回调
 * @param drv 文件系统驱动指针
 * @return true 就绪，false 未就绪
 */
static bool fs_ready_cb(lv_fs_drv_t *drv)
{
    (void)drv;
    return true;
}

/**
 * 将 lv_fs_mode_t 转换为文件模式字符串
 * @param mode LVGL 文件模式
 * @return 文件模式字符串
 */
static const char *fs_mode_to_str(lv_fs_mode_t mode)
{
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

/**
 * 构建文件路径（去除驱动字母前缀）
 * @param lvgl_path LVGL 路径（如 "L:/image.png" 或 "/image.png"）
 * @param out 输出缓冲区
 * @param out_size 输出缓冲区大小
 */
static void fs_build_path(const char *lvgl_path, char *out, size_t out_size)
{
    if (out_size == 0) {
        return;
    }

    if (lvgl_path == NULL || lvgl_path[0] == '\0') {
        if (out_size >= 2) {
            out[0] = '/';
            out[1] = '\0';
        } else {
            out[0] = '\0';
        }
        return;
    }

    // 如果路径以 '/' 开头，直接使用
    if (lvgl_path[0] == '/') {
        size_t len = strlen(lvgl_path);
        if (len >= out_size) {
            len = out_size - 1;
        }
        memcpy(out, lvgl_path, len);
        out[len] = '\0';
        return;
    }

    // 其他情况，添加 '/' 前缀
    if (out_size < 2) {
        out[0] = '\0';
        return;
    }
    out[0] = '/';
    size_t max_copy = out_size - 2;
    size_t copy_len = strlen(lvgl_path);
    if (copy_len > max_copy) {
        copy_len = max_copy;
    }
    memcpy(out + 1, lvgl_path, copy_len);
    out[1 + copy_len] = '\0';
}

/**
 * 使用默认 LuatOS 文件系统接口打开文件
 * @param path 文件路径
 * @param mode 文件模式
 * @return 文件句柄，失败返回 NULL
 */
static FILE *fs_fopen_default(const char *path, lv_fs_mode_t mode)
{
    FILE *fd = NULL;
    const char *mode_str = fs_mode_to_str(mode);

    if ((mode & LV_FS_MODE_RD) && (mode & LV_FS_MODE_WR)) {
        // 读写模式：先尝试打开，失败则创建
        fd = luat_fs_fopen(path, mode_str);
        if (fd == NULL) {
            fd = luat_fs_fopen(path, "w+b");
        }
    } else if (mode & LV_FS_MODE_WR) {
        // 写模式
        fd = luat_fs_fopen(path, mode_str);
    } else {
        // 读模式
        fd = luat_fs_fopen(path, mode_str);
    }

    if (fd == NULL) {
        LLOGW("easylvgl_fs: failed to open %s (%s)", path, mode_str);
    }
    return fd;
}

/**
 * 文件打开回调
 * @param drv 文件系统驱动指针
 * @param path 文件路径
 * @param mode 文件模式
 * @return 文件句柄，失败返回 NULL
 */
static void *fs_open_cb(lv_fs_drv_t *drv, const char *path, lv_fs_mode_t mode)
{
    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)drv->user_data;
    if (ctx == NULL) {
        LLOGE("easylvgl_fs: ctx is NULL");
        return NULL;
    }

    char file_path[EASYLVGL_FS_PATH_MAX] = {0};
    fs_build_path(path, file_path, sizeof(file_path));

    // 如果平台提供了文件系统操作接口，使用平台接口
    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->open != NULL) {
        return ctx->ops->fs_ops->open(ctx, file_path, mode);
    }

    // 否则使用默认的 LuatOS 文件系统接口
    return fs_fopen_default(file_path, mode);
}

/**
 * 文件关闭回调
 * @param drv 文件系统驱动指针
 * @param file_p 文件句柄
 * @return LV_FS_RES_OK 成功，其他值表示失败
 */
static lv_fs_res_t fs_close_cb(lv_fs_drv_t *drv, void *file_p)
{
    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)drv->user_data;
    if (ctx == NULL) {
        return LV_FS_RES_FS_ERR;
    }

    // 如果平台提供了文件系统操作接口，使用平台接口
    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->close != NULL) {
        return ctx->ops->fs_ops->close(ctx, file_p);
    }

    // 否则使用默认的 LuatOS 文件系统接口
    FILE *fd = (FILE *)file_p;
    if (luat_fs_fclose(fd) == 0) {
        return LV_FS_RES_OK;
    }
    return LV_FS_RES_FS_ERR;
}

/**
 * 文件读取回调
 * @param drv 文件系统驱动指针
 * @param file_p 文件句柄
 * @param buf 读取缓冲区
 * @param btr 要读取的字节数
 * @param br 实际读取的字节数（输出）
 * @return LV_FS_RES_OK 成功，其他值表示失败
 */
static lv_fs_res_t fs_read_cb(lv_fs_drv_t *drv, void *file_p, void *buf, uint32_t btr, uint32_t *br)
{
    if (file_p == NULL || buf == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)drv->user_data;
    if (ctx == NULL) {
        return LV_FS_RES_FS_ERR;
    }

    // 如果平台提供了文件系统操作接口，使用平台接口
    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->read != NULL) {
        return ctx->ops->fs_ops->read(ctx, file_p, buf, btr, br);
    }

    // 否则使用默认的 LuatOS 文件系统接口
    FILE *fd = (FILE *)file_p;
    size_t read = luat_fs_fread(buf, 1, btr, fd);
    if (br != NULL) {
        *br = (uint32_t)read;
    }
    if (read == 0 && btr > 0 && !feof(fd)) {
        return LV_FS_RES_FS_ERR;
    }
    return LV_FS_RES_OK;
}

/**
 * 文件写入回调
 * @param drv 文件系统驱动指针
 * @param file_p 文件句柄
 * @param buf 写入缓冲区
 * @param btw 要写入的字节数
 * @param bw 实际写入的字节数（输出）
 * @return LV_FS_RES_OK 成功，其他值表示失败
 */
static lv_fs_res_t fs_write_cb(lv_fs_drv_t *drv, void *file_p, const void *buf, uint32_t btw, uint32_t *bw)
{
    if (file_p == NULL || buf == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)drv->user_data;
    if (ctx == NULL) {
        return LV_FS_RES_FS_ERR;
    }

    // 如果平台提供了文件系统操作接口，使用平台接口
    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->write != NULL) {
        return ctx->ops->fs_ops->write(ctx, file_p, buf, btw, bw);
    }

    // 否则使用默认的 LuatOS 文件系统接口
    FILE *fd = (FILE *)file_p;
    size_t written = luat_fs_fwrite(buf, 1, btw, fd);
    if (bw != NULL) {
        *bw = (uint32_t)written;
    }
    if (written != btw) {
        return LV_FS_RES_FS_ERR;
    }
    return LV_FS_RES_OK;
}

/**
 * 文件定位回调
 * @param drv 文件系统驱动指针
 * @param file_p 文件句柄
 * @param pos 定位位置
 * @param whence 定位方式
 * @return LV_FS_RES_OK 成功，其他值表示失败
 */
static lv_fs_res_t fs_seek_cb(lv_fs_drv_t *drv, void *file_p, uint32_t pos, lv_fs_whence_t whence)
{
    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)drv->user_data;
    if (ctx == NULL) {
        return LV_FS_RES_FS_ERR;
    }

    // 如果平台提供了文件系统操作接口，使用平台接口
    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->seek != NULL) {
        return ctx->ops->fs_ops->seek(ctx, file_p, pos, whence);
    }

    // 否则使用默认的 LuatOS 文件系统接口
    int origin = SEEK_SET;
    if (whence == LV_FS_SEEK_CUR) {
        origin = SEEK_CUR;
    } else if (whence == LV_FS_SEEK_END) {
        origin = SEEK_END;
    }
    FILE *fd = (FILE *)file_p;
    return (luat_fs_fseek(fd, pos, origin) == 0) ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

/**
 * 文件位置查询回调
 * @param drv 文件系统驱动指针
 * @param file_p 文件句柄
 * @param pos_p 当前位置（输出）
 * @return LV_FS_RES_OK 成功，其他值表示失败
 */
static lv_fs_res_t fs_tell_cb(lv_fs_drv_t *drv, void *file_p, uint32_t *pos_p)
{
    if (file_p == NULL || pos_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    easylvgl_ctx_t *ctx = (easylvgl_ctx_t *)drv->user_data;
    if (ctx == NULL) {
        return LV_FS_RES_FS_ERR;
    }

    // 如果平台提供了文件系统操作接口，使用平台接口
    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->tell != NULL) {
        return ctx->ops->fs_ops->tell(ctx, file_p, pos_p);
    }

    // 否则使用默认的 LuatOS 文件系统接口
    FILE *fd = (FILE *)file_p;
    int pos = luat_fs_ftell(fd);
    if (pos < 0) {
        return LV_FS_RES_FS_ERR;
    }
    *pos_p = (uint32_t)pos;
    return LV_FS_RES_OK;
}

/**
 * 注册文件系统驱动
 * @param ctx 上下文指针
 * @param drv 文件系统驱动指针
 * @param letter 驱动字母
 * @return 0 成功，<0 失败
 */
static int fs_register_drv(easylvgl_ctx_t *ctx, lv_fs_drv_t *drv, char letter)
{
    if (ctx == NULL || drv == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    lv_fs_drv_init(drv);
    drv->letter = letter;
    drv->cache_size = 0;
    drv->ready_cb = fs_ready_cb;
    drv->open_cb = fs_open_cb;
    drv->close_cb = fs_close_cb;
    drv->read_cb = fs_read_cb;
    drv->write_cb = fs_write_cb;
    drv->seek_cb = fs_seek_cb;
    drv->tell_cb = fs_tell_cb;
    drv->user_data = ctx;  // 保存上下文指针，供回调函数使用

    lv_fs_drv_register(drv);
    LLOGD("easylvgl_fs: registered driver '%c'", letter);
    return 0;
}

/**********************
 *   GLOBAL FUNCTIONS
 **********************/

/**
 * 初始化文件系统驱动
 * @param ctx 上下文指针
 * @return 0 成功，<0 失败
 * @pre-condition ctx 必须非空且已初始化
 * @post-condition 文件系统驱动已注册到 LVGL
 */
int easylvgl_fs_init(easylvgl_ctx_t *ctx)
{
    if (ctx == NULL) {
        LLOGE("easylvgl_fs_init failed: ctx is NULL");
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // 注册两个文件系统驱动：'L' 和 '/'
    int ret = fs_register_drv(ctx, &ctx->fs_drv[0], 'L');
    if (ret != 0) {
        LLOGE("easylvgl_fs_init failed: register driver 'L' failed");
        return ret;
    }

    ret = fs_register_drv(ctx, &ctx->fs_drv[1], '/');
    if (ret != 0) {
        LLOGE("easylvgl_fs_init failed: register driver '/' failed");
        return ret;
    }

    LLOGD("easylvgl_fs_init: file system drivers initialized");
    return 0;
}

