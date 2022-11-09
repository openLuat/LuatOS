
#ifndef LUAT_GPIO_H
#define LUAT_GPIO_H


#include "luat_base.h"
#include "luat_gpio_legacy.h"



#define LUAT_GPIO_LOW                 (Luat_GPIO_LOW)
#define LUAT_GPIO_HIGH                (Luat_GPIO_HIGH)

#define LUAT_GPIO_OUTPUT         (Luat_GPIO_OUTPUT)
#define LUAT_GPIO_INPUT          (Luat_GPIO_INPUT)
#define LUAT_GPIO_IRQ            (Luat_GPIO_IRQ)

#define LUAT_GPIO_DEFAULT        (Luat_GPIO_DEFAULT)
#define LUAT_GPIO_PULLUP         (Luat_GPIO_PULLUP)
#define LUAT_GPIO_PULLDOWN       (Luat_GPIO_PULLDOWN)

#define LUAT_GPIO_RISING_IRQ             (Luat_GPIO_RISING)
#define LUAT_GPIO_FALLING_IRQ            (Luat_GPIO_FALLING)
#define LUAT_GPIO_BOTH_IRQ               (Luat_GPIO_BOTH)
#define LUAT_GPIO_HIGH_IRQ			(Luat_GPIO_HIGH_IRQ)	//高电平中断
#define LUAT_GPIO_LOW_IRQ			(Luat_GPIO_LOW_IRQ)	//低电平中断
#define LUAT_GPIO_NO_IRQ			(0xff)

#define LUAT_GPIO_MAX_ID             (Luat_GPIO_MAX_ID)




typedef struct luat_gpio_cfg
{
    int pin;
    uint8_t mode;
    uint8_t pull;
    uint8_t irq_type;
    uint8_t output_level;
    luat_gpio_irq_cb irq_cb;
    void* irq_args;
    uint8_t alt_fun;
} luat_gpio_cfg_t;
/**
 * @defgroup luatos_device 外设接口
 * @{
 */

/**
 * @defgroup luatos_device_gpio GPIO接口
 * @{
 */

typedef enum
{
	LUAT_GPIO_CMD_SET_PULL_MODE,
	LUAT_GPIO_CMD_SET_IRQ_MODE,
}LUAT_GPIO_CTRL_CMD_E;

void luat_gpio_set_default_cfg(luat_gpio_cfg_t* gpio);
int luat_gpio_open(luat_gpio_cfg_t* gpio);
int luat_gpio_set(int pin, int level);
int luat_gpio_get(int pin);
void luat_gpio_close(int pin);

int luat_gpio_set_irq_cb(int pin, luat_gpio_irq_cb cb, void* args);
// 在同一个GPIO输出一组脉冲, 注意, len的单位是bit, 高位在前.
void luat_gpio_pulse(int pin, uint8_t *level, uint16_t len, uint16_t delay_ns);

int luat_gpio_ctrl(int pin, LUAT_GPIO_CTRL_CMD_E cmd, int param);
/** @}*/
/** @}*/
#endif
