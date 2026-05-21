#pragma once

#include <stdint.h>

#include "luat_ndk.h"
#include "luat_ndk_abi.h"

void luat_ndk_host_othercsr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value);
void luat_ndk_host_othercsr_read(luat_ndk_t *ctx, uint32_t csrno, uint32_t *value);
uint32_t luat_ndk_host_control_store(luat_ndk_t *ctx, uint32_t addy, uint32_t value);

// Event management
luat_ndk_event_header_t* luat_ndk_event_header(luat_ndk_t *ctx);
void luat_ndk_event_reset(luat_ndk_t *ctx);
void luat_ndk_event_set_last_error(luat_ndk_t *ctx, luat_ndk_host_err_t err);
void luat_ndk_event_push(luat_ndk_t *ctx, uint16_t type, uint16_t source, uint32_t data);
void luat_ndk_event_push_timer(luat_ndk_t *ctx, uint32_t delay_us);

// GPIO CSR handling
uint32_t luat_ndk_gpio_csr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value);
void luat_ndk_gpio_reset(luat_ndk_t *ctx);

// UART CSR handling
uint32_t luat_ndk_uart_csr_write(luat_ndk_t *ctx, uint32_t csrno, uint32_t value);
void luat_ndk_uart_reset(luat_ndk_t *ctx);

// CRYPTO CSR handling
uint32_t luat_ndk_crypto_md5_csr_write(luat_ndk_t *ctx, uint32_t value);
uint32_t luat_ndk_crypto_crc32_csr_write(luat_ndk_t *ctx, uint32_t value);
