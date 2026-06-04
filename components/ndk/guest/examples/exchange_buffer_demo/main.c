/*
 * exchange_buffer_demo — exercise the host<->guest exchange buffer.
 *
 * The host writes a small request into the first 16 bytes; the guest
 * computes sum / xor / verdict and stores them into the result region
 * (bytes 16-31) of the exchange buffer. Then exits via SYSCON 0x5555.
 */
#include "luat_ndk_helper.h"

typedef struct {
    uint32_t a;
    uint32_t b;
    uint32_t control;
    uint32_t reserved;
} exchange_request_t;

typedef struct {
    uint32_t sum;
    uint32_t xorv;
    uint32_t verdict;
    uint32_t reserved;
} exchange_result_t;

static int main(void) {
    volatile exchange_request_t *req =
        (volatile exchange_request_t *)ndk_exchange_ptr();
    volatile exchange_result_t *out =
        (volatile exchange_result_t *)(ndk_exchange_ptr() + 16u);

    ndk_exchange_write_u32(0,  0x12345678u);          /* req->a */
    ndk_exchange_write_u32(4,  0x9ABCDEF0u);          /* req->b */
    ndk_exchange_write_u32(8,  0xA5A50001u);          /* req->control */
    ndk_exchange_write_u32(12, 0u);                   /* req->reserved */

    ndk_exchange_write_u32(16, req->a + req->b);                          /* out->sum */
    ndk_exchange_write_u32(20, req->a ^ req->b);                          /* out->xorv */
    ndk_exchange_write_u32(24,
        (req->control == 0xA5A50001u) ? 0x900Du : 0xBADu);                /* out->verdict */
    ndk_exchange_write_u32(28, 0u);                                       /* out->reserved */

    ndk_exit_ok();
    return 0;
}

NDK_GUEST_START(main)
