
#ifndef LUAT_SYS
#define LUAT_SYS


#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdint.h"


#define LUAT_GPIO_MODE_INPUT 0
#define LUAT_GPIO_MODE_OUTPUT 1
#define LUAT_GPIO_MODE_INT 2

#define LUAT_GPIO_PULL_UP 0
#define LUAT_GPIO_PULL_DOWN 1

#define LUAT_GPIO_INT_UP 1
#define LUAT_GPIO_INT_DOWN 2
#define LUAT_GPIO_INT_BOTH 3

typedef struct luat_gpio_t
{
    int pin;
    int mode;
    int pull;
    void* callback;
} luat_gpio_t;


int luat_gpio_setup(luat_gpio_t gpio);
int luat_gpio_set(luat_gpio_t gpio, int level);
int luat_gpio_get(luat_gpio_t gpio);

#endif