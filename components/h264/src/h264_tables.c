#include "h264_tables.h"

/* 4x4 zigzag scan order (linear index -> block position) */
const uint8_t h264_zigzag_scan4[16] = {
    0,  1,  4,  8,
    5,  2,  3,  6,
    9,  12, 13, 10,
    7,  11, 14, 15
};

/* 2x2 chroma DC zigzag */
const uint8_t h264_zigzag_scan_dc[4] = {0, 1, 2, 3};

/*
 * QP to dequantization step-size table.
 * Each entry is 16 * Qstep scaled so that the IDCT output lands correctly.
 * Values double every 6 QP steps per the H.264 spec.
 */
const int h264_qp_table[52] = {
    10,  11,  13,  14,  16,  18,
    20,  23,  25,  28,  32,  36,
    40,  45,  50,  57,  64,  72,
    80,  90, 101, 114, 128, 144,
   160, 180, 203, 228, 256, 288,
   320, 360, 405, 456, 512, 576,
   640, 720, 810, 912,1024,1152,
  1280,1440,1620,1824,2048,2304,
  2560,2880,3240,3648
};

const char * const h264_intra4x4_mode_names[9] = {
    "Vertical",        /* 0 */
    "Horizontal",      /* 1 */
    "DC",              /* 2 */
    "Diagonal_DL",     /* 3 */
    "Diagonal_DR",     /* 4 */
    "Vertical_R",      /* 5 */
    "Horizontal_D",    /* 6 */
    "Vertical_L",      /* 7 */
    "Horizontal_U"     /* 8 */
};
