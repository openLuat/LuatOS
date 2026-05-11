#ifndef LUAT_IMAGE_H
#define LUAT_IMAGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_IMG_OK             0
#define LUAT_IMG_ERR            (-1)

typedef enum {
    LUAT_IMG_FMT_JPG  = 0,
    LUAT_IMG_FMT_PNG  = 1,
} luat_img_format_t;


typedef enum {
    LUAT_IMG_DECODE_SW = 0,
    LUAT_IMG_DECODE_HW = 1,
} luat_img_decode_mode_t;

typedef struct {
    luat_img_format_t format;
    luat_img_decode_mode_t decode_mode;
} luat_img_conf_t;

typedef struct {
    uint16_t width;
    uint16_t height;
    uint32_t size;
    uint8_t *data;
    void* userdata; // 供解码函数使用的用户数据指针
} luat_img_info_t;

/* jpeg decode */
// 默认的software解码函数,使用tjpgd库解码jpeg图片
int luat_jpeg_decode_sw_default(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
// 下面两个函数可自行实现
int luat_jpeg_decode_sw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
int luat_jpeg_decode_hw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
/* png decode */
// 下面两个函数可自行实现
int luat_png_decode_sw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
int luat_png_decode_hw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);

int luat_image_decode(luat_img_conf_t* img_conf, uint8_t *in_buf, size_t size, luat_img_info_t* img_info);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_IMAGE_H */
