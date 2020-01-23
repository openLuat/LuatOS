
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "rtthread.h"


// 获取DS18B20的温度数据
// while 1 do timer.mdelay(5000) sensor.ds18b20(14) end
static int l_sensor_ds18b20(lua_State *L) {
    extern int32_t ds18b20_get_temperature(rt_base_t pin);
    int32_t temp = ds18b20_get_temperature(luaL_checkinteger(L, 1));
    rt_kprintf("temp:%3d.%dC\n", temp/10, temp%10);
    lua_pushinteger(L, temp);
    return 1;
}


#include "rotable.h"
static const rotable_Reg reg_sensor[] =
{
    { "ds18b20" ,  l_sensor_ds18b20 , NULL},
	{ NULL, NULL , NULL}
};

LUAMOD_API int luaopen_sensor( lua_State *L ) {
    rotable_newlib(L, reg_sensor);
    return 1;
}