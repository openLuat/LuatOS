#ifndef LUAT_CAMERA_H
#define LUAT_CAMERA_H

#include "luat_base.h"

typedef struct luat_camera_conf
{
    uint8_t id;
    uint8_t port_type;
    uint8_t port_id;
    uint8_t color_bit;
    uint8_t pin_sel;
    uint8_t pin_rst;
    char type_name[16];
}luat_camera_conf;


int luat_camera_init(luat_camera_conf* conf);

int luat_camera_close(int id);

#endif
