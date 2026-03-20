#ifndef H264_TABLES_H
#define H264_TABLES_H

#include <stdint.h>

/* CAVLC coeff_token table entry */
typedef struct {
    uint8_t TrailingOnes;
    uint8_t TotalCoeff;
    uint8_t len;
} CoeffToken;

/* VLC table entry */
typedef struct {
    int16_t value;
    uint8_t len;
} VLCEntry;

/* Zigzag scan for 4x4 blocks */
extern const uint8_t h264_zigzag_scan4[16];

/* Zigzag scan for chroma DC (2x2) */
extern const uint8_t h264_zigzag_scan_dc[4];

/* QP to quantization step size mapping (for dequantization) */
extern const int h264_qp_table[52];

/* Intra 4x4 prediction mode names */
extern const char * const h264_intra4x4_mode_names[9];

#endif /* H264_TABLES_H */
