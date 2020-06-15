
#include "luat_disp.h"
#include "rtthread.h"

#ifdef PKG_USING_U8G2
#include "u8g2_port.h"

int luat_disp_setup(luat_disp_conf_t *conf) {
    u8g2_t* u8g2 = (u8g2_t*)conf->ptr;
    u8g2_Setup_ssd1306_i2c_128x64_noname_f( u8g2, U8G2_R0, u8x8_byte_rt_hw_i2c, u8x8_rt_gpio_and_delay);
    u8g2_InitDisplay(u8g2);
    u8g2_SetPowerSave(u8g2, 0);
}
#endif
