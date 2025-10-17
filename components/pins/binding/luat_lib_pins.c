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
#include "luat_hmeta.h"

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
将对应管脚变成高阻或者输入，不对外输出
@api pins.close(pin)
@int 管脚物理编号, 对应模组俯视图下的顺序编号, 例如 67, 68
@return boolean 配置成功,返回true, 其他情况均返回false, 并在日志中提示失败原因
@usage
--把air780epm的PIN67脚关闭掉
--pins.close(67)
 */
static int l_pins_close(lua_State *L){

    int pin = 0;
    int result = 0;
    pin = luaL_optinteger(L, 1, -1);
    if (pin < 0)
    {
    	LLOGE("pin序号参数错误");
    	goto LUAT_PIN_SETUP_DONE;
    }
    else
    {
    	luat_pin_function_description_t pin_function;
    	if (luat_pin_get_description_from_num(pin, &pin_function))
    	{
    		LLOGE("pin%d不支持修改", pin);
    		goto LUAT_PIN_SETUP_DONE;
    	}
    	luat_pin_iomux_info pin_info;
    	pin_info.uid = pin_function.uid;
    	luat_pin_close(pin_info);
    	result = 1;
    }
LUAT_PIN_SETUP_DONE:
	lua_pushboolean(L, result);
	return 1;
}

/**
加载硬件配置
@api pins.loadjson(path)
@string path, 配置文件路径, 可选, 默认值是 /luadb/pins.json
@return boolean 成功返回true, 失败返回nil, 并在日志中提示失败原因
@return int 失败返回错误码, 成功返回0
@usage
-- ，如果存在/luadb/pins_$model.json 就自动加载
-- 其中的 $model是型号, 例如 Air780EPM, 默认加载的是 luadb/pins_Air780EPM.json

-- 以下是自行加载配置的例子, 一般用不到
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
@boolean 是否开启调试模式, 默认是关闭的, 打开之后日志多很多
@return nil 无返回值
@usage
pins.debug(true)
*/
static int l_pins_debug(lua_State *L) {
	extern uint8_t g_pins_debug;
	if (lua_isinteger(L, 1)) {
		g_pins_debug = luaL_checkinteger(L, 1);
	}
	else if (lua_isboolean(L, 1)) {
		g_pins_debug = (uint8_t)lua_toboolean(L, 1);
	}
	lua_pushboolean(L, g_pins_debug);
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pins[] =
{
    {"setup",     ROREG_FUNC(l_pins_setup)},
	{"close",     ROREG_FUNC(l_pins_close)},
	{"loadjson",  ROREG_FUNC(l_pins_load)},
	{"debug",	  ROREG_FUNC(l_pins_debug)},
	{ NULL,       ROREG_INT(0) }
};

LUAMOD_API int luaopen_pins( lua_State *L ) {
    luat_newlib2(L, reg_pins);
	char buff[64] = {0};
	char name[40] = {0};
	luat_hmeta_model_name(name);
	// 需要兼容2种命名风格, 严格模组命名, 或者全小写命名
	// 首先, 找pins_Air780EPM.json
	// 不存在的话, 找 pins_air780epm.json
	snprintf(buff, sizeof(buff), "/luadb/pins_%s.json", name);
	if (luat_fs_fexist(buff) == 0) {
		int size = strlen(name);
    	int j;

		// 为了兼容性,先找大写的
		for( int i = 0; i < size - 1 ; i++){
        	// 转大写
			if (name[i] >= 'a' && name[i] <= 'z'){
				name[i] = name[i] - 32;
			}
    	}
		snprintf(buff, sizeof(buff), "/luadb/pins_%s.json", name);
    
		if (luat_fs_fexist(buff) == 0) {
    		for( int i = 0; i < size ; i++){
        		// 转小写
				if (name[i] >= 'A' && name[i] <= 'Z'){
					name[i] = name[i] + 32;
				}
    		}
			snprintf(buff, sizeof(buff), "/luadb/pins_%s.json", name);
		}
	}
	
	int ret = luat_pins_load_from_file(buff);
	if (ret == 0) {
		LLOGD("%s 加载和配置完成", buff);
	}
    return 1;
}
