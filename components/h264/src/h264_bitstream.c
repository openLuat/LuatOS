#include <string.h>
#include <stdlib.h>
#include "h264_bitstream.h"

/*
 * Remove emulation prevention bytes from a NALU payload.
 * The sequence 00 00 03 xx  becomes  00 00 xx  (the 03 is dropped).
 *
 * Returns the number of bytes written to rbsp_data, or -1 on error.
 */
int h264_nalu_to_rbsp(const uint8_t *nalu_data, int nalu_size,
                      uint8_t *rbsp_data, int rbsp_size)
{
    int i   = 0;
    int out = 0;

    while (i < nalu_size) {
        if (i + 2 < nalu_size &&
            nalu_data[i]   == 0x00 &&
            nalu_data[i+1] == 0x00 &&
            nalu_data[i+2] == 0x03)
        {
            /* copy two zero bytes, skip the emulation prevention 0x03 */
            if (out + 2 > rbsp_size) return -1;
            rbsp_data[out++] = 0x00;
            rbsp_data[out++] = 0x00;
            i += 3;
        } else {
            if (out >= rbsp_size) return -1;
            rbsp_data[out++] = nalu_data[i++];
        }
    }
    return out;
}

/*
 * Add emulation prevention bytes so that 00 00 01 or 00 00 02 or 00 00 03
 * never appear in the NALU payload.
 *
 * Returns the number of bytes written, or -1 on error.
 */
int h264_rbsp_to_nalu(const uint8_t *rbsp_data, int rbsp_size,
                      uint8_t *nalu_data, int nalu_size)
{
    int i   = 0;
    int out = 0;
    int zero_count = 0;

    while (i < rbsp_size) {
        uint8_t b = rbsp_data[i];
        if (zero_count >= 2 && b <= 0x03) {
            /* insert emulation prevention byte */
            if (out >= nalu_size) return -1;
            nalu_data[out++] = 0x03;
            zero_count = 0;
        }
        if (out >= nalu_size) return -1;
        nalu_data[out++] = b;
        zero_count = (b == 0x00) ? zero_count + 1 : 0;
        i++;
    }
    return out;
}
