#include "tiny_epd_port_example.h"

#include <string.h>

#define TINY_EPD_PORT_EXAMPLE_DEFAULT_POLL_MS 10u

static int tiny_epd_port_example_write_cmd(void *user, uint8_t cmd)
{
    tiny_epd_port_example_t *ctx = (tiny_epd_port_example_t *)user;

    if (ctx == NULL || ctx->config.hal.gpio_write == NULL ||
        ctx->config.hal.spi_write == NULL) {
        return -1;
    }
    if (ctx->config.hal.gpio_write(ctx->config.hal.user, ctx->config.pin_dc, 0) != 0) {
        return -1;
    }
    return ctx->config.hal.spi_write(ctx->config.hal.user, &cmd, 1);
}

static int tiny_epd_port_example_write_data(void *user, const uint8_t *data, size_t len)
{
    tiny_epd_port_example_t *ctx = (tiny_epd_port_example_t *)user;

    if (ctx == NULL || (data == NULL && len != 0) ||
        ctx->config.hal.gpio_write == NULL || ctx->config.hal.spi_write == NULL) {
        return -1;
    }
    if (ctx->config.hal.gpio_write(ctx->config.hal.user, ctx->config.pin_dc, 1) != 0) {
        return -1;
    }
    return ctx->config.hal.spi_write(ctx->config.hal.user, data, len);
}

static int tiny_epd_port_example_reset(void *user, const tiny_epd_reset_sequence_t *sequence)
{
    tiny_epd_port_example_t *ctx = (tiny_epd_port_example_t *)user;
    size_t i;

    if (ctx == NULL || ctx->config.hal.gpio_write == NULL ||
        (sequence != NULL && sequence->count != 0 && sequence->steps == NULL)) {
        return -1;
    }
    if (sequence == NULL || sequence->count == 0) {
        return 0;
    }
    if (ctx->config.hal.delay_ms == NULL) {
        return -1;
    }
    for (i = 0; i < sequence->count; i++) {
        if (ctx->config.hal.gpio_write(ctx->config.hal.user, ctx->config.pin_rst,
                                       sequence->steps[i].level) != 0) {
            return -1;
        }
        ctx->config.hal.delay_ms(ctx->config.hal.user, sequence->steps[i].delay_ms);
    }
    return 0;
}

static int tiny_epd_port_example_wait_busy(void *user, uint8_t idle_level, uint32_t timeout_ms)
{
    tiny_epd_port_example_t *ctx = (tiny_epd_port_example_t *)user;
    uint64_t started_ms;
    uint32_t poll_ms;
    int level;

    if (ctx == NULL || ctx->config.hal.gpio_read == NULL ||
        ctx->config.hal.tick_ms == NULL || ctx->config.hal.delay_ms == NULL) {
        return -1;
    }

    started_ms = ctx->config.hal.tick_ms(ctx->config.hal.user);
    poll_ms = ctx->config.busy_poll_ms ? ctx->config.busy_poll_ms :
              TINY_EPD_PORT_EXAMPLE_DEFAULT_POLL_MS;
    for (;;) {
        level = ctx->config.hal.gpio_read(ctx->config.hal.user, ctx->config.pin_busy);
        if (level < 0) {
            return -1;
        }
        if ((uint8_t)level == idle_level) {
            return 0;
        }
        if (ctx->config.hal.tick_ms(ctx->config.hal.user) - started_ms >= timeout_ms) {
            return -1;
        }
        ctx->config.hal.delay_ms(ctx->config.hal.user, poll_ms);
    }
}

static void tiny_epd_port_example_delay_ms(void *user, uint32_t ms)
{
    tiny_epd_port_example_t *ctx = (tiny_epd_port_example_t *)user;

    if (ctx != NULL && ctx->config.hal.delay_ms != NULL) {
        ctx->config.hal.delay_ms(ctx->config.hal.user, ms);
    }
}

int tiny_epd_port_example_init(tiny_epd_port_t *port,
                               tiny_epd_port_example_t *ctx,
                               const tiny_epd_port_example_config_t *config)
{
    if (port == NULL || ctx == NULL || config == NULL ||
        config->pin_dc < 0 || config->pin_rst < 0 || config->pin_busy < 0 ||
        config->hal.spi_write == NULL || config->hal.gpio_write == NULL ||
        config->hal.gpio_read == NULL || config->hal.tick_ms == NULL ||
        config->hal.delay_ms == NULL) {
        return TINY_EPD_ERR_PARAM;
    }

    memset(ctx, 0, sizeof(*ctx));
    memcpy(&ctx->config, config, sizeof(*config));
    memset(port, 0, sizeof(*port));
    port->user = ctx;
    port->write_cmd = tiny_epd_port_example_write_cmd;
    port->write_data = tiny_epd_port_example_write_data;
    port->reset = tiny_epd_port_example_reset;
    port->wait_busy = tiny_epd_port_example_wait_busy;
    port->delay_ms = tiny_epd_port_example_delay_ms;
    port->malloc = config->hal.malloc;
    port->free = config->hal.free;
    return TINY_EPD_OK;
}
