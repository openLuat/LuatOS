#include <string.h>
#include <stdlib.h>
#include "h264_common.h"

/* Forward declaration for emulation-prevention removal */
int h264_nalu_to_rbsp(const uint8_t *nalu_data, int nalu_size,
                      uint8_t *rbsp_data, int rbsp_size);

/*
 * Parse NAL header byte.
 * Returns 0 on success, negative on error.
 */
int h264_parse_nal_header(uint8_t byte, int *nal_unit_type, int *nal_ref_idc)
{
    if (byte & 0x80) return H264_ERR_BITSTREAM; /* forbidden_zero_bit must be 0 */
    *nal_ref_idc   = (byte >> 5) & 0x03;
    *nal_unit_type = byte & 0x1F;
    return H264_OK;
}

/*
 * Find the next NAL unit in a byte stream (Annex B format).
 * Searches for start code 00 00 01 or 00 00 00 01.
 *
 * data      - pointer to the buffer to search
 * size      - total buffer size
 * nal_start - (out) index of first byte AFTER the start code
 * nal_size  - (out) length of the NAL unit payload (up to next start code or end)
 *
 * Returns 1 if found, 0 if not found.
 */
int h264_find_next_nal(const uint8_t *data, int size,
                       int *nal_start, int *nal_size)
{
    int i;
    int start = -1;

    /* Find first start code */
    for (i = 0; i + 2 < size; i++) {
        if (data[i] == 0x00 && data[i+1] == 0x00) {
            if (data[i+2] == 0x01) {
                start = i + 3;
                break;
            } else if (i + 3 < size && data[i+2] == 0x00 && data[i+3] == 0x01) {
                start = i + 4;
                break;
            }
        }
    }
    if (start < 0) return 0;

    /* Find end = next start code */
    int end = size;
    for (i = start; i + 2 < size; i++) {
        if (data[i] == 0x00 && data[i+1] == 0x00) {
            if (data[i+2] == 0x01) {
                /* back up over any leading zeros of this start code */
                end = i;
                while (end > start && data[end-1] == 0x00) end--;
                break;
            } else if (i + 3 < size && data[i+2] == 0x00 && data[i+3] == 0x01) {
                end = i;
                while (end > start && data[end-1] == 0x00) end--;
                break;
            }
        }
    }

    *nal_start = start;
    *nal_size  = end - start;
    return 1;
}

/*
 * Remove emulation prevention bytes inline (wrapper kept for compatibility).
 */
int h264_remove_emulation_prevention(const uint8_t *data, int size,
                                     uint8_t *out, int out_size)
{
    return h264_nalu_to_rbsp(data, size, out, out_size);
}
