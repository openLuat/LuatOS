/*
@module  lcdseg
@summary 段式lcd
@version 1.0
@date    2021.10.22
@tag LUAT_USE_LCDSEG
*/

#include "luat_base.h"
#include "luat_lcdseg.h"


/**
初始化lcdseg库
@api lcdseg.setup(bias, duty, vlcd, com_number, fresh_rate, com_mark, seg_mark)
@int bias值,通常为 1/3 bias, 对应 lcdseg.BIAS_ONETHIRD
@int duty值,通常为 1/4 duty, 对应 lcdseg.DUTY_ONEFOURTH
@int 电压, 单位100mV, 例如2.7v写27. air103支持的值有 27/29/31/33
@int COM脚的数量, 取决于具体模块, air103支持1-4
@int 刷新率,通常为60, 对应60HZ
@int COM启用与否的掩码, 默认为0xFF,全部启用.若只启用COM0/COM1, 则0x03
@int seg启用与否的掩码, 默认为0xFFFFFFFF,即全部启用. 若只启用前16个, 0xFFFF
@return bool 成功返回true,否则返回false
@usage
-- 初始化lcdseg
if lcdseg.setup(lcdseg.BIAS_ONETHIRD, lcdseg.DUTY_ONEFOURTH, 33, 4, 60) then
    lcdseg.enable(1)

    lcdseg.seg_set(0, 1, 1)
    lcdseg.seg_set(2, 0, 1)
    lcdseg.seg_set(3, 31, 1)
end
 */
static int l_lcdseg_setup(lua_State* L) {
    luat_lcd_options_t opts = {0};
    opts.bias = luaL_checkinteger(L, 1);
    opts.duty = luaL_checkinteger(L, 2);
    opts.vlcd = luaL_checkinteger(L, 3);
    opts.com_number = luaL_checkinteger(L, 4);
    opts.fresh_rate = luaL_checkinteger(L, 5);
    opts.com_mark = luaL_optinteger(L, 6, 0xFF);
    opts.seg_mark = luaL_optinteger(L, 7, 0xFFFFFFFF);

    lua_pushboolean(L, luat_lcdseg_setup(&opts) == 0 ? 1 : 0);
    return 1;
}

/**
启用或禁用lcdseg库
@api lcdseg.enable(en)
@int 1启用,0禁用
@return bool 成功与否
 */
static int l_lcdseg_enable(lua_State* L) {
    uint8_t enable = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_lcdseg_enable(enable) == 0 ? 1 : 0);
    return 1;
}

/**
启用或禁用lcdseg的输出
@api lcdseg.power(en)
@int 1启用,0禁用
@return bool 成功与否
 */
static int l_lcdseg_power(lua_State* L) {
    uint8_t enable = luaL_checkinteger(L, 1);
    lua_pushboolean(L, luat_lcdseg_power(enable) == 0 ? 1 : 0);
    return 1;
}

/**
设置具体一个段码的状态
@api lcdseg.seg_set(com, seg, en)
@int COM号
@int seg号 要更改的字段的位索引
@int 1启用,0禁用
@return bool 成功与否
 */
static int l_lcdseg_seg_set(lua_State* L) {
    uint8_t com = luaL_checkinteger(L, 1);
    uint8_t seg = luaL_checkinteger(L, 2);
    uint8_t enable = luaL_checkinteger(L, 3);
    lua_pushboolean(L, luat_lcdseg_seg_set(com, seg, enable) == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_lcdseg[] = {
    { "setup",      ROREG_FUNC(l_lcdseg_setup)},
    { "enable",     ROREG_FUNC(l_lcdseg_enable)},
    { "power",      ROREG_FUNC(l_lcdseg_power)},
    { "seg_set",    ROREG_FUNC(l_lcdseg_seg_set)},

    //@const BIAS_STATIC number 没偏置电压(bias)
    { "BIAS_STATIC",    ROREG_INT(0)},
    //@const BIAS_ONEHALF number 1/2偏置电压(bias)
    { "BIAS_ONEHALF",   ROREG_INT(2)},
    //@const BIAS_ONETHIRD number 1/3偏置电压(bias)
    { "BIAS_ONETHIRD",  ROREG_INT(3)},
    //@const BIAS_ONEFOURTH number 1/4偏置电压(bias)
    { "BIAS_ONEFOURTH", ROREG_INT(4)},


    //@const DUTY_STATIC number 100%占空比(duty)
    { "DUTY_STATIC",    ROREG_INT(0)},
    //@const DUTY_ONEHALF number 1/2占空比(duty)
    { "DUTY_ONEHALF",   ROREG_INT(2)},
    //@const DUTY_ONETHIRD number 1/3占空比(duty)
    { "DUTY_ONETHIRD",  ROREG_INT(3)},
    //@const DUTY_ONEFOURTH number 1/4占空比(duty)
    { "DUTY_ONEFOURTH", ROREG_INT(4)},
    //@const DUTY_ONEFIFTH number 1/5占空比(duty)
    { "DUTY_ONEFIFTH",  ROREG_INT(5)},
    //@const DUTY_ONESIXTH number 1/6占空比(duty)
    { "DUTY_ONESIXTH",  ROREG_INT(6)},
    //@const DUTY_ONESEVENTH number 1/7占空比(duty)
    { "DUTY_ONESEVENTH", ROREG_INT(7)},
    //@const DUTY_ONEEIGHTH number 1/8占空比(duty)
    { "DUTY_ONEEIGHTH", ROREG_INT(8)},
};

LUAMOD_API int luaopen_lcdseg( lua_State *L ) {
    luat_newlib2(L, reg_lcdseg);
    return 1;
}

