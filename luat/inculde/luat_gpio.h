
#ifndef LUAT_SYS
#define LUAT_SYS


#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdint.h"
#include "luat_msgbus.h"


#define Luat_GPIO_LOW                 0x00
#define Luat_GPIO_HIGH                0x01

#define Luat_GPIO_OUTPUT         0x00
#define Luat_GPIO_INPUT          0x01
#define Luat_GPIO_INPUT_PULLUP   0x02
#define Luat_GPIO_INPUT_PULLDOWN 0x03
#define Luat_GPIO_OUTPUT_OD      0x04

#define Luat_GPIO_RISING             0x00
#define Luat_GPIO_FALLING            0x01
#define Luat_GPIO_RISING_FALLING     0x02

typedef struct luat_gpio_t
{
    int pin;
    int mode;
    luat_msg_handler callback;
    int irqmode;
} luat_gpio_t;


void luat_gpio_mode(int pin, int mode);
int luat_gpio_setup(luat_gpio_t* gpio);
int luat_gpio_set(int pin, int level);
int luat_gpio_get(int pin);

#endif