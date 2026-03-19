#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include "h264_common.h"
#include "../include/h264_decoder.h"

/* Alpha and beta threshold tables (H.264 spec Table 8-16, 8-17) */
static const int alpha_table[52] = {
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  4,  4,  5,  6,  7,  8,  9, 10, 12, 13,
   15, 17, 20, 22, 25, 28, 32, 36, 40, 45, 50, 56, 63, 71,
   80, 90,101,113,127,144,162,182,203,226,255,255
};

static const int beta_table[52] = {
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  2,  2,  2,  3,  3,  3,  3,  4,  4,  4,
    6,  6,  7,  7,  8,  8,  9,  9, 10, 10, 11, 11, 12, 12,
   13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18
};

/* tc0 table (H.264 spec Table 8-16) indexed by [indexA][bS-1] */
static const int tc0_table[52][3] = {
    {0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},
    {0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},
    {0,0,0},{0,0,1},{0,0,1},{0,0,1},{0,0,1},{0,1,1},{0,1,1},{1,1,1},
    {1,1,1},{1,1,1},{1,1,1},{1,1,2},{1,1,2},{1,1,2},{1,1,2},{1,2,3},
    {1,2,3},{2,2,3},{2,2,4},{2,3,4},{2,3,4},{3,3,5},{3,4,6},{3,4,6},
    {4,5,7},{4,5,8},{4,6,9},{4,6,9},{5,7,10},{6,8,11},{6,8,13},{7,10,14},
    {8,11,16},{9,12,18},{10,13,20},{11,15,23}
};

static inline int clip3(int lo, int hi, int v) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static void filter_luma_edge(uint8_t *p, int stride, int bS, int qp,
                              int vertical)
{
    if (bS == 0) return;

    int indexA = clip3(0, 51, qp);
    int alpha   = alpha_table[indexA];
    int beta    = beta_table[indexA];
    int i;

    for (i = 0; i < 4; i++) {
        uint8_t *q0 = vertical ? (p + i)        : (p + i*stride);
        /* p samples: ..., p2, p1, p0 | q0, q1, q2, ... */
        uint8_t *P0 = q0 - (vertical ? stride : 1);
        uint8_t *P1 = P0 - (vertical ? stride : 1);
        uint8_t *P2 = P1 - (vertical ? stride : 1);
        uint8_t *Q0 = q0;
        uint8_t *Q1 = q0 + (vertical ? stride : 1);
        uint8_t *Q2 = Q1 + (vertical ? stride : 1);

        int p0v = *P0, p1v = *P1, p2v = *P2;
        int q0v = *Q0, q1v = *Q1, q2v = *Q2;

        if (abs(p0v - q0v) >= alpha) continue;
        if (abs(p1v - p0v) >= beta)  continue;
        if (abs(q1v - q0v) >= beta)  continue;

        if (bS == 4) {
            /* Strong filter */
            int ap = abs(p2v - p0v);
            int aq = abs(q2v - q0v);
            if (ap < beta && abs(p0v - q0v) < ((alpha >> 2) + 2)) {
                *P0 = (uint8_t)((p2v + 2*p1v + 2*p0v + 2*q0v + q1v + 4) >> 3);
                *P1 = (uint8_t)((p2v + p1v + p0v + q0v + 2) >> 2);
            } else {
                *P0 = (uint8_t)((2*p1v + p0v + q1v + 2) >> 2);
            }
            if (aq < beta && abs(p0v - q0v) < ((alpha >> 2) + 2)) {
                *Q0 = (uint8_t)((p1v + 2*p0v + 2*q0v + 2*q1v + q2v + 4) >> 3);
                *Q1 = (uint8_t)((p0v + q0v + q1v + q2v + 2) >> 2);
            } else {
                *Q0 = (uint8_t)((2*q1v + q0v + p1v + 2) >> 2);
            }
        } else {
            /* Normal filter */
            int tc0 = tc0_table[indexA][bS - 1];
            int tc  = tc0;
            int ap  = abs(p2v - p0v);
            int aq  = abs(q2v - q0v);
            int delta;

            if (ap < beta) { tc++; }
            if (aq < beta) { tc++; }

            delta = clip3(-tc, tc,
                          ((q0v - p0v)*4 + (p1v - q1v) + 4) >> 3);
            *P0 = (uint8_t)clip3(0, 255, p0v + delta);
            *Q0 = (uint8_t)clip3(0, 255, q0v - delta);

            if (ap < beta) {
                *P1 = (uint8_t)clip3(0, 255,
                    p1v + clip3(-tc0, tc0, (p2v + ((p0v + q0v + 1) >> 1) - 2*p1v) >> 1));
            }
            if (aq < beta) {
                *Q1 = (uint8_t)clip3(0, 255,
                    q1v + clip3(-tc0, tc0, (q2v + ((p0v + q0v + 1) >> 1) - 2*q1v) >> 1));
            }
        }
    }
}

static void filter_chroma_edge(uint8_t *p, int stride, int bS, int qp,
                                int vertical)
{
    if (bS < 2) return;

    int indexA = clip3(0, 51, qp);
    int alpha   = alpha_table[indexA];
    int beta    = beta_table[indexA];
    int i;

    for (i = 0; i < 2; i++) {
        uint8_t *q0 = vertical ? (p + i)     : (p + i*stride);
        uint8_t *P0 = q0 - (vertical ? stride : 1);
        uint8_t *P1 = P0 - (vertical ? stride : 1);
        uint8_t *Q0 = q0;
        uint8_t *Q1 = q0 + (vertical ? stride : 1);

        int p0v = *P0, p1v = *P1;
        int q0v = *Q0, q1v = *Q1;

        if (abs(p0v - q0v) >= alpha) continue;
        if (abs(p1v - p0v) >= beta)  continue;
        if (abs(q1v - q0v) >= beta)  continue;

        if (bS == 4) {
            *P0 = (uint8_t)((2*p1v + p0v + q1v + 2) >> 2);
            *Q0 = (uint8_t)((2*q1v + q0v + p1v + 2) >> 2);
        } else {
            int tc = tc0_table[indexA][bS-1] + 1;
            int delta = clip3(-tc, tc,
                              ((q0v - p0v)*4 + (p1v - q1v) + 4) >> 3);
            *P0 = (uint8_t)clip3(0, 255, p0v + delta);
            *Q0 = (uint8_t)clip3(0, 255, q0v - delta);
        }
    }
}

/*
 * Apply deblocking filter to the whole frame.
 * This is a simplified version that filters all MB boundaries with bS=4
 * (all intra frame assumption) and all internal edges at bS=3.
 */
void h264_deblock_frame(H264Decoder *dec, H264Frame *frame)
{
    if (!frame || !frame->is_valid) return;

    int mb_w = (frame->width  + 15) / 16;
    int mb_h = (frame->height + 15) / 16;
    int mb_x, mb_y;

    for (mb_y = 0; mb_y < mb_h; mb_y++) {
        for (mb_x = 0; mb_x < mb_w; mb_x++) {
            int x0 = mb_x * 16;
            int y0 = mb_y * 16;
            int cx = mb_x * 8;
            int cy = mb_y * 8;

            /* Luma vertical edges at left MB boundary */
            if (mb_x > 0) {
                uint8_t *p = frame->y + y0 * frame->y_stride + x0;
                filter_luma_edge(p, frame->y_stride, 4, 28, 0);
            }

            /* Luma horizontal edges at top MB boundary */
            if (mb_y > 0) {
                uint8_t *p = frame->y + y0 * frame->y_stride + x0;
                filter_luma_edge(p, frame->y_stride, 4, 28, 1);
            }

            /* Chroma vertical edges */
            if (mb_x > 0) {
                uint8_t *pc = frame->cb + cy * frame->c_stride + cx;
                filter_chroma_edge(pc, frame->c_stride, 4, 28, 0);
                pc = frame->cr + cy * frame->c_stride + cx;
                filter_chroma_edge(pc, frame->c_stride, 4, 28, 0);
            }

            /* Chroma horizontal edges */
            if (mb_y > 0) {
                uint8_t *pc = frame->cb + cy * frame->c_stride + cx;
                filter_chroma_edge(pc, frame->c_stride, 4, 28, 1);
                pc = frame->cr + cy * frame->c_stride + cx;
                filter_chroma_edge(pc, frame->c_stride, 4, 28, 1);
            }
        }
    }
    (void)dec;
}
