#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"

#include "luat_image.h"
#include "luat_image_common.h"

#include <stdbool.h>

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

typedef struct {
    uint8_t *buf;
    size_t len;
    int owns_buf;
} png_input_t;

static uint32_t read_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static int png_read_file_to_buf(const char *path, png_input_t *input)
{
    FILE *fd = NULL;
    uint8_t *buf = NULL;
    long fsize = 0;

    if (path == NULL || input == NULL) {
        return LUAT_IMG_ERR;
    }

    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
        return LUAT_IMG_ERR;
    }

    luat_fs_fseek(fd, 0, SEEK_END);
    fsize = luat_fs_ftell(fd);
    luat_fs_fseek(fd, 0, SEEK_SET);
    if (fsize <= 0) {
        LLOGE("bad png file size %s", path);
        luat_fs_fclose(fd);
        return LUAT_IMG_ERR;
    }

    buf = (uint8_t *)luat_heap_malloc((size_t)fsize);
    if (buf == NULL) {
        LLOGE("oom: png file buf %ld bytes", fsize);
        luat_fs_fclose(fd);
        return LUAT_IMG_ERR;
    }

    if (luat_fs_fread(buf, 1, (size_t)fsize, fd) != (size_t)fsize) {
        LLOGE("read png file error %s", path);
        luat_heap_free(buf);
        luat_fs_fclose(fd);
        return LUAT_IMG_ERR;
    }

    luat_fs_fclose(fd);
    input->buf = buf;
    input->len = (size_t)fsize;
    input->owns_buf = 1;
    return LUAT_IMG_OK;
}

static int png_get_input(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, png_input_t *input)
{
    if (input == NULL) {
        return LUAT_IMG_ERR;
    }

    memset(input, 0, sizeof(*input));
    if (in_buf != NULL && in_len > 0) {
        input->buf = in_buf;
        input->len = in_len;
        return LUAT_IMG_OK;
    }

    if (img_conf == NULL || img_conf->source_path == NULL) {
        return LUAT_IMG_ERR;
    }

    return png_read_file_to_buf(img_conf->source_path, input);
}

static void png_release_input(png_input_t *input)
{
    if (input != NULL && input->owns_buf && input->buf != NULL) {
        luat_heap_free(input->buf);
        input->buf = NULL;
    }
}

static int png_probe_fail(const char *src_desc, const char *reason)
{
    LLOGW("png hw probe failed: %s, %s", src_desc != NULL ? src_desc : "<memory>", reason);
    return LUAT_IMG_ERR;
}

static int png_probe_mem_default(const uint8_t *data, size_t size, luat_img_info_t *img_info,
                                 const char *src_desc, int log_fail, uint32_t *idat_blocks,
                                 uint32_t pixel_size, int require_single_idat)
{
    size_t pos = 0;
    bool ihdr_seen = false;
    uint32_t local_idat_blocks = 0;
    uint32_t width = 0;
    uint32_t height = 0;

    if (data == NULL || size < 8 || img_info == NULL) {
        if (log_fail) {
            return png_probe_fail(src_desc, "invalid input buffer");
        }
        return LUAT_IMG_ERR;
    }

    if (data[0] != 0x89 || data[1] != 0x50 || data[2] != 0x4E || data[3] != 0x47
     || data[4] != 0x0D || data[5] != 0x0A || data[6] != 0x1A || data[7] != 0x0A) {
        if (log_fail) {
            return png_probe_fail(src_desc, "bad PNG signature");
        }
        return LUAT_IMG_ERR;
    }

    pos = 8;
    while (pos + 8 <= size) {
        uint32_t chunk_len;
        const uint8_t *chunk_type;

        chunk_len = read_be32(data + pos);
        pos += 4;
        chunk_type = data + pos;
        pos += 4;

        if (chunk_len > size - pos) {
            if (log_fail) {
                return png_probe_fail(src_desc, "chunk length exceeds buffer");
            }
            return LUAT_IMG_ERR;
        }
        if (size - (pos + chunk_len) < 4) {
            if (log_fail) {
                return png_probe_fail(src_desc, "missing PNG chunk CRC");
            }
            return LUAT_IMG_ERR;
        }

        if (chunk_type[0] == 'I' && chunk_type[1] == 'H' && chunk_type[2] == 'D' && chunk_type[3] == 'R') {
            if (chunk_len < 8) {
                if (log_fail) {
                    return png_probe_fail(src_desc, "IHDR chunk too short");
                }
                return LUAT_IMG_ERR;
            }

            width = read_be32(data + pos);
            height = read_be32(data + pos + 4);
            if (width == 0 || height == 0 || width > UINT16_MAX || height > UINT16_MAX) {
                if (log_fail) {
                    return png_probe_fail(src_desc, "invalid PNG dimensions");
                }
                return LUAT_IMG_ERR;
            }

            ihdr_seen = true;
        }
        else if (chunk_type[0] == 'I' && chunk_type[1] == 'D' && chunk_type[2] == 'A' && chunk_type[3] == 'T') {
            local_idat_blocks++;
            if (require_single_idat && local_idat_blocks > 1) {
                if (log_fail) {
                    return png_probe_fail(src_desc, "multiple IDAT blocks are not supported by hardware");
                }
                return LUAT_IMG_ERR;
            }
        }
        else if (chunk_type[0] == 'I' && chunk_type[1] == 'E' && chunk_type[2] == 'N' && chunk_type[3] == 'D') {
            pos += chunk_len + 4;
            break;
        }

        pos += chunk_len + 4;
    }

    if (!ihdr_seen || local_idat_blocks == 0) {
        if (log_fail) {
            return png_probe_fail(src_desc, !ihdr_seen ? "IHDR chunk not found" : "IDAT chunk not found");
        }
        return LUAT_IMG_ERR;
    }

    {
        uint64_t px_count = (uint64_t)width * (uint64_t)height;
        uint64_t size64 = px_count * (uint64_t)pixel_size;
        if (size64 > UINT32_MAX) {
            if (log_fail) {
                return png_probe_fail(src_desc, "decoded buffer size overflow");
            }
            return LUAT_IMG_ERR;
        }

        img_info->width = (uint16_t)width;
        img_info->height = (uint16_t)height;
        img_info->size = (uint32_t)size64;
    }

    if (idat_blocks != NULL) {
        *idat_blocks = local_idat_blocks;
    }

    return LUAT_IMG_OK;
}

#ifdef LUAT_USE_LODEPNG
#include "lodepng.h"

static int luat_png_probe_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len,
                                     luat_img_info_t* img_info) {
    png_input_t input;
    int ret;

    (void)img_conf;
    if (img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    ret = png_get_input(img_conf, in_buf, in_len, &input);
    if (ret != LUAT_IMG_OK) {
        return ret;
    }

    ret = png_probe_mem_default(input.buf, input.len, img_info, NULL, 0, NULL, (uint32_t)sizeof(luat_color_t), 0);
    png_release_input(&input);
    return ret;
}

int luat_png_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)img_conf;
    unsigned char *rgba = NULL;
    unsigned w = 0;
    unsigned h = 0;
    unsigned err = lodepng_decode32(&rgba, &w, &h, in_buf, in_len);
    if (err) {
        LLOGE("lodepng decode error %u", err);
        return LUAT_IMG_ERR;
    }
    if (luat_image_prepare_output(img_info, (uint16_t)w, (uint16_t)h) != LUAT_IMG_OK) {
        LLOGE("out of memory for png decode buffer");
        luat_heap_free(rgba);
        return LUAT_IMG_ERR;
    }

    luat_image_rgba_to_color_buffer(rgba, (uint32_t)w * h, (luat_color_t*)img_info->data);
    luat_heap_free(rgba);
    return LUAT_IMG_OK;
}

const luat_img_decoder_opts_t png_sw_decoder_opts = {
    .probe = luat_png_probe_sw_default,
    .decode = luat_png_decode_sw_default,
};
#endif /* LUAT_USE_LODEPNG */

#ifdef LUAT_USE_PNG
static int luat_png_probe_hw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len,
                                     luat_img_info_t* img_info) {
    png_input_t input;
    uint32_t idat_blocks = 0;
    int ret;

    if (img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    ret = png_get_input(img_conf, in_buf, in_len, &input);
    if (ret != LUAT_IMG_OK) {
        return ret;
    }

    ret = png_probe_mem_default(input.buf, input.len, img_info,
                                img_conf != NULL ? img_conf->source_path : NULL, 1,
                                &idat_blocks, 4u, 1);
    if (ret == LUAT_IMG_OK && idat_blocks != 1) {
        LLOGW("png hw probe failed: %s, unsupported IDAT block count=%u",
              img_conf != NULL && img_conf->source_path != NULL ? img_conf->source_path : "<memory>",
              (unsigned int)idat_blocks);
        ret = LUAT_IMG_ERR;
    }

    png_release_input(&input);
    return ret;
}

LUAT_WEAK int luat_png_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)img_conf;
    (void)in_buf;
    (void)in_len;
    (void)img_info;
    return LUAT_IMG_ERR;
}

const luat_img_decoder_opts_t png_hw_decoder_opts = {
    .probe = luat_png_probe_hw_default,
    .decode = luat_png_decode_hw,
};
#endif /* LUAT_USE_PNG */
