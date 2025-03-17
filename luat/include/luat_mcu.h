#ifndef LUAT_MCU_H
#define LUAT_MCU_H
#include "luat_base.h"

enum
{
	LUAT_MCU_PERIPHERAL_UART,
	LUAT_MCU_PERIPHERAL_I2C,
	LUAT_MCU_PERIPHERAL_SPI,
	LUAT_MCU_PERIPHERAL_PWM,
	LUAT_MCU_PERIPHERAL_CAN,
	LUAT_MCU_PERIPHERAL_GPIO,
	LUAT_MCU_PERIPHERAL_I2S,
    LUAT_MCU_PERIPHERAL_SDIO,
	LUAT_MCU_PERIPHERAL_LCD,
	LUAT_MCU_PERIPHERAL_CAMERA,
	LUAT_MCU_PERIPHERAL_ONEWIRE,
};

int luat_mcu_set_clk(size_t mhz);
int luat_mcu_get_clk(void);

const char* luat_mcu_unique_id(size_t* t);

long luat_mcu_ticks(void);
uint32_t luat_mcu_hz(void);

uint64_t luat_mcu_tick64(void);
int luat_mcu_us_period(void);
uint64_t luat_mcu_tick64_ms(void);
void luat_mcu_set_clk_source(uint8_t source_main, uint8_t source_32k, uint32_t delay);

/**
 * @brief 用户是否设置了外设的IOMUX
 * @param type 外设类型 LUAT_MCU_PERIPHERAL_XXX
 * @param sn 外设序号，0~7
 * @return 0 用户配置了 1用户没配置
 */
uint8_t luat_mcu_iomux_is_default(uint8_t type, uint8_t sn);
/**
 * @brief 用户控制外设的IOMUX，如果不配置或者取消，则外设初始化时使用默认配置
 * @param type 外设类型 LUAT_MCU_PERIPHERAL_XXX
 * @param sn 外设序号，0~7
 * @param pad_index pad序号，具体看芯片，可能是GPIO序号，可能是PAD序号。如果是-1，则表示取消配置
 * @param alt 复用功能序号，具体看芯片
 * @param is_input，是否是单纯输入功能
 * @return 无
 */
void luat_mcu_iomux_ctrl(uint8_t type, uint8_t sn, int pad_index, uint8_t alt, uint8_t is_input);

void luat_mcu_set_hardfault_mode(int mode);
/**
 * @brief 外部晶振参考信号输出
 * @param main_enable 主晶振参考信号输出使能，0关闭，其他开启
 * @param slow_32k_enable 慢速（一般是32K）晶振参考信号输出使能，0关闭，其他开启
 * @return 无
 */
void luat_mcu_xtal_ref_output(uint8_t main_enable, uint8_t slow_32k_enable);
#endif

