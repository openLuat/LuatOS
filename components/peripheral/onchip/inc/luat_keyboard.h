#ifndef LUAT_KEYBOARD_H
#define LUAT_KEYBOARD_H
#include "luat_base.h"

typedef struct luat_keyboard_ctx
{
    uint16_t port;      // 为多keyboard预留,默认为0
    uint16_t pin_data;  // pin数据, 需要根据pin_map反推按键
    uint32_t state;     // 1 pressed, 0 release
    void* userdata;
}luat_keyboard_ctx_t;

typedef void(*luat_keyboard_irq_cb)(luat_keyboard_ctx_t* ctx);

typedef struct luat_keyboard_conf {
    uint16_t port;       // 为多keyboard预留,默认为0
    uint16_t pin_conf;   // 需要启用的pin的掩码
    uint16_t pin_map;    // 需要启用的pin的输入/输出配置
    uint16_t debounce;   // 消抖配置
    luat_keyboard_irq_cb cb;
    void* userdata;
}luat_keyboard_conf_t;

int luat_keyboard_init(luat_keyboard_conf_t *conf);

int luat_keyboard_deinit(luat_keyboard_conf_t *conf);
#endif
