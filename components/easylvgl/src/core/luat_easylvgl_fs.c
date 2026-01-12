/**
 * @file luat_easylvgl_fs.c
 * @summary EasyLVGL 文件系统驱动实现
 * 整体流程为三层：
    *  底层是 luat_fs 的文件系统接口（读写、打开、关闭等），负责直接跟存储打交道。
    * 中间层是 EasyLVGL 的 internal 实现，它把 luat_fs 的 API 包装成 LVGL 需要的回调函数（比如 lv_fs_drv_t 的 read_cb、open_cb 等），并做一些适配。
    * 最上层是 LVGL 本身，它用注册好的 lv_fs_drv_t 接口来访问文件（比如加载图片、Lottie、字体）。LVGL 调用这些回调，最终走到中间层再到底层去完成实际的文件操作。
*/

#include "luat_easylvgl.h"
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_log.h"
#include "luat_malloc.h"
#include "luat_mem.h"
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

static FILE *fs_fopen_default(const char *path, lv_fs_mode_t mode);

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
 * 尝试调用上下文绑定的文件打开接口，失败则使用默认实现
 * @param ctx EasyLVGL 上下文
 * @param path 标准化后文件路径
 * @param mode LVGL 文件访问模式
 * @return 文件句柄
 */
static void *fs_open_internal(easylvgl_ctx_t *ctx, const char *path, lv_fs_mode_t mode)
{
    if (ctx == NULL) {
        return NULL;
    }

    if (ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->open != NULL) {
        return ctx->ops->fs_ops->open(ctx, path, mode);
    }

    return fs_fopen_default(path, mode);
}

/**
 * 用平台回调或默认 fread 实现读取数据
 * @param ctx EasyLVGL 上下文
 * @param file_p 打开句柄
 * @param buf 目标缓冲区
 * @param btr 期望读取字节数
 * @param br 实际读取字节数输出
 */
static lv_fs_res_t fs_read_internal(easylvgl_ctx_t *ctx, void *file_p, void *buf, uint32_t btr, uint32_t *br)
{
    if (ctx != NULL && ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->read != NULL) {
        return ctx->ops->fs_ops->read(ctx, file_p, buf, btr, br);
    }

    if (file_p == NULL || buf == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

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
 * 关闭文件句柄（优先调用上下文提供的回调）
 * @param ctx EasyLVGL 上下文
 * @param file_p 需要关闭的句柄
 */
static lv_fs_res_t fs_close_internal(easylvgl_ctx_t *ctx, void *file_p)
{
    if (ctx != NULL && ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->close != NULL) {
        return ctx->ops->fs_ops->close(ctx, file_p);
    }

    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    FILE *fd = (FILE *)file_p;
    return (luat_fs_fclose(fd) == 0) ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

/**
 * 调整文件读写位置，用于查询长度或数据复位
 * @param ctx EasyLVGL 上下文
 * @param file_p 文件句柄
 * @param pos 相对位置
 * @param whence 参考点
 */
static lv_fs_res_t fs_seek_internal(easylvgl_ctx_t *ctx, void *file_p, uint32_t pos, lv_fs_whence_t whence)
{
    if (ctx != NULL && ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->seek != NULL) {
        return ctx->ops->fs_ops->seek(ctx, file_p, pos, whence);
    }

    if (file_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

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
 * 返回当前文件位置，辅助判断总长度
 * @param ctx EasyLVGL 上下文
 * @param file_p 文件句柄
 * @param pos_p 输出当前位置
 */
static lv_fs_res_t fs_tell_internal(easylvgl_ctx_t *ctx, void *file_p, uint32_t *pos_p)
{
    if (ctx != NULL && ctx->ops != NULL && ctx->ops->fs_ops != NULL && ctx->ops->fs_ops->tell != NULL) {
        return ctx->ops->fs_ops->tell(ctx, file_p, pos_p);
    }

    if (file_p == NULL || pos_p == NULL) {
        return LV_FS_RES_INV_PARAM;
    }

    FILE *fd = (FILE *)file_p;
    int pos = luat_fs_ftell(fd);
    if (pos < 0) {
        return LV_FS_RES_FS_ERR;
    }

    *pos_p = (uint32_t)pos;
    return LV_FS_RES_OK;
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

    return fs_open_internal(ctx, file_path, mode);
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

    return fs_close_internal(ctx, file_p);
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

    return fs_read_internal(ctx, file_p, buf, btr, br);
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

    return fs_seek_internal(ctx, file_p, pos, whence);
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

    return fs_tell_internal(ctx, file_p, pos_p);
}

/**
 * 从文件路径读取全部数据（兼容 LuatOS 平台接口）
 * @param ctx 上下文指针
 * @param path LVGL 文件路径（包含驱动字母）
 * @param out_data 输出缓冲，调用方负责释放
 * @param out_len 输出长度
 * @return true 成功，false 失败
 */
bool easylvgl_fs_load_file(easylvgl_ctx_t *ctx, const char *path, void **out_data, size_t *out_len)
{
    if (ctx == NULL || path == NULL || out_data == NULL || out_len == NULL) {
        return false;
    }

    char file_path[EASYLVGL_FS_PATH_MAX] = {0};
    // 将 LVGL 风格路径转换成 LuatOS 可识别的绝对路径
    fs_build_path(path, file_path, sizeof(file_path));

    // 打开文件，如果平台接口提供替代实现会优先调用
    void *file_p = fs_open_internal(ctx, file_path, LV_FS_MODE_RD);
    if (file_p == NULL) {
        LLOGW("easylvgl_fs_load_file: open %s failed", file_path);
        return false;
    }

    // 跳到文件尾以便查询文件长度
    if (fs_seek_internal(ctx, file_p, 0, LV_FS_SEEK_END) != LV_FS_RES_OK) {
        fs_close_internal(ctx, file_p);
        return false;
    }

    uint32_t length = 0;
    if (fs_tell_internal(ctx, file_p, &length) != LV_FS_RES_OK) {
        fs_close_internal(ctx, file_p);
        return false;
    }

    if (fs_seek_internal(ctx, file_p, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        fs_close_internal(ctx, file_p);
        return false;
    }

    if (length == 0) {
        fs_close_internal(ctx, file_p);
        void *empty_buf = luat_heap_malloc(1);
        if (empty_buf == NULL) {
            return false;
        }
        ((char *)empty_buf)[0] = '\0';
        *out_data = empty_buf;
        *out_len = 0;
        return true;
    }

    // 为文件内容分配psram内存，末尾预留空字符
    void *buffer = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, length + 1);
    if (buffer == NULL) {
        fs_close_internal(ctx, file_p);
        return false;
    }

    uint32_t read_len = 0;
    if (fs_read_internal(ctx, file_p, buffer, length, &read_len) != LV_FS_RES_OK) {
        fs_close_internal(ctx, file_p);
        luat_heap_opt_free(LUAT_HEAP_PSRAM, buffer);
        return false;
    }

    fs_close_internal(ctx, file_p);

    // 读取字节数必须与文件长度一致
    if (read_len != length) {
        luat_heap_opt_free(LUAT_HEAP_PSRAM, buffer);
        return false;
    }

    ((char *)buffer)[read_len] = '\0';
    *out_data = buffer;
    *out_len = read_len;
    return true;
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

    // 注册文件系统驱动： '/'
    int ret = fs_register_drv(ctx, &ctx->fs_drv, '/');
    if (ret != 0) {
        LLOGE("easylvgl_fs_init failed: register driver '/' failed");
        return ret;
    }

    LLOGD("easylvgl_fs_init: file system drivers initialized");
    return 0;
}

