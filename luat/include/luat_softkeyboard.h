#ifndef LUAT_KEYBOARD_H
#define LUAT_KEYBOARD_H
#include "luat_base.h"

typedef struct luat_softkeyboard_conf {
    uint8_t port;       // 预留port
    uint8_t inio_num;
    uint8_t outio_num;
    uint8_t* inio;      
    uint8_t* outio;     
    void* userdata;
}luat_softkeyboard_conf_t;

int l_softkeyboard_handler(lua_State *L, void* ptr);
int luat_softkeyboard_init(luat_softkeyboard_conf_t *conf);
int luat_softkeyboard_deinit(luat_softkeyboard_conf_t *conf);

#endif
