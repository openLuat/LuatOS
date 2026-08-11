#include "tiny_epd_port_luatos.h"

#if defined(LUAT_USE_TINY_EPD)

#include "luat_gpio.h"
#define LUAT_LOG_TAG "tiny_epd"
#include "luat_log.h"
#if defined(TINY_EPD_PORT_LUATOS_DEBUG_BUSY)
#define TINY_EPD_BUSY_LOGE(...) LLOGE(__VA_ARGS__)
#define TINY_EPD_BUSY_LOGW(...) LLOGW(__VA_ARGS__)
#define TINY_EPD_BUSY_LOGI(...) LLOGI(__VA_ARGS__)
#else
#define TINY_EPD_BUSY_LOGE(...) do { } while (0)
/* A timeout is actionable even in production; retain its GPIO diagnostics. */
#define TINY_EPD_BUSY_LOGW(...) LLOGW(__VA_ARGS__)
#define TINY_EPD_BUSY_LOGI(...) do { } while (0)
#endif
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_timer.h"

#include <string.h>

#define TINY_EPD_PORT_LUATOS_DEFAULT_POLL_MS 10u

static int tiny_epd_port_luatos_spi_write(tiny_epd_port_luatos_t *ctx,
                                          const uint8_t *data,
                                          size_t len)
{
    int ret;

    if (ctx == NULL || (data == NULL && len != 0)) {
        return -1;
    }
    if (len == 0) {
        return 0;
    }
    if (ctx->config.spi_device != NULL) {
        ret = luat_spi_device_send(ctx->config.spi_device, (const char *)data, len);
    }
    else {
        ret = luat_spi_send(ctx->config.spi_id, (const char *)data, len);
    }
    return ret < 0 ? -1 : 0;
}

static int tiny_epd_port_luatos_write_cmd(void *user, uint8_t cmd)
{
    tiny_epd_port_luatos_t *ctx = (tiny_epd_port_luatos_t *)user;

    if (ctx == NULL || luat_gpio_set(ctx->config.pin_dc, LUAT_GPIO_LOW) != 0) {
        return -1;
    }
    return tiny_epd_port_luatos_spi_write(ctx, &cmd, 1);
}

static int tiny_epd_port_luatos_write_data(void *user, const uint8_t *data, size_t len)
{
    tiny_epd_port_luatos_t *ctx = (tiny_epd_port_luatos_t *)user;

    if (ctx == NULL || luat_gpio_set(ctx->config.pin_dc, LUAT_GPIO_HIGH) != 0) {
        return -1;
    }
    return tiny_epd_port_luatos_spi_write(ctx, data, len);
}

static int tiny_epd_port_luatos_reset(void *user, const tiny_epd_reset_sequence_t *sequence)
{
    tiny_epd_port_luatos_t *ctx = (tiny_epd_port_luatos_t *)user;
    size_t i;

    if (ctx == NULL || (sequence != NULL && sequence->count != 0 && sequence->steps == NULL)) {
        return -1;
    }
    if (sequence == NULL || sequence->count == 0) {
        return 0;
    }
    for (i = 0; i < sequence->count; i++) {
        if (luat_gpio_set(ctx->config.pin_rst, sequence->steps[i].level) != 0) {
            return -1;
        }
        luat_timer_mdelay(sequence->steps[i].delay_ms);
    }
    return 0;
}

static int tiny_epd_port_luatos_wait_busy(void *user, uint8_t idle_level, uint32_t timeout_ms)
{
    tiny_epd_port_luatos_t *ctx = (tiny_epd_port_luatos_t *)user;
    uint64_t started_ms;
    uint64_t elapsed_ms;
    uint32_t poll_ms;
    int level;
    int first_level;
    int last_level;

    if (ctx == NULL) {
        return -1;
    }

    started_ms = luat_mcu_tick64_ms();
    poll_ms = ctx->config.busy_poll_ms ? ctx->config.busy_poll_ms :
              TINY_EPD_PORT_LUATOS_DEFAULT_POLL_MS;
    first_level = luat_gpio_get(ctx->config.pin_busy);
    if (first_level < 0) {
        TINY_EPD_BUSY_LOGE("busy read failed pin=%d", ctx->config.pin_busy);
        return -1;
    }
    last_level = first_level;
    TINY_EPD_BUSY_LOGI("wait_busy begin pin=%d idle=%u timeout=%u poll=%u first=%d",
                       ctx->config.pin_busy,
                       (unsigned int)idle_level,
                       (unsigned int)timeout_ms,
                       (unsigned int)poll_ms,
                       first_level);
    for (;;) {
        level = luat_gpio_get(ctx->config.pin_busy);
        if (level < 0) {
            TINY_EPD_BUSY_LOGE("busy read failed pin=%d", ctx->config.pin_busy);
            return -1;
        }
        if (level != last_level) {
            elapsed_ms = luat_mcu_tick64_ms() - started_ms;
            TINY_EPD_BUSY_LOGI("wait_busy change pin=%d level=%d elapsed=%u",
                               ctx->config.pin_busy,
                               level,
                               (unsigned int)elapsed_ms);
            last_level = level;
        }
        if ((uint8_t)level == idle_level) {
            elapsed_ms = luat_mcu_tick64_ms() - started_ms;
            TINY_EPD_BUSY_LOGI("wait_busy idle pin=%d idle=%u elapsed=%u first=%d last=%d",
                               ctx->config.pin_busy,
                               (unsigned int)idle_level,
                               (unsigned int)elapsed_ms,
                               first_level,
                               level);
            return 0;
        }
        elapsed_ms = luat_mcu_tick64_ms() - started_ms;
        if (elapsed_ms >= timeout_ms) {
            TINY_EPD_BUSY_LOGW("wait_busy timeout pin=%d idle=%u elapsed=%u first=%d last=%d",
                               ctx->config.pin_busy,
                               (unsigned int)idle_level,
                               (unsigned int)elapsed_ms,
                               first_level,
                               level);
            return -1;
        }
        luat_rtos_task_sleep(poll_ms);
    }
}

static void tiny_epd_port_luatos_delay_ms(void *user, uint32_t ms)
{
    (void)user;
    luat_timer_mdelay(ms);
}

static void *tiny_epd_port_luatos_malloc(void *user, size_t size)
{
    (void)user;
    return luat_heap_malloc(size);
}

static void tiny_epd_port_luatos_free(void *user, void *ptr)
{
    (void)user;
    luat_heap_free(ptr);
}

int tiny_epd_port_luatos_init(tiny_epd_port_t *port,
                              tiny_epd_port_luatos_t *ctx,
                              const tiny_epd_port_luatos_config_t *config)
{
    int busy_pull;

    if (port == NULL || ctx == NULL || config == NULL ||
        config->pin_dc < 0 || config->pin_rst < 0 || config->pin_busy < 0) {
        return TINY_EPD_ERR_PARAM;
    }

    memset(ctx, 0, sizeof(*ctx));
    memcpy(&ctx->config, config, sizeof(*config));
    busy_pull = config->busy_pull ? config->busy_pull : LUAT_GPIO_DEFAULT;
    luat_gpio_mode(ctx->config.pin_dc, LUAT_GPIO_OUTPUT, LUAT_GPIO_DEFAULT, LUAT_GPIO_HIGH);
    luat_gpio_mode(ctx->config.pin_rst, LUAT_GPIO_OUTPUT, LUAT_GPIO_DEFAULT, LUAT_GPIO_LOW);
    luat_gpio_mode(ctx->config.pin_busy, LUAT_GPIO_INPUT, busy_pull, LUAT_GPIO_LOW);

    memset(port, 0, sizeof(*port));
    port->user = ctx;
    port->write_cmd = tiny_epd_port_luatos_write_cmd;
    port->write_data = tiny_epd_port_luatos_write_data;
    port->reset = tiny_epd_port_luatos_reset;
    port->wait_busy = tiny_epd_port_luatos_wait_busy;
    port->delay_ms = tiny_epd_port_luatos_delay_ms;
    port->malloc = tiny_epd_port_luatos_malloc;
    port->free = tiny_epd_port_luatos_free;
    return TINY_EPD_OK;
}

#endif
