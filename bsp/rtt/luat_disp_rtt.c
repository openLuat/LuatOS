
#include "luat_disp.h"
#include "rtthread.h"

#ifdef PKG_USING_U8G2
#include "u8g2_port.h"

#define LUAT_LOG_TAG "disp"
#include "luat_log.h"

uint8_t luat_u8x8_gpio_and_delay(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);

int luat_disp_setup(luat_disp_conf_t *conf) {
    
    LLOGD("setup disp@rtt pinType=%ld", conf->pinType);
    u8g2_t* u8g2 = (u8g2_t*)conf->ptr;
    if (conf->pinType == 1) {
        u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, u8x8_byte_sw_i2c, luat_u8x8_gpio_and_delay);
        // u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, u8x8_byte_sw_i2c, u8x8_rt_gpio_and_delay);
        u8g2->u8x8.pins[U8X8_PIN_I2C_CLOCK] = conf->pin0;
        u8g2->u8x8.pins[U8X8_PIN_I2C_DATA] = conf->pin1;
        LLOGD("setup disp i2c.sw SCL=%ld SDA=%ld", conf->pin0, conf->pin1);
    }
    else {
        u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, u8x8_byte_rt_hw_i2c, u8x8_rt_gpio_and_delay);
    }
    u8g2_InitDisplay(u8g2);
    u8g2_SetPowerSave(u8g2, 0);
    return 0;
}
#endif
