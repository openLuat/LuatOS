#include "luat_ndk_host.h"

#include "luat_crypto.h"

#define NDK_CRYPTO_MD5_SIZE 16u

static uint32_t ndk_crypto_status_to_error(uint32_t status) {
    switch (status) {
    case LUAT_NDK_CRYPTO_STATUS_OK:
        return LUAT_NDK_HOST_ERR_NONE;
    case LUAT_NDK_CRYPTO_STATUS_BAD_ARG:
    case LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS:
        return LUAT_NDK_HOST_ERR_PARAM;
    case LUAT_NDK_CRYPTO_STATUS_UNSUPPORTED:
        return LUAT_NDK_HOST_ERR_UNSUPPORTED;
    default:
        return LUAT_NDK_HOST_ERR_UNSUPPORTED;
    }
}

static int ndk_crypto_bounds_ok(const luat_ndk_t *ctx, uint32_t offset, uint32_t length) {
    uint64_t end = 0;
    if (!ctx) return 0;
    end = (uint64_t)offset + (uint64_t)length;
    return end <= ctx->exchange_size;
}

uint32_t luat_ndk_crypto_md5_csr_write(luat_ndk_t *ctx, uint32_t value) {
    uint32_t in_offset = 0;
    uint32_t in_len = 0;
    uint32_t out_offset = 0;
    uint32_t status = LUAT_NDK_CRYPTO_STATUS_OK;
    uint8_t *in_ptr = NULL;
    uint8_t *out_ptr = NULL;

    if (!ctx || !ctx->ram) {
        return LUAT_NDK_CRYPTO_STATUS_HOST_ERROR;
    }

    in_offset = LUAT_NDK_CRYPTO_MD5_INPUT_OFFSET(value);
    in_len = LUAT_NDK_CRYPTO_MD5_INPUT_LENGTH(value);
    out_offset = LUAT_NDK_CRYPTO_MD5_OUTPUT_OFFSET(value);

    if (!ndk_crypto_bounds_ok(ctx, in_offset, in_len) || !ndk_crypto_bounds_ok(ctx, out_offset, NDK_CRYPTO_MD5_SIZE)) {
        status = LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS;
        luat_ndk_event_set_last_error(ctx, (luat_ndk_host_err_t)ndk_crypto_status_to_error(status));
        return status;
    }

    in_ptr = ctx->ram + ctx->exchange_offset + in_offset;
    out_ptr = ctx->ram + ctx->exchange_offset + out_offset;

    if (luat_crypto_md5_simple((const char *)in_ptr, in_len, out_ptr) != 0) {
        status = LUAT_NDK_CRYPTO_STATUS_UNSUPPORTED;
        luat_ndk_event_set_last_error(ctx, (luat_ndk_host_err_t)ndk_crypto_status_to_error(status));
        return status;
    }

    luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
    return LUAT_NDK_CRYPTO_STATUS_OK;
}

uint32_t luat_ndk_crypto_crc32_csr_write(luat_ndk_t *ctx, uint32_t value) {
    uint32_t in_offset = 0;
    uint32_t in_len = 0;
    const uint8_t *in_ptr = NULL;

    if (!ctx || !ctx->ram) {
        return LUAT_NDK_CRYPTO_STATUS_HOST_ERROR;
    }

    in_offset = LUAT_NDK_CRYPTO_CRC32_INPUT_OFFSET(value);
    in_len = LUAT_NDK_CRYPTO_CRC32_INPUT_LENGTH(value);
    if (!ndk_crypto_bounds_ok(ctx, in_offset, in_len)) {
        luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_PARAM);
        return LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS;
    }

    in_ptr = ctx->ram + ctx->exchange_offset + in_offset;
    luat_ndk_event_set_last_error(ctx, LUAT_NDK_HOST_ERR_NONE);
    return luat_crc32(in_ptr, in_len, 0xFFFFFFFFu, 0);
}
