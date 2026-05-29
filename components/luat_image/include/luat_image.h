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
    LUAT_IMG_FMT_WEBP = 2,
} luat_img_format_t;

typedef enum {
    LUAT_IMG_DECODE_SW = 0,
    LUAT_IMG_DECODE_HW = 1,
} luat_img_decode_mode_t;

typedef struct {
    luat_img_format_t format;
    luat_img_decode_mode_t decode_mode;
    const char *source_path;
} luat_img_conf_t;

typedef struct {
    uint16_t width;
    uint16_t height;
    uint32_t size;
    uint8_t *data;
    void* userdata; // 供解码函数使用的用户数据指针
} luat_img_info_t;

/*
 * Image decoder opts — mirrors luat_codec_opts_t pattern from multimedia/codec.
 * Each decoder implementation provides a const instance of this struct.
 */
typedef struct luat_img_decoder_opts {
    int (*decode)(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
} luat_img_decoder_opts_t;

/* Table index: format * 2 + mode  (SW=0, HW=1) */
#define LUAT_IMG_DECODER_KEY(fmt, mode)  ((int)(fmt) * 2 + (int)(mode))

/* Lookup a decoder from the built-in opts table */
const luat_img_decoder_opts_t* luat_image_get_decoder_opts(luat_img_format_t fmt, luat_img_decode_mode_t mode);

/* Toggle decode timing logs for all image decoders routed via luat_image_decode */
void luat_image_set_debug(int enable);
int luat_image_get_debug(void);

/* --- Legacy / default decode helpers --- */
/* JPEG SW default (tjpgd), available when LUAT_USE_TJPGD is defined */
int luat_jpeg_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
/* PNG SW default (lodepng), available when LUAT_USE_LODEPNG is defined */
int luat_png_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
/* WebP SW default (libwebp), available when LUAT_USE_WEBP is defined */
#ifdef LUAT_USE_WEBP
int luat_webp_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
#endif
/* HW decode stubs — BSP platforms override these via LUAT_WEAK
 * luat_jpeg_decode_hw: only declared/defined when LUAT_USE_JPG is set
 * luat_png_decode_hw:  only declared/defined when LUAT_USE_PNG_HW is set
 * luat_webp_decode_hw: only declared/defined when LUAT_USE_WEBP is set */
#ifdef LUAT_USE_JPG_HW
int luat_jpeg_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
#endif
#ifdef LUAT_USE_PNG_HW
int luat_png_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
#endif
#ifdef LUAT_USE_WEBP
int luat_webp_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info);
#endif

/* Top-level decode entry point */
int luat_image_decode(luat_img_conf_t* img_conf, uint8_t *in_buf, size_t size, luat_img_info_t* img_info);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_IMAGE_H */
