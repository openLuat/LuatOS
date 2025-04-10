
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
}LUAT_PIN_FUNC_E;

typedef union
{
	struct
	{
		uint8_t ec_gpio_id:7;			//移芯平台的GPIO号
		uint8_t ec_gpio_is_altfun4:1;	//移芯对应GPIO功能是不是复用功能4
	};
	uint8_t common_gpio_id;				//以GPIO号为唯一ID的芯片的GPIO id
}iomux_uid_u;

typedef struct
{
	iomux_uid_u uid;	//用于硬件操作所需的唯一ID
	uint8_t altfun_id;	//复用功能id
}pin_iomux_info;	//pin复用信息

typedef struct
{
	uint16_t
};

typedef struct
{
	uint16_t index;
	iomux_uid_u uid;
};


typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_UART_QTY];
}luat_uart_pin_iomux_t;

typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_I2C_QTY];
}luat_i2c_pin_iomux_t;

typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_SPI_QTY];
}luat_spi_pin_iomux_t;

typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_PWM_QTY];
}luat_pwm_pin_iomux_t;

typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_CAN_QTY];
}luat_can_pin_iomux_t;

typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_I2S_QTY];
}luat_i2s_pin_iomux_t;

typedef struct
{
	pin_iomux_info pin_list[LUAT_PIN_SDIO_QTY];
}luat_sdio_pin_iomux_t;


int luat_pin_to_gpio(const char* pin_name);

int luat_pin_parse(const char* pin_name, size_t* zone, size_t* index);

/**
 * @brief 获取某种外设的全部pin复用信息
 * @param type 外设类型，见LUAT_MCU_PERIPHERAL_E
 * @param id 外设id，例如uart2就填2
 * @param pin_list 输出pin复用信息表
 * @return 0成功，其他失败
 */
int luat_pin_get_iomux_info(LUAT_MCU_PERIPHERAL_E type, uint8_t id, pin_iomux_info *pin_list);
/**
 * @brief 设置某个外设的全部pin复用信息，如果该外设只有一种复用可能性，则不必设置，会直接失败
 * @param type 外设类型，见LUAT_MCU_PERIPHERAL_E
 * @param id 外设id，例如uart2就填2
 * @param pin_list 输入pin复用信息表
 * @return 0成功，其他失败
 */
int luat_pin_set_iomux_info(LUAT_MCU_PERIPHERAL_E type, uint8_t id, pin_iomux_info *pin_list);
/**
 * @brief 从模块pin脚号返回芯片pin的唯一id
 * @param num 模块pin脚号
 * @return pin的唯一id，如果唯一id是0xff代表没有
 */
iomux_uid_u luat_pin_get_from_num(uint32_t num);

void luat_pin_iomux_config(pin_iomux_info pin, uint8_t use_altfunction_pull, uint8_t driver_strength);

void luat_pin_iomux_print(pin_iomux_info *pin_list, uint8_t num);
#endif
