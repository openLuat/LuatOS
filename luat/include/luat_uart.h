#ifndef LUAT_UART_H
#define LUAT_UART_H

#include "luat_base.h"
#include "luat_uart_legacy.h"
/**
 *@version V1.0
 *@attention
 *上报接收数据中断的逻辑：
 * 1.串口初始化时，新建一个缓冲区
 * 2.可以考虑多为用户申请几百字节的缓冲长度，用户处理时防止丢包
 * 3.每次串口收到数据时，先存入缓冲区，记录长度
 * 4.遇到以下情况时，再调用串口中断
    a)缓冲区满（帮用户多申请的的情况）/缓冲区只剩几百字节（按实际长度申请缓冲区的情况）
    b)收到fifo接收超时中断（此时串口数据应该是没有继续收了）
 * 5.触发收到数据中断时，返回的数据应是缓冲区的数据
 * 6.关闭串口时，释放缓冲区资源
 */
/**
 * @ingroup luatos_device 外设接口
 * @{
 */
/**
 * @defgroup luatos_device_uart UART接口
 * @{
 */

/**
 * @brief 校验位
 */
#define LUAT_PARITY_NONE                     0  /**< 无校验 */
#define LUAT_PARITY_ODD                      1  /**< 奇校验 */
#define LUAT_PARITY_EVEN                     2  /**< 偶校验 */

/**
 * @brief 高低位顺序
 */
#define LUAT_BIT_ORDER_LSB                   0  /**< 低位有效 */
#define LUAT_BIT_ORDER_MSB                   1  /**< 高位有效 */

/**
 * @brief 停止位
 */
#define LUAT_0_5_STOP_BITS                   0xf0   /**< 0.5 */
#define LUAT_1_5_STOP_BITS                   0xf1   /**< 1.5 */

#define LUAT_VUART_ID_0						0x20    

#define LUAT_UART_RX_ERROR_DROP_DATA		(0xD6)
#define LUAT_UART_DEBUG_ENABLE				(0x3E)
/**
 * @brief luat_uart
 */
typedef struct luat_uart {
    int id;                     /**< 串口id */
    int baud_rate;              /**< 波特率 */

    uint8_t data_bits;          /**< 数据位 */
    uint8_t stop_bits;          /**< 停止位 */
    uint8_t bit_order;          /**< 高低位 */
    uint8_t parity;             /**< 奇偶校验位 */

    size_t bufsz;               /**< 接收数据缓冲区大小 */
    uint32_t pin485;            /**< 转换485的pin, 如果没有则是0xffffffff*/
    uint32_t delay;             /**< 485翻转延迟时间，单位us */
    uint8_t rx_level;           /**< 接收方向的电平 */
    uint8_t debug_enable;		/**< 是否开启debug功能 ==LUAT_UART_DEBUG_ENABLE开启，其他不开启 */
    uint8_t error_drop;			/**< 遇到错误是否放弃数据 ==LUAT_UART_RX_ERROR_DROP_DATA 放弃，其他不放弃*/
} luat_uart_t;

/**
 * @brief uart初始化
 * 
 * @param uart luat_uart结构体
 * @return int 
 */
int luat_uart_setup(luat_uart_t* uart);

/**
 * @brief 串口写数据
 * 
 * @param uart_id 串口id
 * @param data 数据
 * @param length 数据长度
 * @return int 
 */
int luat_uart_write(int uart_id, void* data, size_t length);

/**
 * @brief 串口读数据
 * 
 * @param uart_id 串口id
 * @param buffer 数据
 * @param length 数据长度
 * @return int 
 */
int luat_uart_read(int uart_id, void* buffer, size_t length);

/**
 * @brief 清除uart的接收缓存数据
 * @return int
 */
void luat_uart_clear_rx_cache(int uart_id);

/**
 * @brief 关闭串口
 * 
 * @param uart_id 串口id
 * @return int 
 */
int luat_uart_close(int uart_id);

/**
 * @brief 检测串口是否存在
 * 
 * @param uart_id 串口id
 * @return int 
 */
int luat_uart_exist(int uart_id);

/**
 * @brief 串口控制参数
 */
typedef enum LUAT_UART_CTRL_CMD
{
    LUAT_UART_SET_RECV_CALLBACK,/**< 接收回调 */
    LUAT_UART_SET_SENT_CALLBACK,/**< 发送回调 */
	LUAT_UART_SET_RTS_STATE,/**< 设置RTS状态 */
	LUAT_UART_GET_CTS_STATE,/**< 获取CTS状态 */
}LUAT_UART_CTRL_CMD_E;

/**
 * @brief 接收回调函数
 * 
 */
typedef void (*luat_uart_recv_callback_t)(int uart_id, uint32_t data_len);

/**
 * @brief 发送回调函数
 * 
 */
typedef void (*luat_uart_sent_callback_t)(int uart_id, void *param);

/**
 * @brief 发送回调函数
 * @param state 1 cts拉高 0 cts拉低
 */
typedef void (*luat_uart_cts_callback_t)(int uart_id, uint32_t state);

/**
 * @brief 串口控制参数
 * 
 */
typedef struct luat_uart_ctrl_param
{
    luat_uart_recv_callback_t recv_callback_fun;/**< 接收回调函数 */
    luat_uart_sent_callback_t sent_callback_fun;/**< 发送回调函数 */
    luat_uart_cts_callback_t  cts_callback_fun;/**< CTS状态变更回调函数 */
}luat_uart_ctrl_param_t;

/**
 * @brief 串口控制
 * 
 * @param uart_id 串口id
 * @param cmd 串口控制命令
 * @param param 串口控制参数
 * @return int 
 */
int luat_uart_ctrl(int uart_id, LUAT_UART_CTRL_CMD_E cmd, void* param);

/**
 * @brief 开关串口硬件流控,Air780E暂不支持
 *
 * @param uart_id 串口id
 * @param cts_callback_fun CTS状态回调函数，如果设置为NULL，则关闭硬件流控功能
 * @return int < 0失败
 */
int luat_uart_setup_flow_ctrl(int uart_id, luat_uart_cts_callback_t  cts_callback_fun);

/**
 * @brief 串口复用函数，目前支持UART0，UART2，仅适用于Air780E
 *
 * @param uart_id 串口id
 * @param use_alt_type 如果为1，UART0，复用到GPIO16,GPIO17;UART2复用到GPIO12 GPIO13
 * @return int 0 失败，其他成功
 */
int luat_uart_pre_setup(int uart_id, uint8_t use_alt_type);

#ifdef LUAT_USE_SOFT_UART
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
/**
 * @brief 软件串口所需硬件定时器配置
 *
 * @param hwtimer_id 硬件定时器id
 * @param callback 定时回调，如果为NULL，则为释放定时器资源
 * @return int 成功返回0，其他值则为失败
 */
int luat_uart_soft_setup_hwtimer_callback(int hwtimer_id, CommonFun_t callback);
void luat_uart_soft_gpio_fast_output(int pin, uint8_t value);
uint8_t luat_uart_soft_gpio_fast_input(int pin);
void luat_uart_soft_gpio_fast_irq_set(int pin, uint8_t onoff);
/**
 * @brief 软件串口所需硬件定时周期
 *
 * @param baudrate 波特率
 * @return uint32_t 计算到的定时周期
 */
uint32_t luat_uart_soft_cal_baudrate(uint32_t baudrate);
/**
 * @brief 软件串口所需硬件定时器开关
 *
 * @param hwtimer_id 硬件定时器id
 * @param period 定时周期，通过luat_uart_soft_cal_baudrate计算
 * @return int 成功返回0，其他值则为失败
 */
void luat_uart_soft_hwtimer_onoff(int hwtimer_id, uint32_t period);

void luat_uart_soft_sleep_enable(uint8_t is_enable);
#endif

int luat_uart_wait_485_tx_done(int uartid);

/** @}*/
/** @}*/
#endif
