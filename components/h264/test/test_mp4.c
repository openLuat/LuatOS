/*
 * test_mp4.c — minimal MP4 demuxer test.
 *
 * Steps:
 *   1. Build the 16×16 gray I-frame Annex-B stream and extract the SPS,
 *      PPS and IDR NAL units from it.
 *   2. Construct a minimal but fully conformant MP4 file in memory:
 *         [ftyp 20 B][mdat 8+N B][moov ...]
 *      The moov contains a single video trak with an avcC box (SPS+PPS),
 *      and sample tables pointing at the AVCC-formatted IDR frame in mdat.
 *   3. Write the MP4 to /tmp/test_h264.mp4.
 *   4. Open with h264_open_mp4(), read one frame, verify 16×16 / 128 grey,
 *      read again → H264_ERR_EOF, then close.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../include/h264_decoder.h"
#include "../src/h264_common.h"
#include "test_utils.h"
#include "test_stream.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); \
        return 1; \
    } \
} while(0)

#define MP4_PATH "/tmp/test_h264.mp4"

/* ================================================================
 * Minimal MP4 box builder helpers
 * ================================================================ */

static void pu8(uint8_t *b, int *p, uint8_t v)
{
    b[(*p)++] = v;
}

static void pu16(uint8_t *b, int *p, uint16_t v)
{
    b[(*p)++] = (v >> 8) & 0xFF;
    b[(*p)++] =  v       & 0xFF;
}

static void pu32(uint8_t *b, int *p, uint32_t v)
{
    b[(*p)++] = (v >> 24) & 0xFF;
    b[(*p)++] = (v >> 16) & 0xFF;
    b[(*p)++] = (v >>  8) & 0xFF;
    b[(*p)++] =  v        & 0xFF;
}

static void pzeros(uint8_t *b, int *p, int n)
{
    memset(b + *p, 0, (size_t)n);
    *p += n;
}

static void pbytes(uint8_t *b, int *p, const uint8_t *src, int n)
{
    memcpy(b + *p, src, (size_t)n);
    *p += n;
}

/* Begin a box: write placeholder size + type; return the position of size. */
static int begin_box(uint8_t *b, int *p, const char type[4])
{
    int sp = *p;
    pu32(b, p, 0);  /* placeholder */
    pu8(b, p, (uint8_t)type[0]);
    pu8(b, p, (uint8_t)type[1]);
    pu8(b, p, (uint8_t)type[2]);
    pu8(b, p, (uint8_t)type[3]);
    return sp;
}

/* Fill in the box size field at sp. */
static void end_box(uint8_t *b, int *p, int sp)
{
    uint32_t sz = (uint32_t)(*p - sp);
    b[sp]   = (sz >> 24) & 0xFF;
    b[sp+1] = (sz >> 16) & 0xFF;
    b[sp+2] = (sz >>  8) & 0xFF;
    b[sp+3] =  sz        & 0xFF;
}

/* Write FullBox version + flags after begin_box(). */
static void fullbox(uint8_t *b, int *p, uint8_t version, uint32_t flags)
{
    pu8(b,  p, version);
    pu8(b,  p, (flags >> 16) & 0xFF);
    pu8(b,  p, (flags >>  8) & 0xFF);
    pu8(b,  p,  flags        & 0xFF);
}

/* ISO 14496-12 unity matrix (9 × 4 bytes = 36 bytes) */
static void write_matrix(uint8_t *b, int *p)
{
    static const uint32_t mat[9] = {
        0x00010000, 0, 0,
        0, 0x00010000, 0,
        0, 0, 0x40000000
    };
    int i;
    for (i = 0; i < 9; i++) pu32(b, p, mat[i]);
}

/* ================================================================
 * build_test_mp4 — construct a minimal valid MP4 in *out.
 *
 * Layout:
 *   [ftyp 20 bytes]
 *   [mdat 8 + avcc_size bytes]      ← AVCC frame data starts at offset 28
 *   [moov …]
 *
 * AVCC format: [4-byte-BE-length][nal_data…]
 * ================================================================ */
static int build_test_mp4(uint8_t *out, int max_size, int *out_size,
                           const uint8_t *sps, int sps_len,
                           const uint8_t *pps, int pps_len,
                           const uint8_t *idr, int idr_len)
{
    int p = 0;
    int sp;

    /* avcc frame = 4-byte length prefix + IDR NAL */
    int avcc_size  = 4 + idr_len;

    /* The AVCC sample data starts immediately after the mdat box header.
     * ftyp = 20 bytes, mdat header = 8 bytes → chunk_offset = 28. */
    uint32_t chunk_offset = 20 + 8;
    uint32_t sample_size  = (uint32_t)avcc_size;

    /* ---- ftyp ---- */
    sp = begin_box(out, &p, "ftyp");
    pu8(out, &p, 'i'); pu8(out, &p, 's'); pu8(out, &p, 'o'); pu8(out, &p, 'm'); /* brand */
    pu32(out, &p, 0);  /* version */
    pu8(out, &p, 'i'); pu8(out, &p, 's'); pu8(out, &p, 'o'); pu8(out, &p, 'm'); /* compat */
    end_box(out, &p, sp);   /* size = 20 */

    /* ---- mdat ---- */
    sp = begin_box(out, &p, "mdat");
    /* AVCC frame: [4-byte BE length][idr_nal] */
    pu32(out, &p, (uint32_t)idr_len);
    pbytes(out, &p, idr, idr_len);
    end_box(out, &p, sp);

    /* ---- moov ---- */
    int sp_moov = begin_box(out, &p, "moov");

    /* mvhd (version=0, 112 bytes) */
    {
        int sp2 = begin_box(out, &p, "mvhd");
        fullbox(out, &p, 0, 0);
        pu32(out, &p, 0);       /* creation_time */
        pu32(out, &p, 0);       /* modification_time */
        pu32(out, &p, 90000);   /* timescale */
        pu32(out, &p, 3000);    /* duration (1 frame @ ~30fps) */
        pu32(out, &p, 0x00010000); /* rate = 1.0 */
        pu16(out, &p, 0x0100);  /* volume = 1.0 */
        pzeros(out, &p, 10);    /* reserved */
        write_matrix(out, &p);
        pzeros(out, &p, 24);    /* pre_defined[6] */
        pu32(out, &p, 2);       /* next_track_ID */
        end_box(out, &p, sp2);
    }

    /* trak */
    {
        int sp_trak = begin_box(out, &p, "trak");

        /* tkhd (version=0, 92 bytes) */
        {
            int sp2 = begin_box(out, &p, "tkhd");
            fullbox(out, &p, 0, 3); /* enabled | in-movie */
            pu32(out, &p, 0);       /* creation_time */
            pu32(out, &p, 0);       /* modification_time */
            pu32(out, &p, 1);       /* track_ID */
            pu32(out, &p, 0);       /* reserved */
            pu32(out, &p, 3000);    /* duration */
            pzeros(out, &p, 8);     /* reserved[2] */
            pu16(out, &p, 0);       /* layer */
            pu16(out, &p, 0);       /* alternate_group */
            pu16(out, &p, 0);       /* volume (video = 0) */
            pu16(out, &p, 0);       /* reserved */
            write_matrix(out, &p);
            pu32(out, &p, 16 << 16); /* width  (16.16 fixed) */
            pu32(out, &p, 16 << 16); /* height (16.16 fixed) */
            end_box(out, &p, sp2);
        }

        /* mdia */
        {
            int sp_mdia = begin_box(out, &p, "mdia");

            /* mdhd (32 bytes) */
            {
                int sp2 = begin_box(out, &p, "mdhd");
                fullbox(out, &p, 0, 0);
                pu32(out, &p, 0);       /* creation_time */
                pu32(out, &p, 0);       /* modification_time */
                pu32(out, &p, 90000);   /* timescale */
                pu32(out, &p, 3000);    /* duration */
                pu16(out, &p, 0x55C4);  /* language = 'und' */
                pu16(out, &p, 0);       /* pre_defined */
                end_box(out, &p, sp2);
            }

            /* hdlr */
            {
                int sp2 = begin_box(out, &p, "hdlr");
                fullbox(out, &p, 0, 0);
                pu32(out, &p, 0);       /* pre_defined */
                pu8(out, &p, 'v'); pu8(out, &p, 'i');
                pu8(out, &p, 'd'); pu8(out, &p, 'e'); /* handler_type */
                pzeros(out, &p, 12);    /* reserved[3] */
                pu8(out, &p, 0);        /* name (null-terminated empty string) */
                end_box(out, &p, sp2);
            }

            /* minf */
            {
                int sp_minf = begin_box(out, &p, "minf");

                /* vmhd */
                {
                    int sp2 = begin_box(out, &p, "vmhd");
                    fullbox(out, &p, 0, 1);
                    pu16(out, &p, 0); /* graphicsMode */
                    pzeros(out, &p, 6); /* opcolor */
                    end_box(out, &p, sp2);
                }

                /* dinf */
                {
                    int sp_dinf = begin_box(out, &p, "dinf");
                    /* dref */
                    {
                        int sp2 = begin_box(out, &p, "dref");
                        fullbox(out, &p, 0, 0);
                        pu32(out, &p, 1); /* entry_count */
                        /* url  entry (self-contained) */
                        {
                            int sp3 = begin_box(out, &p, "url ");
                            fullbox(out, &p, 0, 1); /* flags=1 → self-contained */
                            end_box(out, &p, sp3);
                        }
                        end_box(out, &p, sp2);
                    }
                    end_box(out, &p, sp_dinf);
                }

                /* stbl */
                {
                    int sp_stbl = begin_box(out, &p, "stbl");

                    /* stsd */
                    {
                        int sp2 = begin_box(out, &p, "stsd");
                        fullbox(out, &p, 0, 0);
                        pu32(out, &p, 1); /* entry_count */

                        /* avc1 */
                        {
                            int sp_avc1 = begin_box(out, &p, "avc1");
                            /* VisualSampleEntry fixed fields (78 bytes) */
                            pzeros(out, &p, 6);         /* reserved */
                            pu16(out, &p, 1);            /* data_reference_index */
                            pzeros(out, &p, 16);         /* reserved */
                            pu16(out, &p, 16);           /* width */
                            pu16(out, &p, 16);           /* height */
                            pu32(out, &p, 0x00480000);   /* horizResolution 72dpi */
                            pu32(out, &p, 0x00480000);   /* vertResolution 72dpi */
                            pu32(out, &p, 0);            /* reserved */
                            pu16(out, &p, 1);            /* frame_count */
                            pzeros(out, &p, 32);         /* compressorname */
                            pu16(out, &p, 0x0018);       /* depth */
                            pu16(out, &p, 0xFFFF);       /* pre_defined = -1 */

                            /* avcC */
                            {
                                int sp_avcc = begin_box(out, &p, "avcC");
                                pu8(out, &p, 1);            /* configurationVersion */
                                pu8(out, &p, sps[1]);       /* AVCProfileIndication */
                                pu8(out, &p, sps[2]);       /* profile_compatibility */
                                pu8(out, &p, sps[3]);       /* AVCLevelIndication */
                                pu8(out, &p, 0xFF);         /* 0xFC | (nal_length_size-1)=3 */
                                pu8(out, &p, 0xE1);         /* 0xE0 | numSPS=1 */
                                pu16(out, &p, (uint16_t)sps_len);
                                pbytes(out, &p, sps, sps_len);
                                pu8(out, &p, 1);            /* numPPS */
                                pu16(out, &p, (uint16_t)pps_len);
                                pbytes(out, &p, pps, pps_len);
                                end_box(out, &p, sp_avcc);
                            }

                            end_box(out, &p, sp_avc1);
                        }
                        end_box(out, &p, sp2);
                    } /* stsd */

                    /* stts: 1 entry (sample_count=1, sample_delta=3000) */
                    {
                        int sp2 = begin_box(out, &p, "stts");
                        fullbox(out, &p, 0, 0);
                        pu32(out, &p, 1);    /* entry_count */
                        pu32(out, &p, 1);    /* sample_count */
                        pu32(out, &p, 3000); /* sample_delta */
                        end_box(out, &p, sp2);
                    }

                    /* stsc: 1 entry (first_chunk=1, spc=1, desc=1) */
                    {
                        int sp2 = begin_box(out, &p, "stsc");
                        fullbox(out, &p, 0, 0);
                        pu32(out, &p, 1); /* entry_count */
                        pu32(out, &p, 1); /* first_chunk */
                        pu32(out, &p, 1); /* samples_per_chunk */
                        pu32(out, &p, 1); /* sample_description_index */
                        end_box(out, &p, sp2);
                    }

                    /* stsz: 1 sample */
                    {
                        int sp2 = begin_box(out, &p, "stsz");
                        fullbox(out, &p, 0, 0);
                        pu32(out, &p, 0);           /* sample_size (variable) */
                        pu32(out, &p, 1);           /* sample_count */
                        pu32(out, &p, sample_size); /* entry_size[0] */
                        end_box(out, &p, sp2);
                    }

                    /* stco: 1 chunk */
                    {
                        int sp2 = begin_box(out, &p, "stco");
                        fullbox(out, &p, 0, 0);
                        pu32(out, &p, 1);            /* entry_count */
                        pu32(out, &p, chunk_offset); /* chunk_offset[0] */
                        end_box(out, &p, sp2);
                    }

                    end_box(out, &p, sp_stbl);
                } /* stbl */

                end_box(out, &p, sp_minf);
            } /* minf */

            end_box(out, &p, sp_mdia);
        } /* mdia */

        end_box(out, &p, sp_trak);
    } /* trak */

    end_box(out, &p, sp_moov);

    if (p > max_size) return -1;
    *out_size = p;
    return 0;
}

/* ================================================================
 * Extract individual NAL units from an Annex-B stream.
 * ================================================================ */
static int extract_nals(const uint8_t *stream, int stream_size,
                        const uint8_t **sps_out, int *sps_len,
                        const uint8_t **pps_out, int *pps_len,
                        const uint8_t **idr_out, int *idr_len)
{
    int pos = 0, found = 0;
    while (pos < stream_size && found < 3) {
        int ns, nl;
        if (!h264_find_next_nal(stream + pos, stream_size - pos, &ns, &nl))
            break;
        /* NAL data starts at stream[pos + ns]; first byte is NAL header */
        if (nl < 1) { pos += ns + 1; continue; }
        uint8_t hdr = stream[pos + ns];
        int type = hdr & 0x1F;
        switch (type) {
        case 7: *sps_out = stream + pos + ns; *sps_len = nl; found++; break;
        case 8: *pps_out = stream + pos + ns; *pps_len = nl; found++; break;
        case 5: *idr_out = stream + pos + ns; *idr_len = nl; found++; break;
        default: break;
        }
        pos += ns + nl;
    }
    return (found == 3) ? 0 : -1;
}

/* ================================================================
 * test_mp4
 * ================================================================ */
int test_mp4(void)
{
    /* ---- 1. Build the reference Annex-B stream ---- */
    static uint8_t stream[8192];
    int stream_size = 0;
    int ret = build_16x16_gray_stream(stream, sizeof(stream), &stream_size);
    CHECK(ret == 0,         "mp4: stream build ok");
    CHECK(stream_size > 10, "mp4: stream non-empty");

    /* ---- 2. Extract SPS / PPS / IDR NAL units ---- */
    const uint8_t *sps = NULL, *pps = NULL, *idr = NULL;
    int sps_len = 0, pps_len = 0, idr_len = 0;
    ret = extract_nals(stream, stream_size,
                       &sps, &sps_len, &pps, &pps_len, &idr, &idr_len);
    CHECK(ret == 0,      "mp4: NAL extraction ok");
    CHECK(sps_len >= 4,  "mp4: SPS length reasonable");
    CHECK(pps_len >= 1,  "mp4: PPS length reasonable");
    CHECK(idr_len >= 4,  "mp4: IDR length reasonable");

    /* ---- 3. Build the MP4 in memory ---- */
    static uint8_t mp4_buf[65536];
    int mp4_size = 0;
    ret = build_test_mp4(mp4_buf, (int)sizeof(mp4_buf), &mp4_size,
                         sps, sps_len, pps, pps_len, idr, idr_len);
    CHECK(ret == 0,      "mp4: build_test_mp4 ok");
    CHECK(mp4_size > 64, "mp4: mp4 non-trivial size");

    /* ---- 4. Write to disk ---- */
    {
        FILE *fp = fopen(MP4_PATH, "wb");
        CHECK(fp != NULL, "mp4: fopen for write");
        size_t written = fwrite(mp4_buf, 1, (size_t)mp4_size, fp);
        fclose(fp);
        CHECK((int)written == mp4_size, "mp4: fwrite");
    }

    /* ---- 5. Open with MP4 decoder ---- */
    H264FileDecoder *fctx = h264_open_mp4(MP4_PATH);
    CHECK(fctx != NULL, "mp4: h264_open_mp4");

    /* ---- 6. Read first frame ---- */
    H264Frame frame;
    memset(&frame, 0, sizeof(frame));
    ret = h264_read_frame(fctx, &frame);
    CHECK(ret == H264_OK,     "mp4: first read_frame ok");
    CHECK(frame.is_valid,     "mp4: frame is_valid");
    CHECK(frame.width  == 16, "mp4: frame width 16");
    CHECK(frame.height == 16, "mp4: frame height 16");
    CHECK(frame.y  != NULL,   "mp4: luma plane not null");
    CHECK(frame.cb != NULL,   "mp4: Cb plane not null");
    CHECK(frame.cr != NULL,   "mp4: Cr plane not null");

    /* Verify pixel values */
    {
        int all_y = 1, all_c = 1, i, j;
        for (i = 0; i < 16; i++)
            for (j = 0; j < 16; j++)
                if (frame.y[i * frame.y_stride + j] != 128) all_y = 0;
        for (i = 0; i < 8; i++)
            for (j = 0; j < 8; j++) {
                if (frame.cb[i * frame.c_stride + j] != 128) all_c = 0;
                if (frame.cr[i * frame.c_stride + j] != 128) all_c = 0;
            }
        CHECK(all_y, "mp4: Y = 128");
        CHECK(all_c, "mp4: Cb/Cr = 128");
    }

    /* ---- 7. Second read must return EOF ---- */
    memset(&frame, 0, sizeof(frame));
    ret = h264_read_frame(fctx, &frame);
    CHECK(ret == H264_ERR_EOF, "mp4: second read_frame is EOF");

    /* ---- 8. Close ---- */
    h264_close_file(fctx);
    return 0;
}
