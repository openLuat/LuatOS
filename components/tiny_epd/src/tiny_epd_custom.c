#include "tiny_epd_custom.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define TINY_EPD_CUSTOM_DEFAULT_BUSY_TIMEOUT_MS 30000u

typedef struct {
    uint8_t fast_enabled;
} tiny_epd_custom_ctx_t;

static tiny_epd_custom_op_t *tiny_epd_custom_seq_append(tiny_epd_custom_profile_t *profile,
                                                        tiny_epd_custom_seq_kind_t kind)
{
    tiny_epd_custom_seq_t *seq;
    tiny_epd_custom_op_t *ops;
    size_t capacity;

    if (profile == NULL || kind >= TINY_EPD_CUSTOM_SEQ_MAX ||
        profile->port.malloc == NULL || profile->port.free == NULL) {
        return NULL;
    }
    seq = &profile->seq[kind];
    if (seq->count >= seq->capacity) {
        capacity = seq->capacity == 0u ? 4u : seq->capacity * 2u;
        if (capacity < seq->capacity) {
            return NULL;
        }
        ops = (tiny_epd_custom_op_t *)profile->port.malloc(profile->port.user,
                                                   capacity * sizeof(tiny_epd_custom_op_t));
        if (ops == NULL) {
            return NULL;
        }
        if (seq->ops != NULL) {
            memcpy(ops, seq->ops, seq->count * sizeof(tiny_epd_custom_op_t));
            profile->port.free(profile->port.user, seq->ops);
        }
        seq->ops = ops;
        seq->capacity = capacity;
    }
    return &seq->ops[seq->count++];
}

int tiny_epd_custom_seq_add_cmd(tiny_epd_custom_profile_t *profile,
                                tiny_epd_custom_seq_kind_t kind,
                                uint8_t cmd)
{
    tiny_epd_custom_op_t *op;

    op = tiny_epd_custom_seq_append(profile, kind);
    if (op == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(op, 0, sizeof(*op));
    op->type = TINY_EPD_CUSTOM_OP_CMD;
    op->cmd = cmd;
    return TINY_EPD_OK;
}

int tiny_epd_custom_seq_add_cmd_data(tiny_epd_custom_profile_t *profile,
                                     tiny_epd_custom_seq_kind_t kind,
                                     uint8_t cmd,
                                     const uint8_t *data,
                                     size_t len)
{
    tiny_epd_custom_op_t *op;
    uint8_t *copy;
    if (profile == NULL || (data == NULL && len != 0u) || len > UINT16_MAX) {
        return TINY_EPD_ERR_PARAM;
    }
    op = tiny_epd_custom_seq_append(profile, kind);
    if (op == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    copy = NULL;
    if (len != 0u) {
        copy = (uint8_t *)profile->port.malloc(profile->port.user, len);
        if (copy == NULL) {
            profile->seq[kind].count--;
            return TINY_EPD_ERR_NO_MEM;
        }
        memcpy(copy, data, len);
    }
    memset(op, 0, sizeof(*op));
    op->type = TINY_EPD_CUSTOM_OP_DATA;
    op->cmd = cmd;
    op->len = (uint16_t)len;
    op->data = copy;
    return TINY_EPD_OK;
}

int tiny_epd_custom_seq_add_delay(tiny_epd_custom_profile_t *profile,
                                  tiny_epd_custom_seq_kind_t kind,
                                  uint32_t ms)
{
    tiny_epd_custom_op_t *op;

    op = tiny_epd_custom_seq_append(profile, kind);
    if (op == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(op, 0, sizeof(*op));
    op->type = TINY_EPD_CUSTOM_OP_DELAY;
    op->delay_ms = ms;
    return TINY_EPD_OK;
}

int tiny_epd_custom_seq_add_busy(tiny_epd_custom_profile_t *profile,
                                 tiny_epd_custom_seq_kind_t kind,
                                 uint8_t idle_level,
                                 uint32_t timeout_ms)
{
    tiny_epd_custom_op_t *op;

    op = tiny_epd_custom_seq_append(profile, kind);
    if (op == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(op, 0, sizeof(*op));
    op->type = TINY_EPD_CUSTOM_OP_BUSY;
    op->idle_level = idle_level;
    op->timeout_ms = timeout_ms;
    return TINY_EPD_OK;
}

int tiny_epd_custom_seq_add_reset(tiny_epd_custom_profile_t *profile,
                                  tiny_epd_custom_seq_kind_t kind,
                                  uint32_t high_ms,
                                  uint32_t low_ms,
                                  uint32_t high2_ms)
{
    tiny_epd_custom_op_t *op;

    op = tiny_epd_custom_seq_append(profile, kind);
    if (op == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(op, 0, sizeof(*op));
    op->type = TINY_EPD_CUSTOM_OP_RESET;
    op->reset_high_ms = high_ms;
    op->reset_low_ms = low_ms;
    op->reset_high2_ms = high2_ms;
    return TINY_EPD_OK;
}

int tiny_epd_custom_seq_add_write_ram(tiny_epd_custom_profile_t *profile,
                                      tiny_epd_custom_seq_kind_t kind,
                                      uint8_t cmd,
                                      int second_plane)
{
    tiny_epd_custom_op_t *op;

    op = tiny_epd_custom_seq_append(profile, kind);
    if (op == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    memset(op, 0, sizeof(*op));
    op->type = second_plane ? TINY_EPD_CUSTOM_OP_WRITE_RAM2 : TINY_EPD_CUSTOM_OP_WRITE_RAM;
    op->cmd = cmd;
    return TINY_EPD_OK;
}

tiny_epd_custom_profile_t *tiny_epd_custom_profile_create(const tiny_epd_port_t *port)
{
    tiny_epd_custom_profile_t *profile;

    if (port == NULL || port->malloc == NULL || port->free == NULL) {
        return NULL;
    }
    profile = (tiny_epd_custom_profile_t *)port->malloc(port->user, sizeof(*profile));
    if (profile != NULL) {
        memset(profile, 0, sizeof(*profile));
        profile->port = *port;
        profile->busy_idle_level = 0u;
        profile->busy_timeout_ms = TINY_EPD_CUSTOM_DEFAULT_BUSY_TIMEOUT_MS;
    }
    return profile;
}

void tiny_epd_custom_profile_destroy(const tiny_epd_port_t *port,
                                     tiny_epd_custom_profile_t *profile)
{
    tiny_epd_custom_seq_kind_t kind;

    if (port == NULL || profile == NULL) {
        return;
    }
    for (kind = TINY_EPD_CUSTOM_SEQ_INIT; kind < TINY_EPD_CUSTOM_SEQ_MAX; kind++) {
        tiny_epd_custom_seq_t *seq = &profile->seq[kind];
        size_t i;

        for (i = 0; i < seq->count; i++) {
            if (seq->ops[i].data != NULL) {
                port->free(port->user, seq->ops[i].data);
            }
        }
        if (seq->ops != NULL) {
            port->free(port->user, seq->ops);
        }
    }
    port->free(port->user, profile);
}

static int tiny_epd_custom_run_seq(tiny_epd_t *epd,
                                   const tiny_epd_custom_seq_t *seq)
{
    size_t i;
    int ret;

    for (i = 0; i < seq->count; i++) {
        const tiny_epd_custom_op_t *op = &seq->ops[i];

        switch (op->type) {
        case TINY_EPD_CUSTOM_OP_CMD:
            ret = tiny_epd_write_cmd(epd, op->cmd);
            break;
        case TINY_EPD_CUSTOM_OP_DATA:
            ret = tiny_epd_write_cmd(epd, op->cmd);
            if (ret == TINY_EPD_OK) {
                ret = tiny_epd_write_data(epd, op->data, op->len);
            }
            break;
        case TINY_EPD_CUSTOM_OP_DELAY:
            tiny_epd_delay_ms(epd, op->delay_ms);
            ret = TINY_EPD_OK;
            break;
        case TINY_EPD_CUSTOM_OP_BUSY:
            ret = tiny_epd_wait_busy(epd, op->idle_level, op->timeout_ms);
            break;
        case TINY_EPD_CUSTOM_OP_RESET:
        {
            tiny_epd_reset_step_t steps[3];
            tiny_epd_reset_sequence_t sequence;

            steps[0].level = 1;
            steps[0].delay_ms = op->reset_high_ms;
            steps[1].level = 0;
            steps[1].delay_ms = op->reset_low_ms;
            steps[2].level = 1;
            steps[2].delay_ms = op->reset_high2_ms;
            sequence.steps = steps;
            sequence.count = 3;
            ret = tiny_epd_reset_panel(epd, &sequence);
            break;
        }
        case TINY_EPD_CUSTOM_OP_WRITE_RAM:
        case TINY_EPD_CUSTOM_OP_WRITE_RAM2:
        {
            const uint8_t *framebuffer = tiny_epd_framebuffer_const(epd);
            size_t plane_size;
            const uint8_t *src;
            size_t len;

            if (framebuffer == NULL) {
                return TINY_EPD_ERR_PARAM;
            }
            ret = tiny_epd_write_cmd(epd, op->cmd);
            if (ret != TINY_EPD_OK) {
                break;
            }
            plane_size = (size_t)tiny_epd_stride(epd) * tiny_epd_native_height(epd);
            len = tiny_epd_framebuffer_size(epd);
            if (op->type == TINY_EPD_CUSTOM_OP_WRITE_RAM2 &&
                tiny_epd_plane_count(epd) > 1u) {
                src = framebuffer + plane_size;
                len = plane_size;
            }
            else {
                src = framebuffer;
            }
            ret = tiny_epd_write_data(epd, src, len);
            break;
        }
        default:
            return TINY_EPD_ERR_PARAM;
        }
        if (ret != TINY_EPD_OK) {
            return ret;
        }
    }
    return TINY_EPD_OK;
}

int tiny_epd_custom_driver_init(tiny_epd_t *epd)
{
    tiny_epd_custom_driver_t *driver = (tiny_epd_custom_driver_t *)epd->driver;
    tiny_epd_custom_ctx_t *ctx = (tiny_epd_custom_ctx_t *)tiny_epd_driver_state(epd);

    if (driver == NULL || driver->profile == NULL ||
        driver->profile->seq[TINY_EPD_CUSTOM_SEQ_INIT].count == 0u) {
        return TINY_EPD_ERR_PARAM;
    }
    if (ctx != NULL) {
        ctx->fast_enabled = 0;
    }
    return tiny_epd_custom_run_seq(epd, &driver->profile->seq[TINY_EPD_CUSTOM_SEQ_INIT]);
}

int tiny_epd_custom_driver_refresh(tiny_epd_t *epd,
                                   tiny_epd_refresh_mode_t mode,
                                   const tiny_epd_rect_t *rect)
{
    tiny_epd_custom_driver_t *driver = (tiny_epd_custom_driver_t *)epd->driver;
    tiny_epd_custom_ctx_t *ctx = (tiny_epd_custom_ctx_t *)tiny_epd_driver_state(epd);
    tiny_epd_custom_seq_kind_t kind;
    int ret;

    if (driver == NULL || driver->profile == NULL || rect != NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }

    if (mode == TINY_EPD_REFRESH_FAST) {
        if (driver->profile->seq[TINY_EPD_CUSTOM_SEQ_FAST].count == 0u) {
            return TINY_EPD_ERR_UNSUPPORTED_MODE;
        }
        if (ctx == NULL || !ctx->fast_enabled) {
            if (driver->profile->seq[TINY_EPD_CUSTOM_SEQ_FAST_INIT].count != 0u) {
                ret = tiny_epd_custom_run_seq(
                    epd, &driver->profile->seq[TINY_EPD_CUSTOM_SEQ_FAST_INIT]);
                if (ret != TINY_EPD_OK) {
                    return ret;
                }
            }
            if (ctx != NULL) {
                ctx->fast_enabled = 1;
            }
        }
        kind = TINY_EPD_CUSTOM_SEQ_FAST;
    }
    else if (mode == TINY_EPD_REFRESH_PARTIAL) {
        if (driver->profile->seq[TINY_EPD_CUSTOM_SEQ_PARTIAL].count == 0u) {
            return TINY_EPD_ERR_UNSUPPORTED_MODE;
        }
        if (ctx != NULL && ctx->fast_enabled) {
            ret = tiny_epd_custom_run_seq(
                epd, &driver->profile->seq[TINY_EPD_CUSTOM_SEQ_INIT]);
            if (ret != TINY_EPD_OK) {
                return ret;
            }
            ctx->fast_enabled = 0;
        }
        kind = TINY_EPD_CUSTOM_SEQ_PARTIAL;
    }
    else if (mode == TINY_EPD_REFRESH_FULL) {
        if (driver->profile->seq[TINY_EPD_CUSTOM_SEQ_FULL].count == 0u) {
            return TINY_EPD_ERR_UNSUPPORTED_MODE;
        }
        if (ctx != NULL && ctx->fast_enabled) {
            ret = tiny_epd_custom_run_seq(
                epd, &driver->profile->seq[TINY_EPD_CUSTOM_SEQ_INIT]);
            if (ret != TINY_EPD_OK) {
                return ret;
            }
            ctx->fast_enabled = 0;
        }
        kind = TINY_EPD_CUSTOM_SEQ_FULL;
    }
    else {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }

    return tiny_epd_custom_run_seq(epd, &driver->profile->seq[kind]);
}

int tiny_epd_custom_driver_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    tiny_epd_custom_driver_t *driver = (tiny_epd_custom_driver_t *)epd->driver;

    if (driver == NULL || driver->profile == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (mode == TINY_EPD_SLEEP_AUTO) {
        mode = TINY_EPD_SLEEP_DEEP;
    }
    if (mode != TINY_EPD_SLEEP_DEEP ||
        driver->profile->seq[TINY_EPD_CUSTOM_SEQ_SLEEP].count == 0u) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    return tiny_epd_custom_run_seq(epd, &driver->profile->seq[TINY_EPD_CUSTOM_SEQ_SLEEP]);
}

tiny_epd_custom_driver_t *tiny_epd_custom_driver_create(const tiny_epd_port_t *port,
                                                        tiny_epd_custom_profile_t *profile)
{
    tiny_epd_custom_driver_t *driver;
    uint32_t caps;

    if (port == NULL || port->malloc == NULL || port->free == NULL ||
        profile == NULL || profile->width == 0u || profile->height == 0u) {
        return NULL;
    }
    driver = (tiny_epd_custom_driver_t *)port->malloc(port->user, sizeof(*driver));
    if (driver == NULL) {
        return NULL;
    }
    memset(driver, 0, sizeof(*driver));

    caps = TINY_EPD_CAP_REFRESH_FULL | TINY_EPD_CAP_COLOR_BW;
    if (profile->seq[TINY_EPD_CUSTOM_SEQ_FAST].count != 0u) {
        caps |= TINY_EPD_CAP_REFRESH_FAST;
    }
    if (profile->seq[TINY_EPD_CUSTOM_SEQ_PARTIAL].count != 0u) {
        caps |= TINY_EPD_CAP_REFRESH_PARTIAL;
    }
    if (profile->seq[TINY_EPD_CUSTOM_SEQ_SLEEP].count != 0u) {
        caps |= TINY_EPD_CAP_SLEEP_DEEP;
    }

    driver->base.name = "custom";
    driver->base.width = profile->width;
    driver->base.height = profile->height;
    driver->base.bits_per_pixel = 1;
    driver->base.plane_count = 1;
    driver->base.caps = caps;
    driver->base.context_size = sizeof(tiny_epd_custom_ctx_t);
    driver->base.init = tiny_epd_custom_driver_init;
    driver->base.refresh = tiny_epd_custom_driver_refresh;
    driver->base.sleep = tiny_epd_custom_driver_sleep;
    driver->base.surface = NULL; /* default INDEX1 black/white */
    driver->profile = profile;
    return driver;
}

void tiny_epd_custom_driver_destroy(const tiny_epd_port_t *port,
                                    tiny_epd_custom_driver_t *driver)
{
    if (port == NULL || driver == NULL) {
        return;
    }
    tiny_epd_custom_profile_destroy(port, driver->profile);
    port->free(port->user, driver);
}
