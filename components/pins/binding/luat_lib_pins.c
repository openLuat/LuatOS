/*
@module  pins
@summary 管脚外设复用
@version 1.0
@date    2025.4.10
@tag     @tag LUAT_USE_PINS
@demo     pins
@usage
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo

-- 本库的API属于高级用法, 仅动态配置管脚时使用
-- 本库的API属于高级用法, 仅动态配置管脚时使用
-- 本库的API属于高级用法, 仅动态配置管脚时使用
*/

#include "luat_base.h"
#include "luat_pins.h"
#include "luat_mcu.h"
#include <stdlib.h>
#include "luat_fs.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "pins"
#include "luat_log.h"

/**
当某种外设允许复用在不同引脚上时，指定某个管脚允许复用成某种外设功能，需要在外设启用前配置好，外设启用时起作用。
@api pins.setup(pin, func)
@int 管脚物理编号, 对应模组俯视图下的顺序编号, 例如 67, 68
@string 功能说明, 例如 "GPIO18", "UART1_TX", "UART1_RX", "SPI1_CLK", "I2C1_CLK", 目前支持的外设有"UART","I2C","SPI","PWM","CAN","GPIO","ONEWIRE"
@return boolean 配置成功,返回true, 其他情况均返回false, 并在日志中提示失败原因
@usage
--把air780epm的PIN67脚,做GPIO 18用
--pins.setup(67, "GPIO18")
--把air780epm的PIN55脚,做uart2 rx用
--pins.setup(55, "UART2_RXD")
--把air780epm的PIN56脚,做uart2 tx用
--pins.setup(56, "UART2_TXD")
 */
static int l_pins_setup(lua_State *L){
    size_t len = 0;
    int pin = 0;
    int result = 0;
    int altfun_id = 0;
    const char* func_name = NULL;
    pin = luaL_optinteger(L, 1, -1);
    if (pin < 0)
    {
    	LLOGE("pin序号参数错误");
    	goto LUAT_PIN_SETUP_DONE;
    }
    else
    {
		if (lua_type(L, 2) == LUA_TSTRING) {
			func_name = luaL_checklstring(L, 2, &len);
		}
		else if (lua_isinteger(L, 2)) {
			altfun_id = luaL_checkinteger(L, 2);
		}
		else {
			LLOGE("参数错误");
			goto LUAT_PIN_SETUP_DONE;
		}
		result = luat_pins_setup(pin, func_name, len, altfun_id);
    }
LUAT_PIN_SETUP_DONE:
	lua_pushboolean(L, result);
	return 1;
}

/**
加载硬件配置，如果存在/luadb/pins.json，开机后自动加载/luadb/pins.json，无需调用
@api pins.loadjson(path)
@string path, 配置文件路径, 可选, 默认值是 /luadb/pins.json
@return boolean 成功返回true, 失败返回nil, 并在日志中提示失败原因
@return int 失败返回错误码, 成功返回0
@usage
pins.loadjson("/my.json")
*/
static int l_pins_load(lua_State *L) {
	const char* path = luaL_checkstring(L, 1);
	int ret = luat_pins_load_from_file(path);
	lua_pushboolean(L, ret == 0 ? 1 : 0);
	lua_pushinteger(L, ret);
	return 2;
}

/**
调试模式
@api pins.debug(mode)
@boolean 是否开启调试模式, 默认是关闭的, 就是日志多一些
@usage
pins.debug(true)
*/
static int l_pins_debug(lua_State *L) {
	extern uint8_t g_pins_debug;
	g_pins_debug = (uint8_t)lua_toboolean(L, 1);
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pins[] =
{
    {"setup",     ROREG_FUNC(l_pins_setup)},
	{"loadjson",  ROREG_FUNC(l_pins_load)},
	{"debug",	  ROREG_FUNC(l_pins_debug)},
	{ NULL,       ROREG_INT(0) }
};

LUAMOD_API int luaopen_pins( lua_State *L ) {
    luat_newlib2(L, reg_pins);
	int ret = luat_pins_load_from_file("/luadb/pins.json");
	if (ret == 0) {
		LLOGD("pins.json 加载和配置完成");
	}
    return 1;
}
