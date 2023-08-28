
#ifndef LUAT_GPIO_LEGACY_H
#define LUAT_GPIO_LEGACY_H


#include "luat_base.h"
#ifdef __LUATOS__
#include "luat_msgbus.h"
int l_gpio_handler(lua_State *L, void* ptr);
#endif
typedef int (*luat_gpio_irq_cb)(int pin, void* args);


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
#define Luat_GPIO_HIGH_IRQ			0x03	//高电平中断
#define Luat_GPIO_LOW_IRQ			0x04	//低电平中断

#define Luat_GPIO_MAX_ID             255

typedef struct luat_gpio
{
    int pin;/**<引脚*/
    int mode;/**<GPIO模式*/
    int pull;/**<GPIO上下拉模式*/
    int irq;/**<GPIO中断模式*/
    int lua_ref;
    luat_gpio_irq_cb irq_cb;/**<中断处理函数*/
    void* irq_args;
    int alt_func;
} luat_gpio_t;

int luat_gpio_setup(luat_gpio_t* gpio);
void luat_gpio_mode(int pin, int mode, int pull, int initOutput);
int luat_gpio_irq_default(int pin, void* args);

#endif
