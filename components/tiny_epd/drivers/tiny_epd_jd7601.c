/*
 * JD7601 3.7" E6 480x720 six-colour e-paper (OSPTEK EPD037A02 / HINK-T037A02-A0).
 *
 * Command timing is ported from the vendor reference flow 3D7_E6_480x720_7601.c
 * (MSP430 bit-banged SPI) via the ESP32-S3 bring-up example in
 *   display-epd-3.7inch-480x720/examples/esp32s3-jd7601-spi-bringup/
 *
 * Geometry: the controller RAM is scanned 720 wide x 480 tall, i.e. the native
 * surface is landscape even though the part is sold as a 480x720 panel
 * (EPD037A02 spec: 480(H) x 720(V), which describes the glass, not the RAM
 * layout). 4bpp, 2 pixels per byte -> 480 rows x 360 bytes = 172800 bytes.
 *
 * Do NOT "fix" this to 480x720 / 240 bytes per row by reading the vendor
 * header: on hardware that produces the same page tiled three times down the
 * screen (240*3 = 720). The vendor example builds its payload column-wise
 * (EINK_COL_BYTES = SCREEN_WIDTH/2 = 240 bytes per column, 720 columns), which
 * is a different byte order that happens to total the same 172800 bytes; it is
 * not a row stride. Verified on hardware: only the 720x480 / stride 360 layout
 * shows a correct, non-repeating image.
 *
 * Panel characteristics that shape this driver:
 *   - Frame data is sent row-major through command 0x10 with no row/column
 *     address windowing: the whole frame follows the command in one stream.
 *   - BUSY is HIGH when idle and LOW while busy (opposite of most SSD16xx).
 *   - The reset is a double pulse, not the usual single pulse.
 *   - The vendor flow exposes only a full refresh. The waveform lives in the
 *     panel OTP (EPD037A02 spec: "Waveform stored in On-chip OTP") and the
 *     material we have carries no partial/fast waveform selector, so those
 *     modes are rejected instead of being silently faked.
 */

#include "tiny_epd_driver.h"

#include <stddef.h>
#include <stdint.h>

#define TINY_EPD_JD7601_WIDTH  720u
#define TINY_EPD_JD7601_HEIGHT 480u

/* INDEX4, MSB first: stride = (720 * 4) / 8 = 360 bytes, 480 rows = 172800.
 * The exact byte count is taken from the core at send time, not hardcoded. */

/* Vendor READBUSY: BUSY = 1 means idle, BUSY = 0 means busy. */
#define TINY_EPD_JD7601_BUSY_IDLE_LEVEL 1u
/* A six-colour full refresh runs a long waveform; the vendor port allows 60 s. */
#define TINY_EPD_JD7601_BUSY_TIMEOUT_MS 60000u
#define TINY_EPD_JD7601_BUSY_SETTLE_MS  10u

/* Match the vendor SPI chunking so one transaction stays bounded in size. */
#define TINY_EPD_JD7601_CHUNK_BYTES 4096u

/*
 * Mode byte for command 0x12 (DRF). The vendor flow only documents 0x00, but
 * on this controller family the byte can select another waveform slot stored in
 * the panel OTP. It is a build-time knob on purpose: probing values at runtime
 * would leave the panel in an unknown waveform, while a rebuild keeps the
 * experiment reproducible. Use e.g. -DTINY_EPD_JD7601_DRF_PARAM=0x01 to test a
 * candidate fast-refresh mode and watch the BUSY time in the log.
 */
#ifndef TINY_EPD_JD7601_DRF_PARAM
#define TINY_EPD_JD7601_DRF_PARAM 0x00u
#endif

/*
 * 每个面板的运行时状态。0x12(DRF) 的参数其实是面板 OTP 里的波形槽编号，
 * 厂商只公开了 0x00。这里把槽号做成运行时可改(panel:setDrf)，这样同一份
 * 固件就能扫描各个槽并对比刷新耗时/残影，不必为每个候选值重新编译。
 */
/*
 * 温度锁定值（命令 0xE6）。原厂《3D7E6 调用快刷说明》：IC 内烧了 10 个温度
 * 段（0~50℃，5 度一段），0~45℃ 段放全刷波形，45~50℃ 段放快刷波形。把
 * 0xE6 写成 48 就调用快刷波形；写成实测温度（读回大于 45 时钳到 42）就是
 * 全刷波形。port 层没有 SPI 读能力，读不到真实温度，默认锁 42（即原厂的
 * 钳制值），需要快刷时用 panel:setFast(1) 或 panel:setTemp(48) 切换。
 */
#define TINY_EPD_JD7601_TEMP_FULL 42u
#define TINY_EPD_JD7601_TEMP_FAST 48u

typedef struct {
    uint8_t drf;
    uint8_t drf_ready;
    uint8_t temp;
    uint8_t temp_ready;
    uint8_t temp_dirty;
} tiny_epd_jd7601_state_t;

static tiny_epd_jd7601_state_t *epd_jd7601_state(tiny_epd_t *epd)
{
    return (tiny_epd_jd7601_state_t *)tiny_epd_driver_state(epd);
}

static uint8_t epd_jd7601_drf(tiny_epd_t *epd)
{
    tiny_epd_jd7601_state_t *ctx = epd_jd7601_state(epd);

    return (ctx != NULL && ctx->drf_ready) ? ctx->drf
                                           : (uint8_t)TINY_EPD_JD7601_DRF_PARAM;
}

static uint8_t epd_jd7601_temp(tiny_epd_t *epd)
{
    tiny_epd_jd7601_state_t *ctx = epd_jd7601_state(epd);

    return (ctx != NULL && ctx->temp_ready) ? ctx->temp
                                            : (uint8_t)TINY_EPD_JD7601_TEMP_FULL;
}

/*
 * 可选：厂商参考代码里的“水波纹”波形调优序列（GDEH037E01 的
 * epd_init_jd7601_water_ripple_v2()）。这些是未公开的波形/时序参数，
 * 只影响刷新的观感（残影、水波纹），不会把全刷变成局刷或快刷。
 * 默认关闭；用 -DTINY_EPD_JD7601_WATER_RIPPLE=1 启用后对比画面。
 */
#ifndef TINY_EPD_JD7601_WATER_RIPPLE
#define TINY_EPD_JD7601_WATER_RIPPLE 0
#endif

static int epd_jd7601_cmd_data1(tiny_epd_t *epd, uint8_t cmd, uint8_t data)
{
    int ret = tiny_epd_write_cmd(epd, cmd);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return tiny_epd_write_data_byte(epd, data);
}

static int epd_jd7601_wait_idle(tiny_epd_t *epd)
{
    return tiny_epd_wait_busy(epd,
                              TINY_EPD_JD7601_BUSY_IDLE_LEVEL,
                              TINY_EPD_JD7601_BUSY_TIMEOUT_MS);
}

/*
 * Vendor hw_reset(): RST low 20 ms / high 10 ms, twice, then wait for BUSY.
 * The port drives the pin to each level and holds it for the given time.
 *
 * This is only the pulse train plus the first BUSY wait. The remaining 10 ms
 * settle and the second BUSY wait live in epd_jd7601_init(); together the two
 * reproduce the vendor hw_reset() + wait_busy() pair exactly. Keep the settle
 * where it is rather than folding it in here, or the sequence drifts.
 */
static int epd_jd7601_reset(tiny_epd_t *epd)
{
    static const tiny_epd_reset_step_t reset_steps[] = {
        {0, 20},
        {1, 10},
        {0, 20},
        {1, 10}
    };
    static const tiny_epd_reset_sequence_t reset_sequence = {
        reset_steps,
        sizeof(reset_steps) / sizeof(reset_steps[0])
    };
    int ret = tiny_epd_reset_panel(epd, &reset_sequence);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return TINY_EPD_OK;
}

/*
 * Vendor INIT_JD7601 / INIT_JD7601_fast 的公共部分：把温度值锁进 IC，让波形
 * 按温度段选择。原厂在每次刷图前都完整跑一遍 init，命令顺序固定为
 * 0xE0=0x02 -> 延时 20ms -> 0xE6=温度 -> 0xA5(等 busy + 50ms) -> 0xE9=0x01。
 */
static int epd_jd7601_apply_temp(tiny_epd_t *epd, uint8_t temp)
{
    tiny_epd_jd7601_state_t *ctx = epd_jd7601_state(epd);
    int ret = epd_jd7601_cmd_data1(epd, 0xE0u, 0x02u);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, 20u);
    ret = epd_jd7601_cmd_data1(epd, 0xE6u, temp);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = tiny_epd_write_cmd(epd, 0xA5u);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, 50u);
    ret = epd_jd7601_cmd_data1(epd, 0xE9u, 0x01u);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    if (ctx != NULL) {
        ctx->temp_dirty = 0;
    }
    return TINY_EPD_OK;
}

/* 复位 IC 并重新锁定温度值。运行时切换全刷/快刷时走这条路径。 */
static int epd_jd7601_relock(tiny_epd_t *epd)
{
    int ret = epd_jd7601_reset(epd);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_JD7601_BUSY_SETTLE_MS);
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_jd7601_apply_temp(epd, epd_jd7601_temp(epd));
}

/* Vendor INIT_JD7601: reset + lock temperature + 0xE9. */
static int epd_jd7601_init(tiny_epd_t *epd)
{
    tiny_epd_jd7601_state_t *ctx = epd_jd7601_state(epd);
    int ret;

    if (ctx != NULL) {
        if (!ctx->drf_ready) {
            ctx->drf = (uint8_t)TINY_EPD_JD7601_DRF_PARAM;
            ctx->drf_ready = 1;
        }
        if (!ctx->temp_ready) {
            ctx->temp = (uint8_t)TINY_EPD_JD7601_TEMP_FULL;
            ctx->temp_ready = 1;
        }
    }

    ret = epd_jd7601_relock(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

#if TINY_EPD_JD7601_WATER_RIPPLE
    /* 厂商 epd_init_jd7601_water_ripple_v2()：进入测试模式，写入波形参数，
     * 最后 0xFF 0xE3 退出测试模式。参数原样照抄，未做任何推测。 */
    ret = epd_jd7601_cmd_data1(epd, 0xFFu, 0xA5u);
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xEBu, 0x01u);
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xDAu, 0x04u);
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xB4u, 0x31u);
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xB0u, 0x03u);
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xC0u, 0x78u);
    if (ret == TINY_EPD_OK) {
        static const uint8_t ripple_ef[10] = {3, 80, 6, 45, 10, 36, 14, 8, 18, 4};
        ret = epd_jd7601_cmd_data(epd, 0xEFu, ripple_ef, sizeof(ripple_ef));
    }
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xDCu, 0x01u);
    if (ret == TINY_EPD_OK) {
        static const uint8_t ripple_dd[2] = {6, 18};
        ret = epd_jd7601_cmd_data(epd, 0xDDu, ripple_dd, sizeof(ripple_dd));
    }
    if (ret == TINY_EPD_OK) {
        static const uint8_t ripple_de[5] = {4, 10, 16, 22, 28};
        ret = epd_jd7601_cmd_data(epd, 0xDEu, ripple_de, sizeof(ripple_de));
    }
    if (ret == TINY_EPD_OK) ret = epd_jd7601_cmd_data1(epd, 0xFFu, 0xE3u);
#endif

    return ret;
}

/*
 * The canonical INDEX4 framebuffer already holds JD7601 RAM codes packed
 * MSB-first, so the frame streams byte for byte with no conversion. Command
 * 0x10 starts the transfer and the panel must be idle again before the payload.
 */
static int epd_jd7601_write_frame(tiny_epd_t *epd)
{
    const uint8_t *frame = tiny_epd_framebuffer_const(epd);
    /*
     * Take the length from the core rather than from a hardcoded constant so
     * this loop can never run past the buffer it indexes if the geometry
     * macros are ever edited. The panel geometry fixes it at 360 x 480 bytes.
     */
    size_t remaining = tiny_epd_framebuffer_size(epd);
    size_t offset = 0;
    int ret;

    if (frame == NULL) {
        return TINY_EPD_ERR_BAD_STATE;
    }

    ret = tiny_epd_write_cmd(epd, 0x10u);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    while (remaining > 0u) {
        size_t chunk = remaining > TINY_EPD_JD7601_CHUNK_BYTES ?
                       TINY_EPD_JD7601_CHUNK_BYTES : remaining;

        ret = tiny_epd_write_data(epd, frame + offset, chunk);
        if (ret != TINY_EPD_OK) {
            return ret;
        }
        offset += chunk;
        remaining -= chunk;
    }
    return TINY_EPD_OK;
}

/* Vendor 0x04 (PON) / 0x12 (DRF) / 0x02 (POF). */
static int epd_jd7601_panel_refresh(tiny_epd_t *epd)
{
    int ret = tiny_epd_write_cmd(epd, 0x04u);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_JD7601_BUSY_SETTLE_MS);

    ret = epd_jd7601_cmd_data1(epd, 0x12u, epd_jd7601_drf(epd));
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, TINY_EPD_JD7601_BUSY_SETTLE_MS);
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }

    ret = epd_jd7601_cmd_data1(epd, 0x02u, 0x00u);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    ret = epd_jd7601_wait_idle(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_delay_ms(epd, 20u);
    return TINY_EPD_OK;
}

static int epd_jd7601_refresh(tiny_epd_t *epd,
                              tiny_epd_refresh_mode_t mode,
                              const tiny_epd_rect_t *rect)
{
    int ret;

    if (mode == TINY_EPD_REFRESH_AUTO) {
        mode = TINY_EPD_REFRESH_FULL;
    }
    /*
     * The vendor sequence is full-frame only: no partial waveform, no fast
     * waveform and no RAM window command were ever published for this panel.
     * Reject the rest instead of replaying the full waveform under another name.
     */
    if (mode != TINY_EPD_REFRESH_FULL || rect != NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }

    {
        tiny_epd_jd7601_state_t *ctx = epd_jd7601_state(epd);

        /* 运行时切换过温度/波形段：先复位并重新锁定，再写帧。 */
        if (ctx != NULL && ctx->temp_dirty) {
            ret = epd_jd7601_relock(epd);
            if (ret != TINY_EPD_OK) {
                return ret;
            }
        }
    }

    ret = epd_jd7601_write_frame(epd);
    if (ret != TINY_EPD_OK) {
        return ret;
    }
    return epd_jd7601_panel_refresh(epd);
}

static int epd_jd7601_sleep(tiny_epd_t *epd, tiny_epd_sleep_mode_t mode)
{
    if (mode == TINY_EPD_SLEEP_AUTO) {
        mode = TINY_EPD_SLEEP_DEEP;
    }
    if (mode != TINY_EPD_SLEEP_DEEP) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    /* Vendor deep sleep. The refresh sequence has already issued POF (0x02). */
    return epd_jd7601_cmd_data1(epd, 0x07u, 0xA5u);
}

/*
 * JD7601 E6 RAM codes: BLACK=0x0 WHITE=0x1 YELLOW=0x2 RED=0x3 BLUE=0x5
 * GREEN=0x6. 0x4 and 0x7..0xF are not defined by the controller, which is why
 * the palette has six entries and ORANGE is deliberately absent.
 */
static const tiny_epd_palette_entry_t g_tiny_epd_jd7601_palette[] = {
    {TINY_EPD_COLOR_BLACK,  0x0u, 0x00000000u},
    {TINY_EPD_COLOR_WHITE,  0x1u, 0x00FFFFFFu},
    {TINY_EPD_COLOR_YELLOW, 0x2u, 0x00FFFF00u},
    {TINY_EPD_COLOR_RED,    0x3u, 0x00FF0000u},
    {TINY_EPD_COLOR_BLUE,   0x5u, 0x000000FFu},
    {TINY_EPD_COLOR_GREEN,  0x6u, 0x0000FF00u}
};

static const tiny_epd_surface_desc_t g_tiny_epd_jd7601_surface = {
    TINY_EPD_SURFACE_INDEX4,
    4,
    1,
    (uint16_t)(sizeof(g_tiny_epd_jd7601_palette) /
               sizeof(g_tiny_epd_jd7601_palette[0])),
    TINY_EPD_COLOR_WHITE,
    g_tiny_epd_jd7601_palette
};

static const tiny_epd_driver_t g_tiny_epd_jd7601_driver = {
    "jd7601_3in7_480x720_e6",
    TINY_EPD_JD7601_WIDTH,
    TINY_EPD_JD7601_HEIGHT,
    4,
    1,
    /* COLOR_7 is the multi-pigment family flag; the real colour count is the
     * palette above (6 of the 7 logical colours). */
    TINY_EPD_CAP_REFRESH_FULL |
        TINY_EPD_CAP_SLEEP_DEEP |
        TINY_EPD_CAP_COLOR_7,
    sizeof(tiny_epd_jd7601_state_t),
    epd_jd7601_init,
    epd_jd7601_refresh,
    epd_jd7601_sleep,
    &g_tiny_epd_jd7601_surface
};

const tiny_epd_driver_t *tiny_epd_driver_jd7601(void)
{
    return &g_tiny_epd_jd7601_driver;
}

int tiny_epd_jd7601_set_drf(tiny_epd_t *epd, uint8_t drf)
{
    tiny_epd_jd7601_state_t *ctx;

    if (epd == NULL || epd->driver != &g_tiny_epd_jd7601_driver) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ctx = epd_jd7601_state(epd);
    if (ctx == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ctx->drf = drf;
    ctx->drf_ready = 1;
    return TINY_EPD_OK;
}

int tiny_epd_jd7601_get_drf(const tiny_epd_t *epd, uint8_t *drf)
{
    const tiny_epd_jd7601_state_t *ctx;

    if (epd == NULL || drf == NULL || epd->driver != &g_tiny_epd_jd7601_driver) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ctx = (const tiny_epd_jd7601_state_t *)tiny_epd_driver_state_const(epd);
    *drf = (ctx != NULL && ctx->drf_ready) ? ctx->drf
                                           : (uint8_t)TINY_EPD_JD7601_DRF_PARAM;
    return TINY_EPD_OK;
}

/*
 * JD7601 温度锁定值（命令 0xE6）。原厂《3D7E6 调用快刷说明》：IC 内烧入 10 个
 * 温度段（0~50℃，5 度一段），0~45℃ 段是全刷波形，45~50℃ 段是快刷波形，把
 * 0xE6 锁到 48 就调用快刷波形。设置后下一次 refresh 会先复位并重新锁定温度。
 */
int tiny_epd_jd7601_set_temp(tiny_epd_t *epd, uint8_t temp)
{
    tiny_epd_jd7601_state_t *ctx;

    if (epd == NULL || epd->driver != &g_tiny_epd_jd7601_driver) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ctx = epd_jd7601_state(epd);
    if (ctx == NULL) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ctx->temp = temp;
    ctx->temp_ready = 1;
    ctx->temp_dirty = 1;
    return TINY_EPD_OK;
}

int tiny_epd_jd7601_set_fast(tiny_epd_t *epd, int fast)
{
    return tiny_epd_jd7601_set_temp(epd, fast ? (uint8_t)TINY_EPD_JD7601_TEMP_FAST
                                              : (uint8_t)TINY_EPD_JD7601_TEMP_FULL);
}

int tiny_epd_jd7601_get_temp(const tiny_epd_t *epd, uint8_t *temp)
{
    const tiny_epd_jd7601_state_t *ctx;

    if (epd == NULL || temp == NULL || epd->driver != &g_tiny_epd_jd7601_driver) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    ctx = (const tiny_epd_jd7601_state_t *)tiny_epd_driver_state_const(epd);
    *temp = (ctx != NULL && ctx->temp_ready) ? ctx->temp
                                             : (uint8_t)TINY_EPD_JD7601_TEMP_FULL;
    return TINY_EPD_OK;
}
