
#include "luat_base.h"
#include "luat_log.h"
#include "luat_gpio.h"
#include "luat_malloc.h"

/*
@module gpio GPIO操作
@since 1.0.0
*/

static int l_gpio_handler(lua_State *L, void* ptr) {
    // 给 sys.publish方法发送数据
    luat_gpio_t *gpio = (luat_gpio_t *)ptr;
    lua_getglobal(L, "sys_pub");
    if (!lua_isnil(L, -1)) {
        lua_pushfstring(L, "IRQ_%d", (char)gpio->pin);
        lua_pushinteger(L, luat_gpio_get(gpio->pin));
        lua_call(L, 2, 0);
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

/*
@api gpio.setup 设置管脚功能
@param pin [必]针脚编号,必须是数值
@param mode [必]输入输出模式, 可以是 输入模式gpio.INPUT, 输出模式gpio.OUTPUT, 中断模式gpio.IRQ
@param pull [选]上拉下列模式, 可以是gpio.PULLUP 或 gpio.PULLDOWN, 需要根据实际硬件选用
@param irq [选]中断模式, 上升沿gpio.RISING, 下降沿gpio.FALLING, 上升和下降都要gpio.BOTH.默认是BOTH
@return re 设置失败的话会返回1, 否则返回0
@usage gpio.setup(17, gpio.INPUT) 设置gpio17为输入
@usage gpio.setup(27, gpio.IRQ) 设置gpio27为中断, 通过sys.subscribe("IRQ_27", function(val) end) 可订阅中断事件
*/
static int l_gpio_setup(lua_State *L) {
    lua_gettop(L);
    // TODO 设置失败会内存泄漏
    luat_gpio_t* conf = (luat_gpio_t*)luat_heap_malloc(sizeof(luat_gpio_t));
    conf->pin = luaL_checkinteger(L, 1);
    conf->mode = luaL_checkinteger(L, 2);
    conf->pull = luaL_optinteger(L, 3, Luat_GPIO_DEFAULT);
    conf->irq = luaL_optinteger(L, 4, Luat_GPIO_BOTH);
    if (conf->mode == Luat_GPIO_IRQ) {
        conf->func = &l_gpio_handler;
    }
    else {
        conf->func = NULL;
        
    }
    int re = luat_gpio_setup(conf);
    if (conf->mode == Luat_GPIO_IRQ) {
        if (re) {
            luat_heap_free(conf);
        }
    }
    else {
        luat_heap_free(conf);
    }
    lua_pushinteger(L, re == 0 ? 1 : 0)
    return 1;
}

/*
@api gpio.set 设置管脚电平
@param pin [必]针脚编号,必须是数值
@param value [必]电平, 可以是 高电平gpio.HIGH, 低电平gpio.LOW, 或者直接写数值1或0
@return nil
@usage gpio.set(17, 0) 设置gpio17为低电平
*/
static int l_gpio_set(lua_State *L) {
    luat_gpio_set(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2));
    return 0;
}

/*
@api gpio.get 获取管脚电平
@param pin [必]针脚编号,必须是数值
@return value [必]电平, 高电平gpio.HIGH, 低电平gpio.LOW
@usage gpio.get(17) 获取gpio17的当前电平
*/
static int l_gpio_get(lua_State *L) {
    lua_pushinteger(L, luat_gpio_get(luaL_checkinteger(L, 1)) & 0x01 ? 1 : 0);
    return 1;
}

/*
@api gpio.close 关闭管脚功能(高阻输入态),关掉中断
@param pin [必]针脚编号,必须是数值
@return nil 无返回值,总是执行成功
@usage gpio.close(17) 关闭gpio17
*/
static int l_gpio_close(lua_State *L) {
    luat_gpio_close(luaL_checkinteger(L, 1));
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_gpio[] =
{
    { "setup" ,         l_gpio_setup ,0},
    { "set" ,           l_gpio_set,   0},
    { "get" ,           l_gpio_get,   0 },
    { "close" ,         l_gpio_close, 0 },
    { "LOW",            NULL,         Luat_GPIO_LOW},
    { "HIGH",           NULL,         Luat_GPIO_HIGH},

    { "OUTPUT",         NULL,         Luat_GPIO_OUTPUT},
    { "INPUT",          NULL,         Luat_GPIO_INPUT},
    { "IRQ",            NULL,         Luat_GPIO_IRQ},

    { "PULLUP",         NULL,         Luat_GPIO_PULLUP},
    { "PULLDOWN",       NULL,         Luat_GPIO_PULLDOWN},

    { "RISING",         NULL,         Luat_GPIO_RISING},
    { "FALLING",        NULL,         Luat_GPIO_FALLING},
    { "BOTH",           NULL,         Luat_GPIO_BOTH},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_gpio( lua_State *L ) {
    rotable_newlib(L, reg_gpio);
    return 1;
}
