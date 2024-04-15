/*
@module  ht1621
@summary 液晶屏驱动(HT1621/HT1621B)
@version 1.0
@author  wendal
@date    2024.04.15
@tag     LUAT_USE_GPIO
@usage
-- 需要接3个GPIO引脚, 然后给ht1621接好供电
-- 假设 CS脚接   模块的 GPIO4
-- 假设 DATA脚接 模块的 GPIO5
-- 假设 WR脚接   模块的 GPIO3
local seg = ht1621.setup(4, 5, 3)
ht1621.lcd(seg, true) -- 背光亮起
ht1621.data(seg, 0, 0xeb) -- 位置0显示数字1
*/
#include "luat_base.h"
#include "luat_ht1621.h"
#include "luat_gpio.h"

/*
初始化ht1621
@api ht1621.setup(pin_cs, pin_data, pin_wr)
@int 片选引脚, 填模块的GPIO编码
@int 数据引脚, 填模块的GPIO编码
@int WR引脚, 填模块的GPIO编码
@return userdata 返回ht1621对象
@usage
local seg = ht1621.setup(4, 5, 3)
ht1621.data(seg, 0, 0xeb)
*/
static int l_ht1621_setup(lua_State *L) {
    int pin_cs = luaL_checkinteger(L, 1);
    int pin_data = luaL_checkinteger(L, 2);
    int pin_wr = luaL_checkinteger(L, 3);
    luat_ht1621_conf_t* conf = lua_newuserdata(L, sizeof(luat_ht1621_conf_t));
    conf->pin_cs = pin_cs;
    conf->pin_data = pin_data;
    conf->pin_wr = pin_wr;
    luat_ht1621_init(conf);
    return 1;
}

/*
LCD开关
@api ht1621.lcd(seg, onoff)
@userdata ht1621.setup返回的ht1621对象
@boolean true开,false关
@return nil 无返回值
@usage
local seg = ht1621.setup(4, 5, 3)
ht1621.lcd(seg, true)
*/
static int l_ht1621_lcd(lua_State *L) {
    luat_ht1621_conf_t* conf = lua_touserdata(L, 1);
    if (conf == NULL) return 0;
    int onoff = lua_toboolean(L, 2);
    luat_ht1621_lcd(conf, onoff);
    return 0;
}

/*
展示数据
@api ht1621.data(seg, addr, sdat)
@userdata ht1621.setup返回的ht1621对象
@int 地址, 0-6, 超过6无效
@int 数据, 0-255
@return nil 无返回值
@usage
local seg = ht1621.setup(4, 5, 3)
ht1621.lcd(seg, true)
ht1621.data(seg, 0, 0xF1)
-- 附数字0-9的值表
-- 0,1,2,3,4,5,6,7,8,9
-- 0xeb,0x0a,0xad,0x8f,0x4e,0xc7,0xe7,0x8a,0xef,0xcf
*/
static int l_ht1621_data(lua_State *L) {
    luat_ht1621_conf_t* conf = lua_touserdata(L, 1);
    if (conf == NULL) return 0;
    int addr = luaL_checkinteger(L, 2);
    int sdat = luaL_checkinteger(L, 3);
    luat_ht1621_write_data(conf, addr, sdat);
    return 0;
}

/*
发送指令
@api ht1621.cmd(seg, cmd)
@userdata ht1621.setup返回的ht1621对象
@int 指令, 0-255
@return nil 无返回值
@usage
-- 具体指令请查阅硬件手册
*/
static int l_ht1621_cmd(lua_State *L) {
    luat_ht1621_conf_t* conf = lua_touserdata(L, 1);
    if (conf == NULL) return 0;
    int cmd = luaL_checkinteger(L, 2);
    luat_ht1621_write_cmd(conf, cmd);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_ht1621[] =
{
    { "setup" ,           ROREG_FUNC(l_ht1621_setup)},
    { "lcd" ,             ROREG_FUNC(l_ht1621_lcd)},
    { "data" ,           ROREG_FUNC(l_ht1621_data)},
    { "cmd" ,             ROREG_FUNC(l_ht1621_cmd)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_ht1621( lua_State *L ) {
    luat_newlib2(L, reg_ht1621);
    return 1;
}
