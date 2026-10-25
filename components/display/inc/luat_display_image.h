#ifndef LUAT_DISPLAY_IMAGE_H
#define LUAT_DISPLAY_IMAGE_H

#include "luat_display.h"
#include "luat_display_surface.h"

#define LUAT_DISPLAY_IMAGE_MT "DISPLAY_IMAGE"

/* 图片 userdata 载荷：surf 描述解码后的像素平面，pixels 持有像素缓冲 */
typedef struct {
    SURFACE surf;
    uint8_t *pixels;    /* 解码像素缓冲（native RGB565），由 free/gc 释放 */
    uint32_t size;      /* 像素缓冲字节数 */
} luat_display_image_t;

/* 从文件解码装载图片；按文件头 magic 自动识别 jpg/png/webp */
int luat_display_image_load_path(luat_display_image_t *img, const char *path);
/* 从内存数据解码装载图片；fmt 取 luat_img_format_t */
int luat_display_image_load_data(luat_display_image_t *img, const uint8_t *data, size_t len, int fmt);
/* 释放像素缓冲，可重复调用 */
void luat_display_image_free(luat_display_image_t *img);

/* 绘制图片到 display 的 draw_buf（不自动 flush），BSP 可覆盖做硬件加速 */
int luat_display_draw_image_default(struct luat_display *disp, SURFACE *img, int x, int y);
int luat_display_draw_image(struct luat_display *disp, SURFACE *img, int x, int y);

/* 一次性绘制：直接给路径，内部完成 解码->绘制->释放（用完即弃，不缓存） */
int luat_display_draw_image_file(struct luat_display *disp, const char *path, int x, int y);

#endif /* LUAT_DISPLAY_IMAGE_H */
