/******************************************************************************
 *  CAMERA设备操作抽象层
 *  @author Dozingfiretruck
 *  @since 0.0.1
 *****************************************************************************/
#ifndef Luat_CAMERA_H
#define Luat_CAMERA_H

#include "luat_base.h"
#include "luat_lcd.h"

typedef struct luat_camera_conf
{
    uint8_t id;
    uint8_t zbar_scan;
    uint8_t draw_lcd;
    uint8_t i2c_id;
    uint8_t i2c_addr;
    uint8_t pwm_id;
    size_t pwm_period;
    uint8_t pwm_pulse;
    uint16_t sensor_width;
    uint16_t sensor_height;
    uint8_t color_bit;
    uint8_t id_reg;
	uint8_t id_value;
    size_t init_cmd_size;
    uint8_t *init_cmd;
    luat_lcd_conf_t* lcd_conf;
} luat_camera_conf_t;

int l_camera_handler(lua_State *L, void* ptr);
int luat_camera_init(luat_camera_conf_t *conf);
int luat_camera_start(int id);
int luat_camera_stop(int id);
int luat_camera_close(int id);
int luat_camera_capture(int id, uint8_t quality, const char *path);

#endif
