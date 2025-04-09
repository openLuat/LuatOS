
#ifndef LUAT_PIN_H
#define LUAT_PIN_H
#include "luat_mcu.h"

typedef union
{
	struct
	{
		uint8_t ec_gpio_id:7;
		uint8_t ec_gpio_is_altfun4:1;
	};
	uint8_t common_gpio_id;
}iomux_uid_u;

typedef struct
{
	iomux_uid_u uid;
	uint8_t altfun_id;
}pin_iomux_info;

typedef struct
{
	pin_iomux_info rx;
	pin_iomux_info tx;
	pin_iomux_info rts;
	pin_iomux_info cts;
}uart_iomux_info;

typedef struct
{
	pin_iomux_info scl;
	pin_iomux_info sda;
}i2c_iomux_info;

typedef struct
{
	pin_iomux_info mosi;
	pin_iomux_info miso;
	pin_iomux_info clk;
	pin_iomux_info cs;
}spi_iomux_info;

typedef	struct
{
	pin_iomux_info pwm_p;
	pin_iomux_info pwm_n;
}pwm_iomux_info;

typedef	struct
{
	pin_iomux_info rx;
	pin_iomux_info tx;
	pin_iomux_info stb;
}can_iomux_info;

typedef	struct
{
	pin_iomux_info io;
}gpio_iomux_info;

typedef struct
{
	pin_iomux_info mosi;
	pin_iomux_info miso;
	pin_iomux_info bit_clk;
	pin_iomux_info lr_clk;
	pin_iomux_info m_clk;
}i2s_iomux_info;

typedef	struct
{
	pin_iomux_info data[4];
	pin_iomux_info cmd;
	pin_iomux_info clk;
}sdio_iomux_info;

typedef	struct
{
	pin_iomux_info io;
}onewire_iomux_info;

typedef struct
{
	union
	{
		uart_iomux_info uart;
		i2c_iomux_info i2c;
		spi_iomux_info spi;
		pwm_iomux_info pwm;
		can_iomux_info can;
		gpio_iomux_info gpio;
		i2s_iomux_info i2s;
		sdio_iomux_info sdio;
		onewire_iomux_info onewire;
	};
}peripheral_iomux_info;

int luat_pin_to_gpio(const char* pin_name);

int luat_pin_parse(const char* pin_name, size_t* zone, size_t* index);

int luat_pin_get_iomux_info(LUAT_MCU_PERIPHERAL_E type, uint8_t id, peripheral_iomux_info *pin_iomux_info);
int luat_pin_set_iomux_info(LUAT_MCU_PERIPHERAL_E type, uint8_t id, peripheral_iomux_info *pin_iomux_info);
void luat_pin_iomux_config(pin_iomux_info pin, uint8_t use_altfunction_pull, uint8_t driver_strength);
#endif
