#include "luat_base.h"
#include "luat_i2c.h"
#include "luat_u8g2.h"
#include "u8g2.h"
#include "luat_sdl2.h"
#include "luat_lcd.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "sysp"
#include "luat_log.h"

static u8g2_t* u8g2;
// static luat_u8g2_conf_t u8g2_conf;
static uint8_t *u8g2_buff;
// static u8x8_display_info_t display_info;
static const u8x8_display_info_t display_info =
{
  /* chip_enable_level = */ 0,
  /* chip_disable_level = */ 1,
  
  /* post_chip_enable_wait_ns = */ 20,
  /* pre_chip_disable_wait_ns = */ 10,
  /* reset_pulse_width_ms = */ 100, 	/* SSD1306: 3 us */
  /* post_reset_wait_ms = */ 100, /* far east OLEDs need much longer setup time */
  /* sda_setup_time_ns = */ 50,		/* SSD1306: 15ns, but cycle time is 100ns, so use 100/2 */
  /* sck_pulse_width_ns = */ 50,	/* SSD1306: 20ns, but cycle time is 100ns, so use 100/2, AVR: below 70: 8 MHz, >= 70 --> 4MHz clock */
  /* sck_clock_hz = */ 8000000UL,	/* since Arduino 1.6.0, the SPI bus speed in Hz. Should be  1000000000/sck_pulse_width_ns */
  /* spi_mode = */ 0,		/* active high, rising edge */
  /* i2c_bus_clock_100kHz = */ 4,
  /* data_setup_time_ns = */ 40,
  /* write_pulse_width_ns = */ 150,	/* SSD1306: cycle time is 300ns, so use 300/2 = 150 */
  /* tile_width = */ 16,
  /* tile_hight = */ 8,
  /* default_x_offset = */ 0,
  /* flipmode_x_offset = */ 0,
  /* pixel_width = */ 128,
  /* pixel_height = */ 64
};

static uint32_t *sdl_buff;

static uint8_t sysp_display_cb(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    //LLOGD("sysp_display_cb %d", msg);

    u8x8_tile_t *titl;
    uint8_t* pixptr = NULL;
    uint8_t pixtmp = 0;

    if (msg == U8X8_MSG_DISPLAY_SETUP_MEMORY) {
        u8x8_d_helper_display_setup_memory(u8x8, &display_info);
        return 1;
    }
    if (msg != U8X8_MSG_DISPLAY_DRAW_TILE) {
        return 0;
    }

    titl = (u8x8_tile_t*)arg_ptr;
    pixptr = titl->tile_ptr;
    int x ;
    int y ;
    LLOGD("u8g2 display arg_int %d", arg_int);
    LLOGD("u8g2 display tile_ptr %p", titl->tile_ptr);
    LLOGD("u8g2 display cnt %d", titl->cnt);
    LLOGD("u8g2 display x_pos %d",  titl->x_pos);
    LLOGD("u8g2 display y_pos %d",  titl->y_pos);

    // 注意, i 并非 y, 是titl的索引
    for (size_t i = 0; i < titl->cnt; i++) {
        for (size_t k = 0; k < 8; k++) {
            // 每个字节是1列
            pixtmp = *pixptr;
            pixptr++;
            x = titl->x_pos * 8 + 8 * i + k;
            for (size_t p = 0; p < 8; p++) {
                y = titl->y_pos * 8 + p;
                //LLOGD("x %d y %d index %d", x, y, y* display_info.pixel_width + x);
                if ((pixtmp >> p) & 0x01) {
                    sdl_buff[y* display_info.pixel_width + x] = 0xFFFFFFFFU;
                }
                else {
                    sdl_buff[y* display_info.pixel_width + x] = 0xFF000000U;
                }
            }
        }
    }
    luat_sdl2_draw(0, 0, display_info.pixel_width - 1, display_info.pixel_height - 1, sdl_buff);
    luat_sdl2_flush();
    return 1;
}

static uint8_t byte_cb (u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    LLOGD("byte_cb %d", msg);
    return 0;
}
static uint8_t gpio_msg_cb (u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    LLOGD("gpio_msg_cb %d", msg);
    return 0;
}

int luat_u8g2_setup(luat_u8g2_conf_t *conf) {
    // memcpy(&u8g2_conf, conf, sizeof(luat_u8g2_conf_t));
    int w = 0, h = 0;
    // 已支持的都是12864分辨率, 那就直接来吧
    w = 128;
    h = 64;

    u8g2_buff = luat_heap_malloc(w*h*16);
    sdl_buff = luat_heap_malloc(w*h*sizeof(uint32_t));
    LLOGD("u8g2_buff %p", u8g2_buff);
    LLOGD("sdl_buff %p",  sdl_buff);

    u8g2 = (u8g2_t*)conf->ptr;
    // display_info.pixel_height = 128;
    // display_info.pixel_width = 64;
    // display_info.default_x_offset = 0;

    u8g2_SetupDisplay(u8g2, sysp_display_cb, u8x8_cad_001, byte_cb, gpio_msg_cb);
    u8g2_SetupBuffer(u8g2, u8g2_buff, 8, u8g2_ll_hvline_vertical_top_lsb, conf->direction);

    luat_sdl2_conf_t sdl2_conf = {
        .width = w,
        .height = h
    };
    luat_sdl2_init(&sdl2_conf);

    return 0;
}