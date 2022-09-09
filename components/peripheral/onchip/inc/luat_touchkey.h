
#ifndef LUAT_TOUCHKEY_H
#define LUAT_TOUCHKEY_H

#include "luat_base.h"

typedef struct luat_touchkey_conf
{
    uint8_t id;
    uint8_t scan_period;
    uint8_t window;
    uint8_t threshold;
}luat_touchkey_conf_t;

int luat_touchkey_setup(luat_touchkey_conf_t *conf);

int luat_touchkey_close(uint8_t id);

int l_touchkey_handler(lua_State *L, void* ptr);

#endif
