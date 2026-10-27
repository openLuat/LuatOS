#include "luat_base.h"
#include "luat_mem.h"
#include "luat_fs.h"
#include "luat_image.h"
#include "luat_display.h"
#include "luat_display_surface.h"
#include "luat_display_image.h"

#define LUAT_LOG_TAG "display"
#include "luat_log.h"

/* luat_image 解码输出与 draw_buf 一致，都是 native 排列的像素值
 * （TJpgD JD_FORMAT=1 输出 RGB565 数值，PNG 路径同样走 native RGB565），
 * 因此这里不需要再做字节交换，draw 阶段直接 blit_copy。 */
static void display_image_surf_init(luat_display_image_t *img, const luat_img_info_t *info)
{
    img->pixels = info->data;
    img->size = info->size;
    img->surf.w = info->width;
    img->surf.h = info->height;
#if (LUAT_LCD_COLOR_DEPTH == 16)
    img->surf.bpp = 16;
    img->surf.pitch = info->width * 2;
    img->surf.fmt = LUAT_DISPLAY_FORMAT_RGB565;
#else
    img->surf.bpp = 32;
    img->surf.pitch = info->width * 4;
    img->surf.fmt = LUAT_DISPLAY_FORMAT_RGB888;
#endif
    img->surf.pixels = info->data;
    img->surf.clip.x1 = 0;
    img->surf.clip.y1 = 0;
    img->surf.clip.x2 = info->width;
    img->surf.clip.y2 = info->height;
    img->surf.reserv = NULL;
}

static int display_image_decode_into(luat_display_image_t *img, luat_img_conf_t *conf, uint8_t *in_buf, size_t in_len)
{
    luat_img_info_t info = {0};
    int ret;

    if (img == NULL || conf == NULL) {
        return -1;
    }
    ret = luat_image_decode(conf, in_buf, in_len, &info);
    if (ret != LUAT_IMG_OK || info.data == NULL ||
        info.width == 0 || info.height == 0) {
        if (info.data != NULL) {
            luat_heap_free(info.data);
        }
        LLOGW("image decode error %d", ret);
        return -1;
    }
    display_image_surf_init(img, &info);
    LLOGI("image_loaded %dx%d %uB", (int)info.width, (int)info.height, (unsigned)info.size);
    return 0;
}

int luat_display_image_load_path(luat_display_image_t *img, const char *path)
{
    luat_img_conf_t conf = {0};
    FILE *fd;
    uint8_t hdr[16];
    size_t rd;

    if (img == NULL || path == NULL) {
        return -1;
    }
    /* 按文件头 magic 识别格式 */
    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
        return -1;
    }
    rd = luat_fs_fread(hdr, 1, sizeof(hdr), fd);
    luat_fs_fclose(fd);
    if (rd < 4) {
        return -1;
    }
    if (rd >= 3 && hdr[0] == 0xFF && hdr[1] == 0xD8 && hdr[2] == 0xFF) {
        conf.format = LUAT_IMG_FMT_JPG;
    } else if (rd >= 8 && hdr[0] == 0x89 && hdr[1] == 'P' && hdr[2] == 'N' && hdr[3] == 'G') {
        conf.format = LUAT_IMG_FMT_PNG;
    } else if (rd >= 12 && memcmp(hdr, "RIFF", 4) == 0 && memcmp(hdr + 8, "WEBP", 4) == 0) {
        conf.format = LUAT_IMG_FMT_WEBP;
    } else {
        LLOGW("unsupported image magic %s", path);
        return -1;
    }
    conf.decode_mode = LUAT_IMG_DECODE_SW;
    conf.source_path = path;
    return display_image_decode_into(img, &conf, NULL, 0);
}

int luat_display_image_load_data(luat_display_image_t *img, const uint8_t *data, size_t len, int fmt)
{
    luat_img_conf_t conf = {0};

    if (img == NULL || data == NULL || len == 0) {
        return -1;
    }
    conf.format = (luat_img_format_t)fmt;
    conf.decode_mode = LUAT_IMG_DECODE_SW;
    return display_image_decode_into(img, &conf, (uint8_t *)data, len);
}

void luat_display_image_free(luat_display_image_t *img)
{
    if (img == NULL) {
        return;
    }
    if (img->pixels != NULL) {
        luat_heap_free(img->pixels);
        img->pixels = NULL;
        img->size = 0;
    }
}

int luat_display_draw_image_default(struct luat_display *disp, SURFACE *img, int x, int y)
{
    if (disp == NULL || img == NULL || img->pixels == NULL) {
        return -1;
    }
    if (luat_draw_set_display_target(disp) != 0) {
        return -1;
    }
    return luat_draw_surface(img, x, y);
}

LUAT_WEAK int luat_display_draw_image(struct luat_display *disp, SURFACE *img, int x, int y)
{
    return luat_display_draw_image_default(disp, img, x, y);
}

/* 一次性绘制：路径 -> 解码 -> 绘制 -> 释放，不保留解码缓冲，也不自动 flush */
int luat_display_draw_image_file(struct luat_display *disp, const char *path, int x, int y)
{
    luat_display_image_t img;
    int ret;

    if (disp == NULL || path == NULL) {
        return -1;
    }
    memset(&img, 0, sizeof(img));
    ret = luat_display_image_load_path(&img, path);
    if (ret == 0) {
        ret = luat_display_draw_image(disp, &img.surf, x, y);
    }
    luat_display_image_free(&img);
    return ret;
}
