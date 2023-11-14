
/*
@module  ws2812
@summary 幻彩灯带RGB控制器(WS2812系列)
@version 1.0
@date    2023.11.14
@author  wendal
@tag LUAT_USE_WS2812
@usage
-- 本库尚在开发阶段
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_ymodem.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "ws2812"
#include "luat_log.h"

#include "luat_ws2812.h"

/*
创建上下文
@api ws2812.create(mode, count, id)
@int 传输模式, 例如 ws2812.GPIO, ws2812.PWM, ws2812.SPI
@int RGB灯总个数
@int 主参数id, 对于不同的模式有不同的值
@return userdata 创建成功返回上下文,否则返回nil
@usage
-- GPIO模式, 64个灯, 使用GPIO9
local leds = ws2812.create(ws2812.GPIO, 64, 9)
-- SPI模式, 32个灯, 使用SPI1
local leds = ws2812.create(ws2812.SPI, 32, 1)
-- PWM模式, 16个灯, 使用PWM4
local leds = ws2812.create(ws2812.PWM, 16, 4)
-- HW模式, 64个灯, 使用硬件专用实现,具体id需要对照手册
local leds = ws2812.create(ws2812.RMT, 64, 2)

-- 注意: 并非所有模块都支持以上所有模式
-- 而且, 固件需要开启对应的GPIO/SPI/PWM功能才能使用对应的模式

*/
static int l_ws2812_create(lua_State* L) {
    int mode = luaL_checkinteger(L, 1);
    int count = luaL_checkinteger(L, 2);
    int id = luaL_checkinteger(L, 3);

    if (mode < LUAT_WS2812_MODE_GPIO || mode > LUAT_WS2812_MODE_HW) {
        LLOGE("未知的模式 %d", mode);
        return 0;
    }
    if (count <= 0 || count >= 4 * 1024) {
        LLOGE("灯的数量不合法 %d", count);
        return 0;
    }
    size_t len = sizeof(luat_ws2812_t) + sizeof(luat_ws2812_color_t) * count;
    luat_ws2812_t* ctx = lua_newuserdata(L, len);
    if (ctx == NULL) {
        LLOGE("out of memory when malloc ws2812 ctx");
        return 0;
    }
    memset(ctx, 0, len);
    ctx->id = id;
    ctx->count = count;
    ctx->mode = mode;
    return 1;
}

/*
设置灯的颜色
@api ws2812.set(leds,index, R, G, B)
@userdata 通过ws2812.create获取到的上下文
@int 灯的编号,从0开始
@int RGB值中的R值
@int RGB值中的G值
@int RGB值中的B值
@return boolean 设置成功返回true,否则返回nil
@usage
-- RGB逐个颜色传递
ws2812.set(leds, 5, 0xFF, 0xAA, 0x11)
-- 也支持一个参数传完, 与前一条等价
ws2812.set(leds, 5, 0xFFAA11)
*/
static int l_ws2812_set(lua_State* L) {
    luat_ws2812_t* ctx = lua_touserdata(L, 1);
    int offset = luaL_checkinteger(L, 2);
    if (offset < 0 || offset >= ctx->count) {
        LLOGE("灯序号越界了!!! %d %d", offset, ctx->count);
        return 0;
    }
    if (lua_isinteger(L, 3) && lua_isinteger(L, 4) && lua_isinteger(L, 5)) {
        ctx->colors[offset].R = luaL_checkinteger(L, 3);
        ctx->colors[offset].G = luaL_checkinteger(L, 4);
        ctx->colors[offset].B = luaL_checkinteger(L, 5);
    }
    else if (lua_isinteger(L, 3)) {
        lua_Integer val = luaL_checkinteger(L, 3);
        ctx->colors[offset].R = (val >> 16) & 0xFF;
        ctx->colors[offset].G = (val >> 8) & 0xFF;
        ctx->colors[offset].B = (val >> 0) & 0xFF;
    }
    else {
        LLOGE("无效的RGB参数");
        return 0;
    }
    lua_pushboolean(L, 1);
    return 0;
}

/*
发送数据到设备
@api ws2812.send(leds)
@userdata 通过ws2812.create获取到的上下文
@return boolean 设置成功返回true,否则返回nil
@usage
-- 没有更多参数, 发就完事了
ws2812.send(leds)
*/
static int l_ws2812_send(lua_State* L) {
    luat_ws2812_t* ctx = lua_touserdata(L, 1);
    int ret = luat_ws2812_send(ctx);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 0;
}

/*
配置额外参数
@api ws2812.send(leds, arg0, arg1, arg2, arg3, arg4)
@userdata 通过ws2812.create获取到的上下文
@int 额外参数0
@int 额外参数1
@int 额外参数2
@int 额外参数3
@int 额外参数4
@return boolean 设置成功返回true,否则返回nil
@usage
-- 本函数与具体模式有关

--GPIO模式可调整T0H T0L, T1H T1L 的具体延时
ws2812.send(leds, t0h, t0l, t1h, t1l)
*/
static int l_ws2812_args(lua_State* L) {
    luat_ws2812_t* ctx = lua_touserdata(L, 1);
    int c = lua_gettop(L);
    if (c > 1) {
        for (size_t i = 1; i < c && i < 8; i++)
        {
            ctx->args[i - 1] = lua_tointeger(L, i + 1);
        }
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_ws2812[] =
{
    { "create",           	ROREG_FUNC(l_ws2812_create)},
    { "set",           	    ROREG_FUNC(l_ws2812_set)},
    { "args",               ROREG_FUNC(l_ws2812_args)},
    { "send",           	ROREG_FUNC(l_ws2812_send)},

    { "GPIO",               ROREG_INT(LUAT_WS2812_MODE_GPIO)},
    { "SPI",                ROREG_INT(LUAT_WS2812_MODE_SPI)},
    { "PWM",                ROREG_INT(LUAT_WS2812_MODE_PWM)},
    { "RMT",                ROREG_INT(LUAT_WS2812_MODE_RMT)},
    { "HW",                 ROREG_INT(LUAT_WS2812_MODE_HW)},
	{ NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_ws2812( lua_State *L ) {
    luat_newlib2(L, reg_ws2812);
    return 1;
}
