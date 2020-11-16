
#ifndef LUAT_GPIO
#define LUAT_GPIO


#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdint.h"
#include "luat_msgbus.h"


#define Luat_GPIO_LOW                 0x00
#define Luat_GPIO_HIGH                0x01

#define Luat_GPIO_OUTPUT         0x00
#define Luat_GPIO_INPUT          0x01
#define Luat_GPIO_IRQ            0x02

#define Luat_GPIO_DEFAULT        0x00
#define Luat_GPIO_PULLUP         0x01
#define Luat_GPIO_PULLDOWN       0x02

#define Luat_GPIO_RISING             0x00
#define Luat_GPIO_FALLING            0x01
#define Luat_GPIO_BOTH               0x02

typedef struct luat_gpio
{
    int pin;
    int mode;
    int pull;
    int irq;
    int lua_ref;
    //luat_msg_handler func;
} luat_gpio_t;


void luat_gpio_mode(int pin, int mode, int pull, int initOutput);
int luat_gpio_setup(luat_gpio_t* gpio);
int luat_gpio_set(int pin, int level);
int luat_gpio_get(int pin);
void luat_gpio_close(int pin);

int l_gpio_handler(lua_State *L, void* ptr);

#endif
