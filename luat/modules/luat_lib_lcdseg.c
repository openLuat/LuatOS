/*
@module  lcdseg
@summary 段式lcd
@version 1.0
@date    2021.10.22
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
@int seg启用与否的掩码, 默认为0xFFFF,即全部启用. 若只启用前16个, 0xFF
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
    opts.seg_mark = luaL_optinteger(L, 7, 0xFF);

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

    { "BIAS_STATIC",    ROREG_INT(0)},
    { "BIAS_ONEHALF",   ROREG_INT(2)},
    { "BIAS_ONETHIRD",  ROREG_INT(3)},
    { "BIAS_ONEFOURTH", ROREG_INT(4)},


    { "DUTY_STATIC",    ROREG_INT(0)},
    { "DUTY_ONEHALF",   ROREG_INT(2)},
    { "DUTY_ONETHIRD",  ROREG_INT(3)},
    { "DUTY_ONEFOURTH", ROREG_INT(4)},
    { "DUTY_ONEFIFTH",  ROREG_INT(5)},
    { "DUTY_ONESIXTH",  ROREG_INT(6)},
    { "DUTY_ONESEVENTH", ROREG_INT(7)},
    { "DUTY_ONEEIGHTH", ROREG_INT(8)},
};

LUAMOD_API int luaopen_lcdseg( lua_State *L ) {
    luat_newlib2(L, reg_lcdseg);
    return 1;
}

