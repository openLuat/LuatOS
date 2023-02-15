/*
@module  hmeta
@summary 硬件元数据
@version 1.0
@date    2022.01.11
@demo    hmeta
@tag LUAT_USE_HMETA
@usage
-- 本库开发中
--[[
    这个库的作用是展示当前硬件的能力, 例如:
1. 有多少GPIO, 各GPIO默认模式是什么, 是否支持上拉/下拉
2. 有多少I2C,支持哪些速率
3. 有多少SPI,支持哪些速率和模式
4. 扩展属性, 例如区分Air780E和Air600E

]]
*/
#include "luat_base.h"
#include "luat_hmeta.h"

/*
获取模组名称
@api hmeta.model()
@return string 若能识别到,返回模组类型, 否则会是nil
@usage
sys.taskInit(function()
    while 1 do
        sys.wait(3000)
        -- hmeta识别底层模组类型的
        -- 不同的模组可以使用相同的bsp,但根据封装的不同,根据内部数据仍可识别出具体模块
        log.info("hmeta", hmeta.model())
        log.info("bsp",   rtos.bsp())
    end
end)
*/
static int l_hmeta_model(lua_State *L) {
    char buff[40] = {0};
    luat_hmeta_model_name(buff);
    if (strlen(buff)) {
        lua_pushstring(L, buff);
    }
    else {
        lua_pushnil(L);
    }
    return 1;
}

static int l_hmeta_gpio(lua_State *L) {
    return 0;
}

static int l_hmeta_uart(lua_State *L) {
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_hmeta[] =
{
    { "model" ,           ROREG_FUNC(l_hmeta_model)},
    { "gpio" ,            ROREG_FUNC(l_hmeta_gpio)},
    { "uart" ,            ROREG_FUNC(l_hmeta_uart)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_hmeta( lua_State *L ) {
    luat_newlib2(L, reg_hmeta);
    return 1;
}
