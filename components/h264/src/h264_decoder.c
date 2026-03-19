#include <string.h>
#include <stdlib.h>
#include "h264_common.h"
#include "../include/h264_decoder.h"

/* Memory allocation macros with fallback */
#ifdef LUAT_HEAP_MALLOC
#include "luat_malloc.h"
#define H264_MALLOC  luat_heap_malloc
#define H264_FREE    luat_heap_free
#else
#define H264_MALLOC  malloc
#define H264_FREE    free
#endif

/* Forward declarations */
int h264_parse_nal_header(uint8_t byte, int *nal_unit_type, int *nal_ref_idc);
int h264_find_next_nal(const uint8_t *data, int size, int *nal_start, int *nal_size);
int h264_nalu_to_rbsp(const uint8_t *nalu_data, int nalu_size,
                      uint8_t *rbsp_data, int rbsp_size);
int h264_parse_sps(H264BitStream *bs, H264SPS *sps);
int h264_parse_pps(H264BitStream *bs, H264PPS *pps, H264SPS sps_array[32]);
int h264_parse_slice_header(H264BitStream *bs, H264Decoder *dec, H264SliceHeader *sh);
int h264_decode_slice(H264Decoder *dec, H264BitStream *bs, H264SliceHeader *sh);
void h264_deblock_frame(H264Decoder *dec, H264Frame *frame);

/* ---- Create / Destroy ---- */

H264Decoder *h264_decoder_create(void)
{
    H264Decoder *dec = (H264Decoder *)H264_MALLOC(sizeof(H264Decoder));
    if (!dec) return NULL;
    memset(dec, 0, sizeof(*dec));
    dec->active_sps_id = -1;
    dec->active_pps_id = -1;
    return dec;
}

static void free_frame_buffers(H264Decoder *dec)
{
    if (dec->frame_y)  { H264_FREE(dec->frame_y);  dec->frame_y  = NULL; }
    if (dec->frame_cb) { H264_FREE(dec->frame_cb); dec->frame_cb = NULL; }
    if (dec->frame_cr) { H264_FREE(dec->frame_cr); dec->frame_cr = NULL; }
    if (dec->mbs)      { H264_FREE(dec->mbs);      dec->mbs      = NULL; }
}

static void free_ref_frames(H264Decoder *dec)
{
    int i;
    for (i = 0; i < H264_MAX_REF; i++) {
        if (dec->ref[i].y)  { H264_FREE(dec->ref[i].y);  dec->ref[i].y  = NULL; }
        if (dec->ref[i].cb) { H264_FREE(dec->ref[i].cb); dec->ref[i].cb = NULL; }
        if (dec->ref[i].cr) { H264_FREE(dec->ref[i].cr); dec->ref[i].cr = NULL; }
        dec->ref[i].is_valid = 0;
    }
    dec->num_ref = 0;
}

void h264_decoder_destroy(H264Decoder *dec)
{
    if (!dec) return;
    free_frame_buffers(dec);
    free_ref_frames(dec);
    H264_FREE(dec);
}

/* ---- Frame buffer allocation ---- */

static int alloc_frame_buffers(H264Decoder *dec, int width, int height)
{
    if (dec->frame_width == width && dec->frame_height == height &&
        dec->frame_y != NULL) {
        return H264_OK;
    }

    free_frame_buffers(dec);

    int stride   = width;
    int c_stride = (width + 1) / 2;
    int c_height = (height + 1) / 2;

    dec->frame_y  = (uint8_t *)H264_MALLOC((size_t)(stride * height));
    dec->frame_cb = (uint8_t *)H264_MALLOC((size_t)(c_stride * c_height));
    dec->frame_cr = (uint8_t *)H264_MALLOC((size_t)(c_stride * c_height));

    int mb_w = (width  + 15) / 16;
    int mb_h = (height + 15) / 16;
    dec->mbs = (H264MacroBlock *)H264_MALLOC(
                    (size_t)(mb_w * mb_h) * sizeof(H264MacroBlock));

    if (!dec->frame_y || !dec->frame_cb || !dec->frame_cr || !dec->mbs) {
        free_frame_buffers(dec);
        return H264_ERR_NOMEM;
    }

    memset(dec->frame_y,  128, (size_t)(stride * height));
    memset(dec->frame_cb, 128, (size_t)(c_stride * c_height));
    memset(dec->frame_cr, 128, (size_t)(c_stride * c_height));
    memset(dec->mbs, 0, (size_t)(mb_w * mb_h) * sizeof(H264MacroBlock));

    dec->frame_width   = width;
    dec->frame_height  = height;
    dec->frame_stride  = stride;
    dec->frame_c_stride = c_stride;
    dec->mb_width      = mb_w;
    dec->mb_height     = mb_h;
    dec->mb_count      = mb_w * mb_h;

    return H264_OK;
}

/* ---- Save reference frame ---- */

static void save_reference_frame(H264Decoder *dec)
{
    H264RefPic *ref = &dec->ref[0];
    int w = dec->frame_width, h = dec->frame_height;
    int stride   = dec->frame_stride;
    int c_stride = dec->frame_c_stride;
    int c_h      = (h + 1) / 2;

    if (!ref->y || ref->width != w || ref->height != h) {
        if (ref->y)  H264_FREE(ref->y);
        if (ref->cb) H264_FREE(ref->cb);
        if (ref->cr) H264_FREE(ref->cr);
        ref->y  = (uint8_t *)H264_MALLOC((size_t)(stride * h));
        ref->cb = (uint8_t *)H264_MALLOC((size_t)(c_stride * c_h));
        ref->cr = (uint8_t *)H264_MALLOC((size_t)(c_stride * c_h));
        if (!ref->y || !ref->cb || !ref->cr) {
            if (ref->y)  H264_FREE(ref->y);
            if (ref->cb) H264_FREE(ref->cb);
            if (ref->cr) H264_FREE(ref->cr);
            ref->y = ref->cb = ref->cr = NULL;
            ref->is_valid = 0;
            return;
        }
    }

    memcpy(ref->y,  dec->frame_y,  (size_t)(stride * h));
    memcpy(ref->cb, dec->frame_cb, (size_t)(c_stride * c_h));
    memcpy(ref->cr, dec->frame_cr, (size_t)(c_stride * c_h));
    ref->width   = w;
    ref->height  = h;
    ref->stride  = stride;
    ref->c_stride = c_stride;
    ref->is_valid = 1;
    if (dec->num_ref == 0) dec->num_ref = 1;
}

/* ---- NAL dispatch ---- */

int h264_decode_nal(H264Decoder *dec, const uint8_t *nal_data, int nal_size,
                    H264Frame *frame)
{
    if (!dec || !nal_data || nal_size < 1) return H264_ERR_PARAM;

    if (frame) {
        frame->is_valid = 0;
        frame->y = frame->cb = frame->cr = NULL;
    }

    int nal_unit_type, nal_ref_idc;
    if (h264_parse_nal_header(nal_data[0], &nal_unit_type, &nal_ref_idc) != H264_OK)
        return H264_ERR_BITSTREAM;

    /* Remove emulation prevention bytes */
    int rbsp_size_max = nal_size + 16;
    uint8_t *rbsp = (uint8_t *)H264_MALLOC((size_t)rbsp_size_max);
    if (!rbsp) return H264_ERR_NOMEM;

    int rbsp_size = h264_nalu_to_rbsp(nal_data + 1, nal_size - 1, rbsp, rbsp_size_max);
    if (rbsp_size < 0) {
        H264_FREE(rbsp);
        return H264_ERR_BITSTREAM;
    }

    H264BitStream bs;
    bs_init(&bs, rbsp, rbsp_size);

    int ret = H264_OK;

    switch (nal_unit_type) {
    case H264_NAL_SPS: {
        H264SPS sps;
        ret = h264_parse_sps(&bs, &sps);
        if (ret == H264_OK && sps.seq_parameter_set_id < H264_MAX_SPS) {
            dec->sps[sps.seq_parameter_set_id] = sps;
        }
        break;
    }

    case H264_NAL_PPS: {
        H264PPS pps;
        ret = h264_parse_pps(&bs, &pps, dec->sps);
        if (ret == H264_OK && pps.pic_parameter_set_id < H264_MAX_PPS) {
            dec->pps[pps.pic_parameter_set_id] = pps;
        }
        break;
    }

    case H264_NAL_IDR_SLICE:
    case H264_NAL_SLICE: {
        H264SliceHeader sh;
        sh.is_idr = (nal_unit_type == H264_NAL_IDR_SLICE) ? 1 : 0;

        ret = h264_parse_slice_header(&bs, dec, &sh);
        if (ret != H264_OK) break;

        dec->current_sh = sh;

        H264SPS *sps = &dec->sps[dec->active_sps_id];
        ret = alloc_frame_buffers(dec, sps->width, sps->height);
        if (ret != H264_OK) break;

        ret = h264_decode_slice(dec, &bs, &sh);

        /* Output frame */
        if (frame) {
            frame->y        = dec->frame_y;
            frame->cb       = dec->frame_cb;
            frame->cr       = dec->frame_cr;
            frame->y_stride = dec->frame_stride;
            frame->c_stride = dec->frame_c_stride;
            frame->width    = dec->frame_width;
            frame->height   = dec->frame_height;
            frame->is_valid = 1;
        }

        /* Save as reference for next P-frame */
        if (nal_ref_idc != 0) {
            save_reference_frame(dec);
        }

        dec->frame_num++;
        break;
    }

    case H264_NAL_SEI:
    case H264_NAL_AUD:
    default:
        /* Silently ignore */
        break;
    }

    H264_FREE(rbsp);
    return ret;
}

/* ---- Stream decode (Annex B) ---- */

int h264_decode_stream(H264Decoder *dec, const uint8_t *data, int size,
                       H264Frame *frame)
{
    if (!dec || !data || size < 4) return H264_ERR_PARAM;

    if (frame) {
        frame->is_valid = 0;
        frame->y = frame->cb = frame->cr = NULL;
    }

    int pos = 0;
    int last_ret = H264_OK;

    while (pos < size) {
        int nal_start, nal_size;
        if (!h264_find_next_nal(data + pos, size - pos, &nal_start, &nal_size))
            break;

        if (nal_size > 0) {
            int ret = h264_decode_nal(dec, data + pos + nal_start, nal_size, frame);
            if (ret == H264_OK && frame && frame->is_valid) {
                /* Got a decoded frame - return it */
                pos += nal_start + nal_size;
                last_ret = H264_OK;
                /* Continue to find next NALs but keep frame */
            } else if (ret != H264_OK) {
                last_ret = ret;
            }
        }
        pos += nal_start + (nal_size > 0 ? nal_size : 1);
    }

    return last_ret;
}

/* ---- Frame free ---- */

void h264_frame_free(H264Frame *frame)
{
    /* Frames point into the decoder's internal buffers; don't free here.
     * This function is provided for API completeness - callers that allocate
     * their own frame copies can use it. */
    if (!frame) return;
    frame->is_valid = 0;
    frame->y = frame->cb = frame->cr = NULL;
}
