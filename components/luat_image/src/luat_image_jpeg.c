#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_fs.h"

#include "luat_image.h"
#include "luat_jpeg.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

typedef struct {
    uint8_t *buf;
    size_t len;
    int owns_buf;
} jpeg_input_t;

static int jpeg_read_file_to_buf(const char *path, jpeg_input_t *input) {
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
        LLOGE("bad jpeg file size %s", path);
        luat_fs_fclose(fd);
        return LUAT_IMG_ERR;
    }

    /* HW decoder on CCM42xx requires 8-byte aligned image_addr. */
    buf = (uint8_t *)luat_heap_memalign(8, (size_t)fsize);
    if (buf == NULL) {
        LLOGE("oom: jpeg file buf %ld bytes", fsize);
        luat_fs_fclose(fd);
        return LUAT_IMG_ERR;
    }

    if (luat_fs_fread(buf, 1, (size_t)fsize, fd) != (size_t)fsize) {
        LLOGE("read jpeg file error %s", path);
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

static int jpeg_get_input(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, jpeg_input_t *input) {
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

    return jpeg_read_file_to_buf(img_conf->source_path, input);
}

static void jpeg_release_input(jpeg_input_t *input) {
    if (input != NULL && input->owns_buf && input->buf != NULL) {
        luat_heap_free(input->buf);
        input->buf = NULL;
    }
}

static int jpeg_probe_mem_default(const uint8_t *data, size_t size, luat_img_info_t *img_info) {
    size_t pos = 0;

    if (data == NULL || size < 4 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    if (data[0] != 0xFF || data[1] != 0xD8) {
        return LUAT_IMG_ERR;
    }

    pos = 2;
    while (pos + 4 <= size) {
        uint8_t marker;
        uint16_t seg_len;

        while (pos < size && data[pos] == 0xFF) {
            pos++;
        }
        if (pos >= size) {
            break;
        }

        marker = data[pos++];
        if (marker == 0xD9 || marker == 0xDA) {
            break;
        }

        if (pos + 2 > size) {
            break;
        }

        seg_len = (uint16_t)(((uint16_t)data[pos] << 8) | data[pos + 1]);
        pos += 2;
        if (seg_len < 2 || pos + seg_len - 2 > size) {
            break;
        }

        if ((marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF)) {
            if (seg_len < 7) {
                break;
            }

            img_info->height = (uint16_t)(((uint16_t)data[pos + 1] << 8) | data[pos + 2]);
            img_info->width = (uint16_t)(((uint16_t)data[pos + 3] << 8) | data[pos + 4]);
            if (img_info->width == 0 || img_info->height == 0) {
                return LUAT_IMG_ERR;
            }

            img_info->size = (uint32_t)img_info->width * img_info->height * sizeof(luat_color_t);
            return LUAT_IMG_OK;
        }

        pos += seg_len - 2;
    }

    return LUAT_IMG_ERR;
}

LUAT_WEAK int luat_jpeg_hw_info(const uint8_t *data, size_t size, luat_jpeg_info_t *info) {
    luat_img_info_t img_info = {0};
    void *ctx = NULL;
    int ret;

    if (info == NULL) {
        return LUAT_IMG_ERR;
    }

    ret = luat_jpeg_hw_init(&ctx);
    if (ret != LUAT_IMG_OK) {
        return LUAT_IMG_ERR;
    }
    luat_jpeg_hw_deinit(ctx);

    ret = jpeg_probe_mem_default(data, size, &img_info);
    if (ret != LUAT_IMG_OK) {
        return ret;
    }

    info->width = img_info.width;
    info->height = img_info.height;
    return LUAT_IMG_OK;
}

LUAT_WEAK int luat_jpeg_hw_init(void **ctx) {
    (void)ctx;
    return LUAT_IMG_ERR;
}

LUAT_WEAK int luat_jpeg_hw_decode(void *ctx, const uint8_t *data, size_t size, void *frame) {
    (void)ctx;
    (void)data;
    (void)size;
    (void)frame;
    return LUAT_IMG_ERR;
}

LUAT_WEAK void luat_jpeg_hw_deinit(void *ctx) {
    (void)ctx;
}

static int luat_jpeg_probe_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    jpeg_input_t input;
    int ret;
    luat_jpeg_info_t info;

    if (img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    ret = jpeg_get_input(img_conf, in_buf, in_len, &input);
    if (ret != LUAT_IMG_OK) {
        return ret;
    }

    if (img_conf != NULL && img_conf->decode_mode == LUAT_IMG_DECODE_HW) {
        ret = luat_jpeg_hw_info(input.buf, input.len, &info);
        if (ret == LUAT_IMG_OK) {
            img_info->width = info.width;
            img_info->height = info.height;
            img_info->size = (uint32_t)info.width * info.height * sizeof(luat_color_t);
        }
    } else {
        ret = jpeg_probe_mem_default(input.buf, input.len, img_info);
    }

    jpeg_release_input(&input);
    return ret;
}

#ifdef LUAT_USE_TJPGD
#include "tjpgd.h"
#include "tjpgdcnf.h"

typedef struct {
    const uint8_t *data;
    size_t len;
    size_t pos;
} mem_reader_t;

static unsigned int decode_mem_in_func(JDEC* jd, uint8_t* buff, unsigned int nbyte) {
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    mem_reader_t *reader = (mem_reader_t*)img_info->userdata;
    size_t available = reader->len - reader->pos;
    if ((size_t)nbyte > available) nbyte = (unsigned int)available;
    if (buff) {
        memcpy(buff, reader->data + reader->pos, nbyte);
    }
    reader->pos += nbyte;
    return nbyte;
}

static int decode_out_func(JDEC* jd, void* bitmap, JRECT* rect) {
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    luat_color_t *tmp = (luat_color_t*)bitmap;
    luat_color_t *out = (luat_color_t*)img_info->data;
    uint16_t idx = 0;
    for (size_t y = rect->top; y <= rect->bottom; y++) {
        size_t offset = (size_t)y * img_info->width + rect->left;
        for (size_t x = rect->left; x <= rect->right; x++) {
            out[offset] = tmp[idx];
            offset++;
            idx++;
        }
    }
    return 1;
}

int luat_jpeg_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    JRESULT res;
    JDEC jdec;
    void *work = NULL;
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3;
#else
    size_t sz_work = 3500;
#endif
    (void)img_conf;
    if (in_buf == NULL || in_len == 0 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }
    mem_reader_t reader = {in_buf, in_len, 0};
    img_info->userdata = &reader;
    work = luat_heap_malloc(sz_work);
    if (work == NULL) {
        LLOGE("out of memory when malloc jpeg decode workbuff");
        goto error;
    }
    res = luat_jd_prepare(&jdec, decode_mem_in_func, work, sz_work, img_info);
    if (res != JDR_OK) {
        LLOGW("luat_jd_prepare mem error %d", res);
        goto error;
    }
    img_info->width = jdec.width;
    img_info->height = jdec.height;
    img_info->size = (uint32_t)jdec.width * jdec.height * sizeof(luat_color_t);
    img_info->data = (uint8_t*)luat_heap_malloc(img_info->size);
    if (img_info->data == NULL) {
        LLOGE("out of memory when malloc jpeg image buff");
        goto error;
    }
    res = luat_jd_decomp(&jdec, decode_out_func, 0);
    if (res != JDR_OK) {
        LLOGW("luat_jd_decomp mem error %d", res);
        goto error;
    }
    luat_heap_free(work);
    return LUAT_IMG_OK;
error:
    if (work) luat_heap_free(work);
    if (img_info->data) {
        luat_heap_free(img_info->data);
        img_info->data = NULL;
    }
    return LUAT_IMG_ERR;
}

const luat_img_decoder_opts_t jpeg_sw_decoder_opts = {
    .probe = luat_jpeg_probe_default,
    .decode = luat_jpeg_decode_sw_default,
};
#endif /* LUAT_USE_TJPGD */

#ifdef LUAT_USE_JPG
LUAT_WEAK int luat_jpeg_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    jpeg_input_t input;
    luat_jpeg_frame_t frame = {0};
    void *ctx = NULL;
    int ret;

    if (img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    ret = jpeg_get_input(img_conf, in_buf, in_len, &input);
    if (ret != LUAT_IMG_OK) {
        return LUAT_IMG_ERR;
    }

    ret = luat_jpeg_hw_init(&ctx);
    if (ret != LUAT_IMG_OK) {
        jpeg_release_input(&input);
        return LUAT_IMG_ERR;
    }

    ret = luat_jpeg_hw_decode(ctx, input.buf, input.len, &frame);
    luat_jpeg_hw_deinit(ctx);
    jpeg_release_input(&input);
    if (ret != LUAT_IMG_OK || frame.data == NULL || frame.width == 0 || frame.height == 0) {
        if (frame.data != NULL) {
            luat_heap_free(frame.data);
        }
        return LUAT_IMG_ERR;
    }

    img_info->width = frame.width;
    img_info->height = frame.height;
    img_info->size = (uint32_t)frame.width * frame.height * sizeof(luat_color_t);
    img_info->data = frame.data;
    return LUAT_IMG_OK;
}

static int jpeg_hw_decode_fn(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    jpeg_input_t input;
    int ret;

    if (img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    ret = jpeg_get_input(img_conf, in_buf, in_len, &input);
    if (ret != LUAT_IMG_OK) {
        return ret;
    }

    ret = luat_jpeg_decode_hw(img_conf, input.buf, input.len, img_info);
    jpeg_release_input(&input);
    return ret;
}

const luat_img_decoder_opts_t jpeg_hw_decoder_opts = {
    .probe = luat_jpeg_probe_default,
    .decode = jpeg_hw_decode_fn,
};
#endif /* LUAT_USE_JPG */
