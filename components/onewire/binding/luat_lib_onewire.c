/*
@module  onewire
@summary 单总线协议驱动
@version 1.0
@date    2023.11.16
@author  wendal
@tag     LUAT_USE_ONEWIRE
@demo    onewire
@usage
-- 本代码库尚处于开发阶段
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_onewire.h"

#define LUAT_LOG_TAG "onewire"
#include "luat_log.h"

static int l_onewire_open(lua_State *L)
{
    return 0;
}

static int l_onewire_close(lua_State *L)
{
    return 0;
}


/*
读取DS18B20
@api onewire.ds18b20(mode, pin, check)
@int 模式, 只能是 onewire.GPIO 或者 onewire.HW
@int GPIO模式对应GPIO编号, HW模式根据实际硬件来确定
@boolean 是否检查数据的CRC值
@return number 成功返回温度值,否则返回nil.单位 0.1摄氏度
@usage

-- GPIO模式,接 GPIO 9
local temp = onewire.ds18b20(onewire.GPIO, 9, true)
if temp then
    log.info("读取到的温度值", temp)
else
    log.info("读取失败")
end

*/
static int l_onewire_ds18b20(lua_State *L)
{
    luat_onewire_ctx_t ctx = {0};
    int ret = 0;
    ctx.mode = luaL_checkinteger(L, 1);
    ctx.id = luaL_checkinteger(L, 2);
    int check_crc = lua_toboolean(L, 3);
    int32_t val = 0;
    ret = luat_onewire_ds18b20(&ctx, check_crc, &val);
    if (ret) {
        return 0;
    }
    lua_pushinteger(L, val);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_onewire[] =
    {
        {"ds18b20", ROREG_FUNC(l_onewire_ds18b20)},
        {"open", ROREG_FUNC(l_onewire_open)},
        {"close", ROREG_FUNC(l_onewire_close)},

        {"GPIO", ROREG_INT(1)},
        {"HW", ROREG_INT(2)},
        {NULL, ROREG_INT(0)}
    };

LUAMOD_API int luaopen_onewire(lua_State *L)
{
    luat_newlib2(L, reg_onewire);
    return 1;
}
