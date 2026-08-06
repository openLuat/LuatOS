#ifndef LUAT_TINY_EPD_CUSTOM_H
#define LUAT_TINY_EPD_CUSTOM_H

#include "tiny_epd_driver.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Declarative custom driver.
 *
 * A profile is a list of command sequences (reset / command / data / delay /
 * busy / whole-framebuffer write) that describe a conventional e-paper
 * controller without writing a C driver.  The sequences are parsed by the
 * language binding (or a C caller) into tiny_epd_custom_profile_t before the
 * refresh worker runs, because the worker has no Lua context.
 */

typedef enum {
    TINY_EPD_CUSTOM_OP_CMD = 1,
    TINY_EPD_CUSTOM_OP_DATA,
    TINY_EPD_CUSTOM_OP_DELAY,
    TINY_EPD_CUSTOM_OP_BUSY,
    TINY_EPD_CUSTOM_OP_RESET,
    TINY_EPD_CUSTOM_OP_WRITE_RAM,
    TINY_EPD_CUSTOM_OP_WRITE_RAM2
} tiny_epd_custom_op_type_t;

typedef struct {
    tiny_epd_custom_op_type_t type;
    uint8_t cmd;
    uint16_t len;
    /* Heap-owned data for CMD_DATA. Freed with the profile. */
    uint8_t *data;
    uint8_t idle_level;
    uint32_t timeout_ms;
    uint32_t delay_ms;
    uint32_t reset_high_ms;
    uint32_t reset_low_ms;
    uint32_t reset_high2_ms;
} tiny_epd_custom_op_t;

typedef struct {
    tiny_epd_custom_op_t *ops;
    size_t count;
    size_t capacity;
} tiny_epd_custom_seq_t;

typedef enum {
    TINY_EPD_CUSTOM_SEQ_INIT = 0,
    TINY_EPD_CUSTOM_SEQ_FAST_INIT,
    TINY_EPD_CUSTOM_SEQ_FULL,
    TINY_EPD_CUSTOM_SEQ_FAST,
    TINY_EPD_CUSTOM_SEQ_PARTIAL,
    TINY_EPD_CUSTOM_SEQ_SLEEP,
    TINY_EPD_CUSTOM_SEQ_MAX
} tiny_epd_custom_seq_kind_t;

typedef struct {
    uint16_t width;
    uint16_t height;
    uint8_t busy_idle_level;
    uint32_t busy_timeout_ms;
    /* Owned copy of the allocating port; used to grow/free sequences. */
    tiny_epd_port_t port;
    tiny_epd_custom_seq_t seq[TINY_EPD_CUSTOM_SEQ_MAX];
} tiny_epd_custom_profile_t;

typedef struct {
    tiny_epd_driver_t base;
    tiny_epd_custom_profile_t *profile;
} tiny_epd_custom_driver_t;

tiny_epd_custom_profile_t *tiny_epd_custom_profile_create(const tiny_epd_port_t *port);
void tiny_epd_custom_profile_destroy(const tiny_epd_port_t *port,
                                     tiny_epd_custom_profile_t *profile);

/* Sequence builders. All return TINY_EPD_OK or a tiny_epd_err_t. */
int tiny_epd_custom_seq_add_cmd(tiny_epd_custom_profile_t *profile,
                                tiny_epd_custom_seq_kind_t kind,
                                uint8_t cmd);
int tiny_epd_custom_seq_add_cmd_data(tiny_epd_custom_profile_t *profile,
                                     tiny_epd_custom_seq_kind_t kind,
                                     uint8_t cmd,
                                     const uint8_t *data,
                                     size_t len);
int tiny_epd_custom_seq_add_delay(tiny_epd_custom_profile_t *profile,
                                  tiny_epd_custom_seq_kind_t kind,
                                  uint32_t ms);
int tiny_epd_custom_seq_add_busy(tiny_epd_custom_profile_t *profile,
                                 tiny_epd_custom_seq_kind_t kind,
                                 uint8_t idle_level,
                                 uint32_t timeout_ms);
int tiny_epd_custom_seq_add_reset(tiny_epd_custom_profile_t *profile,
                                  tiny_epd_custom_seq_kind_t kind,
                                  uint32_t high_ms,
                                  uint32_t low_ms,
                                  uint32_t high2_ms);
int tiny_epd_custom_seq_add_write_ram(tiny_epd_custom_profile_t *profile,
                                      tiny_epd_custom_seq_kind_t kind,
                                      uint8_t cmd,
                                      int second_plane);

/*
 * Builds a per-panel driver that owns the profile.  The caller keeps
 * ownership of the driver object and must call tiny_epd_custom_driver_destroy
 * after tiny_epd_destroy().
 */
tiny_epd_custom_driver_t *tiny_epd_custom_driver_create(const tiny_epd_port_t *port,
                                                        tiny_epd_custom_profile_t *profile);
void tiny_epd_custom_driver_destroy(const tiny_epd_port_t *port,
                                    tiny_epd_custom_driver_t *driver);

int tiny_epd_custom_driver_init(tiny_epd_t *epd);
int tiny_epd_custom_driver_refresh(tiny_epd_t *epd,
                                   tiny_epd_refresh_mode_t mode,
                                   const tiny_epd_rect_t *rect);
int tiny_epd_custom_driver_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode);

#ifdef __cplusplus
}
#endif

#endif
