/**
 * @file hw_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 通用硬件外设操作，包括uart，ADC，gpio，spi，i2c，hw_timer，lp_timer等等
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __HW_API_H__
#define __HW_API_H__
#include "api_config.h"

/**
 * @brief 硬件通讯总线类型
 * 
 */
enum LUATOS_HW_BUS_TYPE
{
    LUATOS_HW_BUS_GPIO,
    LUATOS_HW_BUS_TIM,                          /// < 高精度定时器/捕获器，目前用于STM32
    LUATOS_HW_BUS_ADC,
    LUATOS_HW_BUS_PWM,
    LUATOS_HW_BUS_UART,
    LUATOS_HW_BUS_I2C,
    LUATOS_HW_BUS_SPI,
    LUATOS_HW_BUS_CAN,                          /// < CAN暂时不用
    LUATOS_HW_BUS_USB,                          /// < USB暂时不用
    LUATOS_HW_BUS_SDIO,                         /// < SDIO暂时不用
    LUATOS_HW_BUS_FSMC,                         /// < 外部存储器接口，SRAM，PSRAM，并行NOR/NAND
};

/**
 * @brief 可接收外部数据的通讯总线接收数据通知方式，可以多选
 * 
 */
enum LUATOS_HW_BUS_RX_MODE
{
    LUATOS_HW_BUS_RX_NEW_ONCE = 0x00,           /// < 有新数据，且缓冲区没有数据时，通知一次，如果没有其他选项，默认启用
    LUATOS_HW_BUS_RX_NEW_CONTINUE = 0x01,       /// < 有新数据就通知回调一次
    LUATOS_HW_BUS_RX_DONE = 0x02,               /// < 接收完成后通知回调一次，对应stm32的idle irq，rda8955的rxDmaTimeout irq
};

/**
 * @brief gpio 中断类型
 * 
 */
enum LUATOS_HW_GPIO_IRQ_TYPE
{
    LUATOS_HW_GPIO_IRQ_RISING = 0x01,
    LUATOS_HW_GPIO_IRQ_FALLING = 0x02,
    LUATOS_HW_GPIO_IRQ_HIGH_LEVEL = 0x10,
    LUATOS_HW_GPIO_IRQ_LOW_LEVEL = 0x20,
};


typedef struct LUATOS_TIME_STRUCT
{
	uint8_t sec;
	uint8_t min;
	uint8_t hour;
	uint8_t week;//表示日期0~6,sun~sat，表示预约时，bit0~bit6,sun~sat
}luatos_time_struct;

typedef struct LUATOS_DATE_STRUCT
{
	uint16_t year;
	uint8_t mon;
	uint8_t day;
}luatos_date_struct;

typedef union LUATOS_TIME_UNION
{
	uint32_t dwtime;
	luatos_time_struct time;
}luatos_time_union;

typedef union LUATOS_DATE_UNION
{
	uint32_t dwdate;
	luatos_date_struct date;
}luatos_date_union;

/**
 * @brief gpio id
 * 
 */
typedef struct LUATOS_HW_GPIO_ID
{
    u32 port;                                       /// < bit0~bit31，代表port0~port31，或者portA，portB...
    u32 pin;                                        /// < bit0~bit31, 代表PIN0~PIN31
}luatos_hw_gpio_id_t;

/**
 * @brief gpio初始化成员变量
 * 
 */
typedef struct LUATOS_HW_GPIO_CONFIG
{
    luatos_hw_gpio_id_t id;                         /// < GPIO ID
    void (*irq)(luatos_hw_gpio_id_t id, u8 type);   /// < 中断回调，如果不为空，且is_input为真，则启动中断功能
    u8 is_input;                                    /// < 是否为输入型 1是 0否
    u8 init_value;                                  /// < 初始输出电平 1高 0低
    u8 irq_rising;                                  /// < 上升沿或者高电平中断 1启用 0不启用
    u8 irq_falling;                                 /// < 下降沿或者低电平中断 1启用 0不启用
    u8 irq_level;                                   /// < 边沿或者电平中断 1电平 0边沿
    u8 debounce;                                    /// < 中断去抖动 0不启用 其他为过滤时间，单位ms
}luatos_hw_gpio_config_t;

/**
 * @brief adc
 * 
 */
typedef struct LUATOS_HW_ADC_CONFIG
{
    void (*done_cb)(u8 bus_id, u32 raw_value);  /// < 转换完成通知回调
    void *sdk_config;                           /// < SDK的特殊配置，一般填NULL，让SDK自动控制
    u8 id;                                      /// < ADC通道ID 0，1，2...
}luatos_hw_adc_config_t;

/**
 * @brief 高精度定时器
 * 
 */
typedef struct LUATOS_HW_TIM_CONFIG
{
    void (*done_cb)(u8 bus_id);                 /// < 转换完成通知回调
    void *sdk_config;                           /// < SDK的特殊配置，一般填NULL，让SDK自动控制
    u32 ns_time;                                /// < 定时时间，单位ns，最多4秒
    u8 id;                                      /// < 定时通道ID 0，1，2...
}luatos_hw_tim_config_t;

/**
 * @brief pwm
 * 
 */
typedef struct LUATOS_HW_PWM_CONFIG
{
    u32 freq;                                   /// < 频率
    u16 duty;                                   /// < 占空比
    u8 polarity;                                /// < 空闲时的电平，1高，0低
    u8 id;                                      /// < PWM通道ID 0，1，2...
}luatos_hw_PWM_config_t;

/**
 * @brief 串口初始化成员变量
 * 
 */
typedef struct LUATOS_HW_UART_CONFIG
{
    u32 br;                                     /// < 波特率
    u32 tx_cache_len;                           /// < 发送缓冲区大小
    u32 rx_cache_len;                           /// < 接收缓冲区大小
    void (*tx_done_cb)(u8 bus_id);              /// < 发送完成回调
    void (*new_rx_cb)(u8 bus_id);               /// < 新接收数据通知回调
    void (*rx_done_cb)(u8 bus_id);              /// < 接收数据完成通知回调，表明在一定时间内没有新的数据了
    u8 id;                                      /// < 串口序号 0，1，2，3...
    u8 data_bits;                               /// < 数据位 5，6，7，8，9
    u8 stop_bits;                               /// < 停止位 0=1bit，1=1.5bit，2=2bit
    u8 parity;                                  /// < 校验位 0=不校验，1=奇校验，2=偶校验
    u8 work_mode;                               /// < 工作模式 0=全双工，1=ISO7816智能卡，2=IrDA
    u8 rx_mode;                                 /// < 数据接收通知模式，见LUATOS_HW_BUS_RX_MODE
}luatos_hw_uart_config_t;

/**
 * @brief I2C初始化成员变量
 * 
 */
typedef struct LUATOS_HW_I2C_CONFIG
{
    void (*done_cb)(u8 bus_id, u8 is_read);     /// < 主机模式下收发完成通知回调，从机模式下接收到主机收发数据请求
    u32 freq;                                   /// < 期望的总线频率，单位Hz
    u16 address;                                /// < 主机模式下，默认外设地址，从机模式下自身地址
    u8 id;                                      /// < I2C序号 0，1，2，3...
    u8 slave_mode;                              /// < 从机模式
}luatos_hw_I2C_config_t;

/**
 * @brief SPI初始化成员变量
 * 
 */
typedef struct LUATOS_HW_SPI_CONFIG
{
    void (*done_cb)(u8 bus_id, u8 is_read);     /// < 主机模式下收发完成通知回调，从机模式下接收到主机收发数据请求
    u32 freq;                                   /// < 期望的总线频率，单位Hz
    u8 id;                                      /// < SPI序号 0，1，2，3...
    u8 slave_mode;                              /// < 从机模式
    u8 data_bit;                                /// < 数据位 8，16
    u8 bit_sequence;                            /// < 数据位顺序 1 LSB先 0 MSB先
    u8 work_mode;                               /// < 工作模式，0~3 对应标准的MODE0~MODE3
}luatos_hw_spi_config_t;

/**
 * @brief 总线初始化配置集合
 * 
 */
typedef union LUATOS_HW_BUS_CONFIG
{
    luatos_hw_gpio_config_t gpio;
    luatos_hw_adc_config_t  adc;
    luatos_hw_tim_config_t  tim;
    luatos_hw_PWM_config_t  pwm;
    luatos_hw_uart_config_t uart;
    luatos_hw_I2C_config_t  I2C;
    luatos_hw_spi_config_t  spi;
}luatos_hw_bus_config_t;

typedef union LUATOS_HW_BUS_ID
{
    luatos_hw_gpio_id_t gpio_id;
    u8 id;
}luatos_hw_bus_id_t;

/**
 * @brief 硬件外设在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_hw_init(void);

/**
 * @brief 创建一个非高精度定时器
 * 
 * @note 允许在时间到时，回调函数或者任务通知，回调函数优先，无回调函数情况下，才任务通知
 * @param callback_entry_address 定时器时间到，回调函数入口地址，和回调通知任务不能同时用
 * @param task_handle 定时器时间到，回调通知的任务，和回调函数不能同时用
 * @param timer_param 定时器回调参数，返回给回调函数，或者发送luatos_message_t.param2给task
 * @param timeout_ms 定时器时间，单位ms
 * @param repeat 是否重复运行，1是，0否
 * @param lowpower_mode 是否可以在低功耗模式下运行, 1可以，0不可以
 * @return LUATOS_HANDLE 返回一个定时器句柄，失败返回NULL
 */
LUATOS_HANDLE luatos_hw_create_timer(
    u32 callback_entry_address, LUATOS_HANDLE task_handle, u32 timer_param, u32 timeout_ms, u8 repeat, u8 lowpower_mode);

/**
 * @brief 销毁一个非高精度定时器
 * 
 * @param timer_handle 定时器句柄
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_destory_timer(LUATOS_HANDLE timer_handle);

/**
 * @brief 启动一个非高精度定时器
 * 
 * @param timer_handle 
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_start_timer(LUATOS_HANDLE timer_handle);

/**
 * @brief 停止一个非高精度定时器
 * 
 * @param timer_handle 
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_stop_timer(LUATOS_HANDLE timer_handle);

/**
 * @brief 停止同一个回调函数的所有非高精度定时器
 * 
 * @param callback_entry_address 回调函数入口地址
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_stop_callback_timers(u32 callback_entry_address);

/**
 * @brief 打开一条硬件总线，并按照配置初始化
 * 
 * @param type 总线类型
 * @param config 初始化的配置
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_bus_open(LUATOS_HW_BUS_TYPE type, luatos_hw_bus_config_t *config);

/**
 * @brief 关闭一条硬件总线
 * 
 * @param type 总线类型
 * @param bus_id 总线id
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_bus_close(LUATOS_HW_BUS_TYPE type, luatos_hw_bus_id_t bus_id);

/**
 * @brief 对一条硬件总线读数据
 * 
 * @param type 总线类型
 * @param bus_id 总线id
 * @param buf 读取数据缓存
 * @param len 期望读取数据长度
 * @param [OUT]read_len 实际读取数据长度
 * @param flags 读取控制标志，根据总线类型决定
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_bus_read(LUATOS_HW_BUS_TYPE type, luatos_hw_bus_id_t bus_id, void *buf, u32 len, u32 *read_len, u32 flags);

/**
 * @brief 对一条硬件总线写数据
 * 
 * @param type 总线类型
 * @param bus_id 总线id
 * @param buf 写入数据缓存
 * @param len 期望写入数据的长度
 * @param [OUT]write_len 实际写入数据长度
 * @param flags 写入控制标志，根据总线类型决定
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_bus_write(LUATOS_HW_BUS_TYPE type, luatos_hw_bus_id_t bus_id, const void *buf, u32 len, u32 *write_len, u32 flags);

/**
 * @brief 对一条硬件总线进行IO控制
 * 
 * @param type 总线类型
 * @param bus_id 总线id
 * @param cmd IO控制命令
 * @param param IO控制参数
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_bus_ioctrl(LUATOS_HW_BUS_TYPE type, luatos_hw_bus_id_t bus_id, u32 cmd, u32 param);

/**
 * @brief 获取rtc时间，utc时间戳形式
 * 
 * @return u64 utc时间戳的ms数
 */
u64 luatos_hw_get_rtc_tamp(void);

/**
 * @brief 获取rtc时间，utc时间
 * 
 * @param date UTC日期
 * @param time UTC时间
 * @param ms UTC时间ms
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_get_rtc_datetime(luatos_date_struct *date, luatos_time_struct *time, u32 *ms);
/**
 * @brief 设置系统运行频率，如果有多个时钟，则修改对luatos运行有影响的时钟
 * 
 * @param clk 频率 =0系统自动决定当前运行频率 其他为期望运行的频率，单位hz
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_set_sys_clk(u32 clk);

/**
 * @brief 获取当前系统运行频率
 * 
 * @return u32 运行的频率，单位hz
 */
u32 luatos_hw_get_sys_clk(void);

/**
 * @brief 低功耗模式设置，由系统决定是否真正进入低功耗
 * 
 * @param on_off 0退出低功耗，1进入低功耗
 * @param level 低功耗级别，目前只对NBIOT有效
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_set_lowpower_sleep(u8 on_off, u8 level);
#endif