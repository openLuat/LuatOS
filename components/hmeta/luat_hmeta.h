#ifndef LUAT_HMETA_H
#define LUAT_HMETA_H


// 获取模块的设备类型, 原始需求是区分Air780E和Air600E
int luat_hmeta_model_name(char* buff);


// -------------------------------------------------------
//             GPIO 元数据
// -------------------------------------------------------
typedef struct luat_hmeta_gpio_pin
{
    uint16_t id;            // GPIO编号
    // const char* name;    // 管脚名称
    uint8_t pull_up : 1;    // 支持上拉
    uint8_t pull_down: 1;   // 支持下拉
    uint8_t pull_open: 1;   // 支持开漏
    uint8_t irq_rasing:1;   // 支持上升沿中断
    uint8_t irq_falling:1;  //支持下降沿中断
    uint8_t irq_both   :1;  // 支持双向触发
    uint8_t irq_high   :1;  // 支持高电平触发
    uint8_t irq_low   :1;  // 支持低电平触发
    uint8_t volsel;         // 电压范围
    const char* commet;     // 备注信息
}luat_hmeta_gpio_pin_t;

typedef struct luat_hmeta_gpio
{
    size_t count;      // 总共有多少管脚
    const char* comment;   // 总体备注
    const luat_hmeta_gpio_pin_t pins;
}luat_hmeta_gpio_t;

const luat_hmeta_gpio_t* luat_hmeta_gpio_get(void);

// -------------------------------------------------------
//             UART 元数据
// -------------------------------------------------------
typedef struct luat_hmeta_uart_port
{
    uint16_t id;            // UART编号
    uint16_t pins[2];       // 对应的GPIO, 如果有的话
    uint16_t baudrates[16]; // 可用的波特率,0会自动跳过
    const char* commet;     // 备注信息
}luat_hmeta_uart_port_t;

typedef struct luat_hmeta_uart
{
    size_t count;      // 总共有多少管脚
    const char* comment;   // 总体备注
    const luat_hmeta_uart_port_t ports;
}luat_hmeta_uart_t;

const luat_hmeta_uart_t* luat_hmeta_uart_get(void);

// TODO i2c/spi/pwm/adc的 元数据

#endif
