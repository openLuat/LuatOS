/*
 * h264_mp4.c — minimal MP4 demuxer for H.264 video.
 *
 * Finds the first H.264 video track, extracts SPS/PPS from the avcC box,
 * and yields one decoded frame per h264_read_frame() call.
 *
 * Supported boxes: ftyp, moov/mvhd, trak, tkhd, mdia, hdlr, minf,
 *   stbl, stsd/avc1/avcC, stts, stsc, stsz, stco, co64.
 * All multi-byte integers are big-endian (ISO 14496-12).
 */

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "h264_common.h"
#include "h264_file.h"

/* Memory allocation macros */
#ifdef LUAT_HEAP_MALLOC
#include "luat_malloc.h"
#define H264_MALLOC  luat_heap_malloc
#define H264_FREE    luat_heap_free
#define H264_REALLOC luat_heap_realloc
#else
#define H264_MALLOC  malloc
#define H264_FREE    free
#define H264_REALLOC realloc
#endif

/* ---- Debug logging (g_h264_debug defined in h264_file.c) ---- */
#ifdef LUAT_BUILD
#define LUAT_LOG_TAG "h264"
#include "luat_log.h"
#define H264_DBGI(fmt, ...) do { if (g_h264_debug) { LLOGI(fmt, ##__VA_ARGS__); } } while(0)
#else
#define H264_DBGI(fmt, ...) do { if (g_h264_debug) { printf("[h264] " fmt "\n", ##__VA_ARGS__); } } while(0)
#endif

/* ---- Four-CC helper ---- */
#define FOURCC(a,b,c,d) \
    ((uint32_t)((uint8_t)(a))<<24 | (uint32_t)((uint8_t)(b))<<16 | \
     (uint32_t)((uint8_t)(c))<<8  | (uint32_t)((uint8_t)(d)))

/* ---- Big-endian read helpers ---- */

static uint16_t read_u16_be(FILE *fp)
{
    uint8_t b[2];
    if (fread(b, 1, 2, fp) != 2) return 0;
    return (uint16_t)((b[0] << 8) | b[1]);
}

static uint32_t read_u32_be(FILE *fp)
{
    uint8_t b[4];
    if (fread(b, 1, 4, fp) != 4) return 0;
    return ((uint32_t)b[0]<<24)|((uint32_t)b[1]<<16)|
           ((uint32_t)b[2]<<8 )| (uint32_t)b[3];
}

static uint64_t read_u64_be(FILE *fp)
{
    uint64_t hi = read_u32_be(fp);
    uint64_t lo = read_u32_be(fp);
    return (hi << 32) | lo;
}

/* ---- stsc entry ---- */
typedef struct {
    uint32_t first_chunk;
    uint32_t samples_per_chunk;
    uint32_t sample_desc;
} StscEntry;
/* ---- MP4 context ---- */
typedef struct {
    /* From avcC */
    uint8_t  *sps_data[32];
    int       sps_len[32];
    int       sps_count;
    uint8_t  *pps_data[32];
    int       pps_len[32];
    int       pps_count;
    int       nal_length_size; /* from lengthSizeMinusOne+1 */

    /* From stsz */
    uint32_t *sample_sizes;
    int       sample_count;

    /* From stco / co64 */
    uint64_t *chunk_offsets;
    int       chunk_count;

    /* From stsc */
    StscEntry *stsc_entries;
    int        stsc_count;

    /* Decode state */
    int       current_sample;
    int       params_sent;  /* whether SPS/PPS were fed to decoder */

    FILE     *fp;           /* alias of fctx->fp (not owned here) */
} H264Mp4Context;

/* ---- Box header ---- */
typedef struct {
    uint32_t type;
    long     payload_start; /* file pos after header */
    long     box_end;       /* file pos at end of box */
} BoxInfo;

/* Forward declaration: defined after mp4_cleanup */
static void mp4_free_ctx_resources(H264Mp4Context *ctx);

/* Read one box header.  Positions fp at start of payload.
 * Returns 0 on success, -1 on error / EOF. */
static int next_box(FILE *fp, BoxInfo *bi)
{
    long pos = ftell(fp);
    if (pos < 0) return -1;

    uint32_t size32 = read_u32_be(fp);
    if (feof(fp) || ferror(fp)) return -1;
    bi->type = read_u32_be(fp);
    if (feof(fp) || ferror(fp)) return -1;

    if (size32 == 1) {
        /* Extended 64-bit size */
        uint64_t size64 = read_u64_be(fp);
        bi->payload_start = pos + 16;
        bi->box_end       = (long)((uint64_t)pos + size64);
    } else if (size32 == 0) {
        /* Box extends to EOF */
        long save = ftell(fp);
        fseek(fp, 0, SEEK_END);
        bi->box_end = ftell(fp);
        fseek(fp, save, SEEK_SET);
        bi->payload_start = pos + 8;
    } else {
        if (size32 < 8) return -1; /* malformed */
        bi->payload_start = pos + 8;
        bi->box_end       = pos + (long)size32;
    }
    return 0;
}

/* ---- Allocate a buffer and read exactly 'len' bytes from fp.
 * Returns the buffer (caller must H264_FREE it), or NULL on error. ---- */
static uint8_t *read_alloc(FILE *fp, uint16_t len)
{
    if (len == 0) return NULL;
    uint8_t *buf = (uint8_t *)H264_MALLOC(len);
    if (!buf) return NULL;
    if ((int)fread(buf, 1, len, fp) != len) { H264_FREE(buf); return NULL; }
    return buf;
}

/* ---- avcC parser ---- */
static int parse_avcc(FILE *fp, H264Mp4Context *ctx, long box_end)
{
    (void)box_end;
    uint8_t cfg_ver = (uint8_t)fgetc(fp);
    if (cfg_ver != 1) return -1;
    fgetc(fp); /* AVCProfileIndication */
    fgetc(fp); /* profile_compatibility */
    fgetc(fp); /* AVCLevelIndication */

    uint8_t len_byte = (uint8_t)fgetc(fp);
    ctx->nal_length_size = (len_byte & 0x03) + 1;

    uint8_t num_sps = (uint8_t)fgetc(fp) & 0x1F;
    int i;
    for (i = 0; i < (int)num_sps && i < 32; i++) {
        uint16_t slen = read_u16_be(fp);
        uint8_t *buf = read_alloc(fp, slen);
        if (!buf) return -1;
        ctx->sps_data[i] = buf;
        ctx->sps_len[i]  = slen;
        ctx->sps_count++;
    }

    uint8_t num_pps = (uint8_t)fgetc(fp);
    for (i = 0; i < (int)num_pps && i < 32; i++) {
        uint16_t plen = read_u16_be(fp);
        uint8_t *buf = read_alloc(fp, plen);
        if (!buf) return -1;
        ctx->pps_data[i] = buf;
        ctx->pps_len[i]  = plen;
        ctx->pps_count++;
    }
    H264_DBGI("avcC: nal_length_size=%d sps_count=%d pps_count=%d",
              ctx->nal_length_size, ctx->sps_count, ctx->pps_count);
    return 0;
}

/* ---- avc1 → avcC scanner ---- */
static void parse_avc1(FILE *fp, H264Mp4Context *ctx,
                       long payload_start, long box_end)
{
    /* Skip 78 bytes of fixed VisualSampleEntry fields */
    fseek(fp, payload_start + 78, SEEK_SET);

    while (ftell(fp) + 8 <= box_end) {
        BoxInfo sub;
        if (next_box(fp, &sub) != 0) break;
        if (sub.type == FOURCC('a','v','c','C'))
            parse_avcc(fp, ctx, sub.box_end);
        fseek(fp, sub.box_end, SEEK_SET);
    }
}

/* ---- stsd ---- */
static void parse_stsd(FILE *fp, H264Mp4Context *ctx,
                       long payload_start, long box_end)
{
    /* FullBox: skip version(1)+flags(3)+entry_count(4) = 8 bytes */
    fseek(fp, payload_start + 8, SEEK_SET);

    while (ftell(fp) + 8 <= box_end) {
        BoxInfo entry;
        if (next_box(fp, &entry) != 0) break;
        if (entry.type == FOURCC('a','v','c','1'))
            parse_avc1(fp, ctx, entry.payload_start, entry.box_end);
        fseek(fp, entry.box_end, SEEK_SET);
    }
}

/* ---- stsc ---- */
static void parse_stsc(FILE *fp, H264Mp4Context *ctx, long payload_start)
{
    fseek(fp, payload_start + 4, SEEK_SET); /* skip version+flags */
    uint32_t count = read_u32_be(fp);
    if (count == 0) return;

    ctx->stsc_entries = (StscEntry *)H264_MALLOC(count * sizeof(StscEntry));
    if (!ctx->stsc_entries) return;
    ctx->stsc_count = (int)count;

    uint32_t i;
    for (i = 0; i < count; i++) {
        ctx->stsc_entries[i].first_chunk        = read_u32_be(fp);
        ctx->stsc_entries[i].samples_per_chunk  = read_u32_be(fp);
        ctx->stsc_entries[i].sample_desc        = read_u32_be(fp);
    }
}

/* ---- stsz ---- */
static void parse_stsz(FILE *fp, H264Mp4Context *ctx, long payload_start)
{
    fseek(fp, payload_start + 4, SEEK_SET); /* skip version+flags */
    uint32_t fixed_size  = read_u32_be(fp);
    uint32_t count       = read_u32_be(fp);
    if (count == 0) return;

    ctx->sample_sizes = (uint32_t *)H264_MALLOC(count * sizeof(uint32_t));
    if (!ctx->sample_sizes) return;
    ctx->sample_count = (int)count;

    uint32_t i;
    if (fixed_size != 0) {
        for (i = 0; i < count; i++) ctx->sample_sizes[i] = fixed_size;
    } else {
        for (i = 0; i < count; i++) ctx->sample_sizes[i] = read_u32_be(fp);
    }
}

/* ---- stco ---- */
static void parse_stco(FILE *fp, H264Mp4Context *ctx, long payload_start)
{
    fseek(fp, payload_start + 4, SEEK_SET);
    uint32_t count = read_u32_be(fp);
    if (count == 0) return;

    ctx->chunk_offsets = (uint64_t *)H264_MALLOC(count * sizeof(uint64_t));
    if (!ctx->chunk_offsets) return;
    ctx->chunk_count = (int)count;

    uint32_t i;
    for (i = 0; i < count; i++)
        ctx->chunk_offsets[i] = (uint64_t)read_u32_be(fp);
}

/* ---- co64 ---- */
static void parse_co64(FILE *fp, H264Mp4Context *ctx, long payload_start)
{
    fseek(fp, payload_start + 4, SEEK_SET);
    uint32_t count = read_u32_be(fp);
    if (count == 0) return;

    ctx->chunk_offsets = (uint64_t *)H264_MALLOC(count * sizeof(uint64_t));
    if (!ctx->chunk_offsets) return;
    ctx->chunk_count = (int)count;

    uint32_t i;
    for (i = 0; i < count; i++)
        ctx->chunk_offsets[i] = read_u64_be(fp);
}

/* ---- stbl container ---- */
static void parse_stbl(FILE *fp, H264Mp4Context *ctx,
                       long payload_start, long box_end)
{
    fseek(fp, payload_start, SEEK_SET);
    while (ftell(fp) + 8 <= box_end) {
        BoxInfo bi;
        if (next_box(fp, &bi) != 0) break;
        switch (bi.type) {
        case FOURCC('s','t','s','d'): parse_stsd(fp, ctx, bi.payload_start, bi.box_end); break;
        case FOURCC('s','t','s','c'): parse_stsc(fp, ctx, bi.payload_start); break;
        case FOURCC('s','t','s','z'): parse_stsz(fp, ctx, bi.payload_start); break;
        case FOURCC('s','t','c','o'): parse_stco(fp, ctx, bi.payload_start); break;
        case FOURCC('c','o','6','4'): parse_co64(fp, ctx, bi.payload_start); break;
        default: break;
        }
        fseek(fp, bi.box_end, SEEK_SET);
    }
}

/* ---- minf container ---- */
static void parse_minf(FILE *fp, H264Mp4Context *ctx,
                       long payload_start, long box_end)
{
    fseek(fp, payload_start, SEEK_SET);
    while (ftell(fp) + 8 <= box_end) {
        BoxInfo bi;
        if (next_box(fp, &bi) != 0) break;
        if (bi.type == FOURCC('s','t','b','l'))
            parse_stbl(fp, ctx, bi.payload_start, bi.box_end);
        fseek(fp, bi.box_end, SEEK_SET);
    }
}

/* ---- mdia container — returns 1 if this is a video track ---- */
static int parse_mdia(FILE *fp, H264Mp4Context *ctx,
                      long payload_start, long box_end)
{
    int is_video = 0;
    fseek(fp, payload_start, SEEK_SET);
    while (ftell(fp) + 8 <= box_end) {
        BoxInfo bi;
        if (next_box(fp, &bi) != 0) break;

        if (bi.type == FOURCC('h','d','l','r')) {
            /* FullBox: skip version(1)+flags(3)+pre_defined(4) = 8 bytes */
            fseek(fp, bi.payload_start + 8, SEEK_SET);
            uint32_t handler = read_u32_be(fp);
            if (handler == FOURCC('v','i','d','e'))
                is_video = 1;
        } else if (bi.type == FOURCC('m','i','n','f') && is_video) {
            parse_minf(fp, ctx, bi.payload_start, bi.box_end);
        }
        fseek(fp, bi.box_end, SEEK_SET);
    }
    return is_video;
}

/* ---- trak container ---- */
static void parse_trak(FILE *fp, H264Mp4Context *ctx,
                       long payload_start, long box_end)
{
    /* We first need to check hdlr (inside mdia) before committing to parse
     * the full stbl.  parse_mdia handles both in one pass. */
    H264Mp4Context tmp;
    memset(&tmp, 0, sizeof(tmp));
    tmp.fp              = ctx->fp;
    tmp.nal_length_size = 4; /* default */

    fseek(fp, payload_start, SEEK_SET);
    while (ftell(fp) + 8 <= box_end) {
        BoxInfo bi;
        if (next_box(fp, &bi) != 0) break;
        if (bi.type == FOURCC('m','d','i','a')) {
            if (parse_mdia(fp, &tmp, bi.payload_start, bi.box_end)) {
                /* Video track found — steal parsed tables into ctx */
                /* Free any existing tables from a previous (non-video) trak */
                mp4_free_ctx_resources(ctx);
                memcpy(ctx, &tmp, sizeof(tmp));
                memset(&tmp, 0, sizeof(tmp)); /* tmp no longer owns anything */
                fseek(fp, bi.box_end, SEEK_SET);
                break; /* use first video trak */
            }
        }
        fseek(fp, bi.box_end, SEEK_SET);
    }

    /* Free any resources left in tmp (non-video trak) */
    mp4_free_ctx_resources(&tmp);
}

/* ---- moov container ---- */
static void parse_moov(FILE *fp, H264Mp4Context *ctx,
                       long payload_start, long box_end)
{
    fseek(fp, payload_start, SEEK_SET);
    while (ftell(fp) + 8 <= box_end) {
        BoxInfo bi;
        if (next_box(fp, &bi) != 0) break;
        if (bi.type == FOURCC('t','r','a','k'))
            parse_trak(fp, ctx, bi.payload_start, bi.box_end);
        fseek(fp, bi.box_end, SEEK_SET);
    }
}

/* ---- Compute file offset + size of sample[sample_idx] ---- */
/*
 * Compute the file byte offset and byte size of sample[sample_idx].
 *
 * The MP4 sample-to-chunk table (stsc) maps ranges of chunks to a fixed
 * number of samples per chunk.  For each stsc entry we compute how many
 * samples fall into the covered chunk range, then locate the chunk that
 * contains sample_idx and add up the sizes of all earlier samples within
 * that chunk to get the final byte offset inside it.
 */
static int get_sample_info(H264Mp4Context *ctx, int sample_idx,
                           uint64_t *offset_out, uint32_t *size_out)
{
    if (sample_idx < 0 || sample_idx >= ctx->sample_count) return -1;
    *size_out = ctx->sample_sizes[sample_idx];

    /* Walk stsc to find which chunk this sample belongs to */
    int chunk_idx  = -1;
    int sic        = 0;   /* sample-in-chunk index */
    int gfic       = 0;   /* global index of first sample in that chunk */
    int cum        = 0;   /* cumulative sample count before current stsc range */

    int i;
    for (i = 0; i < ctx->stsc_count; i++) {
        uint32_t fc  = ctx->stsc_entries[i].first_chunk;
        uint32_t spc = ctx->stsc_entries[i].samples_per_chunk;
        uint32_t end_fc;

        if (i + 1 < ctx->stsc_count)
            end_fc = ctx->stsc_entries[i + 1].first_chunk;
        else
            end_fc = (uint32_t)(ctx->chunk_count) + 1;

        uint32_t num_chunks = end_fc - fc;
        uint32_t in_range   = num_chunks * spc;

        if ((uint32_t)(sample_idx - cum) < in_range) {
            uint32_t rel   = (uint32_t)(sample_idx - cum);
            uint32_t ci    = rel / spc;       /* chunk within range */
            chunk_idx      = (int)(fc - 1 + ci);
            sic            = (int)(rel % spc);
            gfic           = cum + (int)(ci * spc);
            break;
        }
        cum += (int)in_range;
    }

    if (chunk_idx < 0 || chunk_idx >= ctx->chunk_count) return -1;

    uint64_t off = ctx->chunk_offsets[chunk_idx];
    int j;
    for (j = gfic; j < gfic + sic; j++) {
        if (j >= ctx->sample_count) return -1;
        off += ctx->sample_sizes[j];
    }
    *offset_out = off;
    return 0;
}

/* ---- mp4 read_next implementation ---- */
static int mp4_read_next(H264FileDecoder *fctx, H264Frame *frame)
{
    H264Mp4Context *ctx = (H264Mp4Context *)fctx->mp4_ctx;

    /* Feed SPS/PPS to decoder on first call */
    if (!ctx->params_sent) {
        H264Frame dummy;
        memset(&dummy, 0, sizeof(dummy));
        int i;
        for (i = 0; i < ctx->sps_count; i++)
            h264_decode_nal(fctx->dec, ctx->sps_data[i], ctx->sps_len[i], &dummy);
        for (i = 0; i < ctx->pps_count; i++)
            h264_decode_nal(fctx->dec, ctx->pps_data[i], ctx->pps_len[i], &dummy);
        ctx->params_sent = 1;
        /* Debug: print video resolution from the first valid SPS */
        if (g_h264_debug) {
            int s;
            for (s = 0; s < H264_MAX_SPS; s++) {
                if (fctx->dec->sps[s].is_valid) {
                    H264_DBGI("MP4 video: %dx%d, total_samples=%d",
                              fctx->dec->sps[s].width,
                              fctx->dec->sps[s].height,
                              ctx->sample_count);
                    break;
                }
            }
        }
    }

    /* Iterate samples until we decode a frame or run out */
    while (ctx->current_sample < ctx->sample_count) {
        int sidx = ctx->current_sample;
        uint64_t offset;
        uint32_t sz;

        if (get_sample_info(ctx, sidx, &offset, &sz) != 0) {
            ctx->current_sample++;
            continue;
        }

        uint8_t *sbuf = (uint8_t *)H264_MALLOC(sz);
        if (!sbuf) return H264_ERR_NOMEM;

        fseek(fctx->fp, (long)offset, SEEK_SET);
        if (fread(sbuf, 1, sz, fctx->fp) != sz) {
            H264_FREE(sbuf);
            ctx->current_sample++;
            continue;
        }

        /* Parse AVCC NALs: [nal_length_size bytes BE length][NAL data] */
        uint32_t pos = 0;
        int got_frame = 0;
        int ret = H264_OK;

        while (pos + (uint32_t)ctx->nal_length_size <= sz) {
            uint32_t nal_len = 0;
            int k;
            for (k = 0; k < ctx->nal_length_size; k++)
                nal_len = (nal_len << 8) | sbuf[pos + k];
            pos += (uint32_t)ctx->nal_length_size;

            if (nal_len == 0 || pos + nal_len > sz) break;

            H264Frame f;
            memset(&f, 0, sizeof(f));
            ret = h264_decode_nal(fctx->dec, sbuf + pos, (int)nal_len, &f);
            pos += nal_len;

            if (ret == H264_OK && f.is_valid) {
                *frame = f;
                got_frame = 1;
            }
        }

        H264_FREE(sbuf);
        ctx->current_sample++;

        if (got_frame) {
            fctx->frame_count++;
            H264_DBGI("MP4 frame #%d: sample=%d %dx%d",
                      fctx->frame_count, sidx, frame->width, frame->height);
            return H264_OK;
        }
        if (ret != H264_OK) return ret;
    }

    return H264_ERR_EOF;
}

/* ---- mp4 context resource freer (used by mp4_cleanup and mp4_open_fail) ---- */
static void mp4_free_ctx_resources(H264Mp4Context *ctx)
{
    int i;
    for (i = 0; i < ctx->sps_count; i++) if (ctx->sps_data[i]) H264_FREE(ctx->sps_data[i]);
    for (i = 0; i < ctx->pps_count; i++) if (ctx->pps_data[i]) H264_FREE(ctx->pps_data[i]);
    if (ctx->sample_sizes)  H264_FREE(ctx->sample_sizes);
    if (ctx->chunk_offsets) H264_FREE(ctx->chunk_offsets);
    if (ctx->stsc_entries)  H264_FREE(ctx->stsc_entries);
}

/* ---- mp4 cleanup ---- */
static void mp4_cleanup(H264FileDecoder *fctx)
{
    H264Mp4Context *ctx = (H264Mp4Context *)fctx->mp4_ctx;
    if (!ctx) return;
    mp4_free_ctx_resources(ctx);
    H264_FREE(ctx);
    fctx->mp4_ctx = NULL;
}

/* ---- Cleanup helper for failed h264_open_mp4() paths ---- */

static H264FileDecoder *mp4_open_fail(H264FileDecoder *fctx, H264Mp4Context *ctx)
{
    if (ctx) {
        mp4_free_ctx_resources(ctx);
        H264_FREE(ctx);
    }
    if (fctx) {
        if (fctx->fp) { fclose(fctx->fp); fctx->fp = NULL; }
        h264_decoder_destroy(fctx->dec);
        H264_FREE(fctx);
    }
    return NULL;
}

/* ---- Public entry point ---- */

H264FileDecoder *h264_open_mp4(const char *path)
{
    if (!path) return NULL;

    H264FileDecoder *fctx = h264_file_decoder_alloc();
    if (!fctx) return NULL;

    fctx->fp = fopen(path, "rb");
    if (!fctx->fp)
        return mp4_open_fail(fctx, NULL);

    H264Mp4Context *ctx = (H264Mp4Context *)H264_MALLOC(sizeof(H264Mp4Context));
    if (!ctx)
        return mp4_open_fail(fctx, NULL);
    memset(ctx, 0, sizeof(*ctx));
    ctx->fp             = fctx->fp;
    ctx->nal_length_size = 4; /* default; overridden by avcC */

    /* Walk top-level boxes to find moov */
    int found_moov = 0;
    while (!feof(fctx->fp)) {
        BoxInfo bi;
        if (next_box(fctx->fp, &bi) != 0) break;
        if (bi.type == FOURCC('m','o','o','v')) {
            parse_moov(fctx->fp, ctx, bi.payload_start, bi.box_end);
            found_moov = 1;
        }
        fseek(fctx->fp, bi.box_end, SEEK_SET);
    }

    /* Validate: need at least one sample and a chunk-offset table */
    if (!found_moov || ctx->sample_count == 0 || !ctx->chunk_offsets ||
        !ctx->sample_sizes || !ctx->stsc_entries || ctx->sps_count == 0) {
        return mp4_open_fail(fctx, ctx);
    }

    fctx->mp4_ctx   = ctx;
    fctx->type      = 1;
    fctx->read_next = mp4_read_next;
    fctx->cleanup   = mp4_cleanup;
    H264_DBGI("opened MP4: %s, samples=%d chunks=%d sps_count=%d",
              path, ctx->sample_count, ctx->chunk_count, ctx->sps_count);
    return fctx;
}
