/*
@module  pin
@summary 管脚命名映射
@version 1.0
@date    2021.12.05
@tag LUAT_USE_PIN
@usage
-- 这个库是为了解决文本形式的PIN脚命名与GPIO编号的映射问题
-- 功能实现上, pin.PA01 就对应数值 1, 代表GPIO 1, 丝印上对应 PA01

-- PA12, GPIO12, 设置为输出, 而且低电平.
gpio.setup(12, 0)
gpio.setup(pin.PA12, 0) -- 推荐使用
gpio.setup(pin.get("PA12"), 0) -- 不推荐, 太长^_^

-- 只有部分BSP有这个库, ESP系列就没这个库
-- 这个库在 Air101/Air103/Air105 上有意义, 但不是必须用这个库, 直接写GPIO号是一样的效果
-- 在 ESP32系列, EC618系列(Air780E等), GPIO号都是直接给出的, 没有"Pxxx"形式, 所以这个库不存在
*/

#include "luat_base.h"
#include "luat_pin.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "pin"
#include "luat_log.h"

/**
获取管脚对应的GPIO号, 可简写为  pin.PA01 , 推荐使用简写
@api pin.get(name)
@name 管脚的名称, 例如PA01, PB12
@return int 对应的GPIO号,如果不存在则返回-1,并打印警告信息
@usage
-- 以下三个语句完全等价, 若提示pin这个库不存在,要么固件版本低,请升级底层固件, 要么就是不需要这个库
-- PA12, GPIO12, 设置为输出, 而且低电平.
gpio.setup(12, 0)
gpio.setup(pin.PA12, 0) -- 推荐使用
gpio.setup(pin.get("PA12"), 0) -- 不推荐, 太长^_^
 */
static int luat_pin_index(lua_State *L){
    size_t len;
    int pin = 0;
    const char* pin_name = luaL_checklstring(L, 1, &len);
    if (len < 3) {
        LLOGW("invaild pin id %s", pin_name);
        return 0;
    }
    pin = luat_pin_to_gpio(pin_name);
    if (pin >= 0) {
        lua_pushinteger(L, pin);
        return 1;
    }
    else {
        LLOGW("invaild pin id %s", pin_name);
        return 0;
    }
}

int luat_pin_parse(const char* pin_name, size_t* zone, size_t* index) {
    if (pin_name[0] != 'P' && pin_name[0] != 'p') {
        return -1;
    }
    // pa~pz
    if (pin_name[1] >= 'a' && pin_name[0] <= 'z') {
        *zone = pin_name[1] - 'a';
    }
    // PA~PZ
    else if (pin_name[1] >= 'A' && pin_name[0] <= 'Z') {
        *zone = pin_name[1] - 'A';
    }
    else {
        return -1;
    }
    // PA01 ~ PA99
    int re = atoi(&pin_name[2]);
    if (re < 0) {
        return -1;
    }
    *index = re;
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pin[] =
{
    {"__index", ROREG_FUNC(luat_pin_index)},
    {"get",     ROREG_FUNC(luat_pin_index)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_pin( lua_State *L ) {
    luat_newlib2(L, reg_pin);
    return 1;
}
