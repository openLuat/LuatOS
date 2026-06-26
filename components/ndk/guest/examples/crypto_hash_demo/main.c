/*
 * crypto_hash_demo — call the host MD5 / CRC32 CSRs (0x230 / 0x231).
 *
 * The host writes the request into the exchange buffer at offsets 0..15:
 *     ex[0] = cmd  (0x30 = MD5, 0x31 = CRC32)
 *     ex[1] = len  (input length in bytes)
 *     ex[2] = in_offset   (offset of input in exchange buffer)
 *     ex[3] = out_offset  (offset of MD5 output in exchange buffer; CRC32 ignored)
 *
 * The guest writes the result back at offsets 16..31:
 *     ex[4] = status code (LUAT_NDK_CRYPTO_STATUS_OK on success)
 *     ex[5] = output length (16 for MD5, 4 for CRC32, 0 on error)
 *     ex[6] = CRC32 result (CRC32 only; high word for 64-bit split is 0)
 */
#include "luat_ndk_helper.h"

#define CMD_MD5   LUAT_NDK_CMD_CRYPTO_MD5
#define CMD_CRC32 LUAT_NDK_CMD_CRYPTO_CRC32

static int main(void) {
    volatile uint32_t *ex = ndk_exchange_u32(0);

    uint32_t cmd     = ex[0];
    uint32_t in_len  = ex[1];
    uint32_t in_off  = ex[2];
    uint32_t out_off = ex[3];

    /* defaults: error */
    ex[4] = LUAT_NDK_CRYPTO_STATUS_HOST_ERROR;
    ex[5] = 0u;
    ex[6] = 0u;

    if (cmd == CMD_MD5) {
        uint32_t status = ndk_hash_md5(in_off, in_len, out_off);
        ex[4] = status;
        ex[5] = (status == LUAT_NDK_CRYPTO_STATUS_OK) ? 16u : 0u;
    } else if (cmd == CMD_CRC32) {
        /* CRC32 result is returned directly in a0 (not a status code). */
        uint32_t crc = ndk_hash_crc32(in_off, in_len);
        /* Check ndk_last_error() to distinguish "ok" from "bad bounds". */
        uint32_t err = ndk_last_error();
        ex[4] = (err == LUAT_NDK_HOST_ERR_NONE)
                    ? LUAT_NDK_CRYPTO_STATUS_OK
                    : LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS;
        ex[5] = (err == LUAT_NDK_HOST_ERR_NONE) ? 4u : 0u;
        ex[6] = crc;
        if (err == LUAT_NDK_HOST_ERR_NONE) {
            /* Write the 4-byte little-endian CRC32 to out_off for the host
             * to read back. */
            ndk_store32_le(ndk_exchange_ptr() + out_off, crc);
        }
    } else {
        ex[4] = LUAT_NDK_HOST_ERR_BAD_OPCODE;
    }

    ndk_exit_ok();
    return 0;
}

NDK_GUEST_START(main)
