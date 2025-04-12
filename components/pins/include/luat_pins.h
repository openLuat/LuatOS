
#ifndef LUAT_PIN_H
#define LUAT_PIN_H
#include "luat_mcu.h"


typedef enum
{
	LUAT_PIN_UART_RX,
	LUAT_PIN_UART_TX,
	LUAT_PIN_UART_RTS,
	LUAT_PIN_UART_CTS,
	LUAT_PIN_UART_QTY,
	LUAT_PIN_I2C_SCL = 0,
	LUAT_PIN_I2C_SDA,
	LUAT_PIN_I2C_QTY,
	LUAT_PIN_SPI_MOSI = 0,
	LUAT_PIN_SPI_MISO,
	LUAT_PIN_SPI_CLK,
	LUAT_PIN_SPI_CS,
	LUAT_PIN_SPI_QTY,
	LUAT_PIN_PWM_P = 0,
	LUAT_PIN_PWM_N,
	LUAT_PIN_PWM_QTY,
	LUAT_PIN_CAN_RX = 0,
	LUAT_PIN_CAN_TX,
	LUAT_PIN_CAN_STB,
	LUAT_PIN_CAN_QTY,
	LUAT_PIN_I2S_MOSI = 0,
	LUAT_PIN_I2S_MISO,
	LUAT_PIN_I2S_BCLK,
	LUAT_PIN_I2S_LRCLK,
	LUAT_PIN_I2S_MCLK,
	LUAT_PIN_I2S_QTY,
	LUAT_PIN_SDIO_DATA0 = 0,
	LUAT_PIN_SDIO_DATA1,
	LUAT_PIN_SDIO_DATA2,
	LUAT_PIN_SDIO_DATA3,
	LUAT_PIN_SDIO_CMD,
	LUAT_PIN_SDIO_CLK,
	LUAT_PIN_SDIO_QTY,

	LUAT_PIN_ONLY_ONE_QTY = 1,
	LUAT_PIN_FUNCTION_MAX = LUAT_PIN_SDIO_QTY,
	LUAT_PIN_ALT_FUNCTION_MAX = 8,
}LUAT_PIN_FUNC_E;

typedef struct
{
	uint8_t uid;	//用于硬件操作所需的唯一ID
	uint8_t altfun_id;	//复用功能id
}luat_pin_iomux_info;	//pin复用信息

typedef union
{
	struct
	{
		uint16_t function_id:4;
		uint16_t peripheral_id:4;
		uint16_t peripheral_type:5;
		uint16_t is_no_use:1;
	};
	uint16_t code;
}luat_pin_peripheral_function_description_u;

typedef struct
{
	uint16_t function_code[LUAT_PIN_ALT_FUNCTION_MAX];
	uint16_t index;
	uint8_t uid;
}luat_pin_function_description_t;


typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_UART_QTY];
}luat_uart_pin_iomux_t;

typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_I2C_QTY];
}luat_i2c_pin_iomux_t;

typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_SPI_QTY];
}luat_spi_pin_iomux_t;

typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_PWM_QTY];
}luat_pwm_pin_iomux_t;

typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_CAN_QTY];
}luat_can_pin_iomux_t;

typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_I2S_QTY];
}luat_i2s_pin_iomux_t;

typedef struct
{
	luat_pin_iomux_info pin_list[LUAT_PIN_SDIO_QTY];
}luat_sdio_pin_iomux_t;


/**
 * @brief 获取某种外设的全部pin复用信息
 * @param type 外设类型，见LUAT_MCU_PERIPHERAL_E
 * @param id 外设id，例如uart2就填2
 * @param pin_list 输出pin复用信息表
 * @return 0成功，其他失败
 */
int luat_pin_get_iomux_info(LUAT_MCU_PERIPHERAL_E type, uint8_t id, luat_pin_iomux_info *pin_list);
/**
 * @brief 设置某个外设的全部pin复用信息，如果该外设只有一种复用可能性，则不必设置，会直接失败
 * @param type 外设类型，见LUAT_MCU_PERIPHERAL_E
 * @param id 外设id，例如uart2就填2
 * @param pin_list 输入pin复用信息表
 * @return 0成功，其他失败
 */
int luat_pin_set_iomux_info(LUAT_MCU_PERIPHERAL_E type, uint8_t id, luat_pin_iomux_info *pin_list);
/**
 * @brief 从模块pin脚号返回芯片pin功能的详细描述
 * @param num 模块pin脚号
 * @param pin_function 芯片pin功能的详细描述
 * @return 0成功，其他失败
 */
int luat_pin_get_description_from_num(uint32_t num, luat_pin_function_description_t *pin_function);

/**
 * @brief 从芯片pin功能的详细描述找出所需功能的altfun_id
 * @param code 功能id
 * @param pin_function 芯片pin功能的详细描述
 * @return 0xff失败，其他成功
 */
uint8_t luat_pin_get_altfun_id_from_description(uint16_t code, luat_pin_function_description_t *pin_function);

void luat_pin_iomux_config(luat_pin_iomux_info pin, uint8_t use_altfunction_pull, uint8_t driver_strength);

void luat_pin_iomux_print(luat_pin_iomux_info *pin_list, uint8_t num);

int luat_pins_load_from_file(const char* path);

int luat_pins_setup(uint16_t pin, const char* func_name, size_t name_len, int altfun_id);

#endif
