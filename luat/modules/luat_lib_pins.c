/*
@module  pins
@summary 管脚外设复用
@version 1.0
@date    2025.4.10
@tag LUAT_USE_PINS
@usage

*/

#include "luat_base.h"
#include "luat_pin.h"
#include "luat_mcu.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "pins"
#include "luat_log.h"

static luat_pin_peripheral_function_description_t luat_pins_function_analyze(char *string)
{
	const char *peripheral_names[LUAT_MCU_PERIPHERAL_QTY] = {
			"UART","I2C","SPI","PWM","CAN","GPIO","I2S","SDIO","LCD","CAMERA","ONEWIRE","KEYBORAD"
	};
	const char *function0_names[3] = {
			"RX","SCL","MOSI",
	};
	const char *function1_names[3] = {
			"TX","SDA","MISO",
	};
	const char *function2_names[4] = {
			"RTS","CLK","STB","BCLK"
	};
	const char *function3_names[3] = {
			"CTS","CS","LRCLK"
	};
	const char *function4_names[2] = {
			"MCLK","CMD"
	};
}

/**
当某种外设允许复用在不同引脚上时，指定某个管脚允许复用成某种外设功能，需要在外设启用前配置好，外设启用时起作用。
@api pins.setup(pin, func)
@int 管脚物理编号, 对应模组俯视图下的顺序编号, 例如 67, 68
@string 功能说明, 例如 "GPIO18", "UART1_TX", "UART1_RX", "SPI1_CLK", "I2C1_CLK", 目前支持的外设有"UART","I2C","SPI","PWM","CAN","GPIO","ONEWIRE"
@return boolean 配置成功,返回true, 其他情况均返回nil, 并在日志中提示失败原因
@usage
-- 把air780epm的PIN67脚,做GPIO 18用
--pins.setup(67, "GPIO18")
-- 把air780epm的PIN55脚,做uart2 rx用
--pins.setup(55, "UART2_RX")
-- 把air780epm的PIN56脚,做uart2 tx用
--pins.setup(56, "UART2_TX")
 */
static int luat_pins_setup(lua_State *L){
	return 1;
}

/**
加载硬件配置，如果存在/luadb/pins.json，开机后自动加载/luadb/pins.json，无需调用
@api pins.load(path)
@string path, 配置文件路径, 可选, 默认值是 /luadb/pins.json
@return boolean 成功返回true, 失败返回false
@usage
pins.load()
pins.load("/my.json")
*/
static int luat_pins_load(lua_State *L){
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pins[] =
{
    {"setup",     ROREG_FUNC(luat_pins_setup)},
	{"load",     ROREG_FUNC(luat_pins_load)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_pins( lua_State *L ) {
    luat_newlib2(L, reg_pins);
    return 1;
}
