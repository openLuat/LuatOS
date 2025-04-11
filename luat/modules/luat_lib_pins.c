/*
@module  pins
@summary 管脚外设复用
@version 1.0
@date    2025.4.10
@tag
@usage

*/

#include "luat_base.h"
#include "luat_pin.h"
#include "luat_mcu.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "pins"
#include "luat_log.h"

static int search(char *string, size_t string_len, const char **table, uint8_t len)
{
	for(int i = 0; i < len; i++)
	{
		if (strnstr(string, table[i], string_len))
		{
			return i;
		}
	}
	return -1;
}

static luat_pin_peripheral_function_description_u luat_pin_function_analyze(char *string, size_t len)
{
	luat_pin_peripheral_function_description_u description;
	size_t offset = 0;
	const char *peripheral_names[LUAT_MCU_PERIPHERAL_QTY] = {
			"UART","I2C","SPI","PWM","CAN","GPIO","I2S","SDIO","LCD","CAMERA","ONEWIRE","KEYBORAD"
	};
	const char *function0_names[3] = {
			"RX","SCL","MOSI"
	};
	const char *function1_names[3] = {
			"TX","SDA","MISO"
	};
	const char *function2_names[4] = {
			"RTS","SCLK","STB","BCLK"
	};
	const char *function3_names[3] = {
			"CTS","CS","LRCLK"
	};
	const char *function4_names[2] = {
			"MCLK","CMD"
	};
	const char *function5_names[1] = {
			"SCLK"
	};
	description.code = 0;
	for(description.peripheral_type = 0; description.peripheral_type < LUAT_MCU_PERIPHERAL_QTY; description.peripheral_type++)
	{
		offset = strlen(peripheral_names[description.peripheral_type]);
		if (!memcmp(string, peripheral_names[description.peripheral_type], offset))
		{
			int function_id;
			description.peripheral_id = 0;
			string += offset;
			len -= offset;
			while(isdigit(string[0]))
			{
				description.peripheral_id = description.peripheral_id * 10 + (string[0] - '0');
				string++;
				len--;
			}
			switch(description.peripheral_type)
			{
			case LUAT_MCU_PERIPHERAL_UART:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function3_names, sizeof(function3_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 3;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_I2C:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_SPI:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function3_names, sizeof(function3_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 3;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_PWM:
				if (!string[0])
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				if (string[0] == 'n')
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_CAN:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_GPIO:
				if (!string[0])
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_I2S:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function3_names, sizeof(function3_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 3;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function4_names, sizeof(function4_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 4;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_SDIO:
				if (strnstr(string, "_DATA", len))
				{
					if (string[5] >= '0' && string[5] <= '3')
					{
						function_id = string[5] - '0';
					}
					break;
				}
				function_id = search(string, len, function4_names, sizeof(function4_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 4;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function5_names, sizeof(function5_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 5;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_ONEWIRE:
				if (!string[0])
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			default:
				break;
			}
		}
	}
	LLOGE("%.*s不是可配置的外设功能", len, string);
	description.code = 0xffff;
LUAT_PIN_FUNCTION_ANALYZE_DONE:
	if (!description.is_no_use)
	{
		LLOGD("%.*s find %d,%d,%d", len, string, description.peripheral_type, description.peripheral_id, description.function_id);
	}
	return description;
}

/**
当某种外设允许复用在不同引脚上时，指定某个管脚允许复用成某种外设功能，需要在外设启用前配置好，外设启用时起作用。
@api pins.setup(pin, func)
@int 管脚物理编号, 对应模组俯视图下的顺序编号, 例如 67, 68
@string 功能说明, 例如 "GPIO18", "UART1_TX", "UART1_RX", "SPI1_CLK", "I2C1_CLK", 目前支持的外设有"UART","I2C","SPI","PWM","CAN","GPIO","ONEWIRE"
@return boolean 配置成功,返回true, 其他情况均返回false, 并在日志中提示失败原因
@usage
-- 把air780epm的PIN67脚,做GPIO 18用
--pins.setup(67, "GPIO18")
-- 把air780epm的PIN55脚,做uart2 rx用
--pins.setup(55, "UART2_RX")
-- 把air780epm的PIN56脚,做uart2 tx用
--pins.setup(56, "UART2_TX")
 */
static int luat_pin_setup(lua_State *L){
    size_t len;
    int pin = 0;
    int result;
    const char* func_name = luaL_checklstring(L, 2, &len);
    pin = luaL_optinteger(L, 1, -1);
    if (pin < 0)
    {
    	LLOGE("pin序号参数错误");
    	goto LUAT_PIN_SETUP_DONE;
    }
    else
    {
    	if (len < 2)
    	{
    		LLOGE("%.*s外设功能描述不正确", len, func_name);
    		goto LUAT_PIN_SETUP_DONE;
    	}
    	luat_pin_function_description_t pin_description;
    	if (luat_pin_get_description_from_num(pin, &pin_description))
    	{
        	LLOGE("pin%d不支持修改", pin);
        	goto LUAT_PIN_SETUP_DONE;
    	}
    	luat_pin_peripheral_function_description_u func_description = luat_pin_function_analyze(func_name, len);
    	if (func_description.code == 0xffff)
    	{
    		goto LUAT_PIN_SETUP_DONE;
    	}
    	uint8_t altfun_id = luat_pin_get_altfun_id_from_description(func_description.code, &pin_description);
    	if (altfun_id == 0xff)
    	{
    		LLOGE("%.*s不是pin%d的可配置功能", len, func_name, pin);
    		goto LUAT_PIN_SETUP_DONE;
    	}
    	luat_pin_iomux_info pin_list[LUAT_PIN_FUNCTION_MAX] = {0};
    	if (!luat_pin_get_iomux_info(func_description.peripheral_type, func_description.peripheral_id, pin_list))
    	{
    		pin_list[func_description.function_id].altfun_id = altfun_id;
    		pin_list[func_description.function_id].uid = pin_description.uid;
    		if (!luat_pin_set_iomux_info(func_description.peripheral_type, func_description.peripheral_id, pin_list))
    		{
    			result = 1;
    			goto LUAT_PIN_SETUP_DONE;
    		}
    	}
    	LLOGE("%.*s不可配置，请确认硬件手册上该功能可以复用在2个及以上的pin", len, func_name);
    }
LUAT_PIN_SETUP_DONE:
	lua_pushboolean(L, result);
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
static int luat_pin_load(lua_State *L){
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pins[] =
{
    {"setup",     ROREG_FUNC(luat_pin_setup)},
	{"load",     ROREG_FUNC(luat_pin_load)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_pins( lua_State *L ) {
    luat_newlib2(L, reg_pins);
    return 1;
}
