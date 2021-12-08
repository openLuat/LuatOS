
/*
@module  gpio
@summary GPIO操作
@catalog 外设API
@version 1.0
@date    2020.03.30
*/
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "gpio"
#include "luat_log.h"

static int l_gpio_set(lua_State *L);
static int l_gpio_get(lua_State *L);
static int l_gpio_close(lua_State *L);

#define GPIO_IRQ_COUNT 16
typedef struct luat_lib_gpio_cb
{
    int pin;
    int lua_ref;
} luat_lib_gpio_cb_t;

// 保存中断回调的数组
static luat_lib_gpio_cb_t irq_cbs[GPIO_IRQ_COUNT];
static uint8_t default_gpio_pull = Luat_GPIO_DEFAULT;

int l_gpio_handler(lua_State *L, void* ptr) {
    // 给 sys.publish方法发送数据
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int pin = msg->arg1;
    for (size_t i = 0; i < GPIO_IRQ_COUNT; i++)
    {
        if (irq_cbs[i].pin == pin) {
            lua_geti(L, LUA_REGISTRYINDEX, irq_cbs[i].lua_ref);
            if (!lua_isnil(L, -1)) {
                lua_pushinteger(L, msg->arg2);
                lua_call(L, 1, 0);
            }
            return 0;
        }
    }
    return 0;
}

/*
设置管脚功能
@api gpio.setup(pin, mode, pull, irq)
@int pin 针脚编号,必须是数值
@any mode 输入输出模式. 数字0/1代表输出模式,nil代表输入模式,function代表中断模式
@int pull 上拉下列模式, 可以是gpio.PULLUP 或 gpio.PULLDOWN, 需要根据实际硬件选用
@int irq 默认gpio.BOTH。中断触发模式, 上升沿gpio.RISING, 下降沿gpio.FALLING, 上升和下降都要gpio.BOTH
@return any 输出模式返回设置电平的闭包, 输入模式和中断模式返回获取电平的闭包
@usage
-- 设置gpio17为输入
gpio.setup(17, nil)
@usage
-- 设置gpio17为输出
gpio.setup(17, 0)
@usage
-- 设置gpio27为中断
gpio.setup(27, function(val) print("IRQ_27",val) end, gpio.PULLUP)
*/
static int l_gpio_setup(lua_State *L) {
    luat_gpio_t conf;
    conf.pin = luaL_checkinteger(L, 1);
    //conf->mode = luaL_checkinteger(L, 2);
    conf.lua_ref = 0;
    conf.irq = 0;
    if (lua_isfunction(L, 2)) {
        conf.mode = Luat_GPIO_IRQ;
        lua_pushvalue(L, 2);
        conf.lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        conf.irq = luaL_optinteger(L, 4, Luat_GPIO_BOTH);
    }
    else if (lua_isinteger(L, 2)) {
        conf.mode = Luat_GPIO_OUTPUT;
        conf.irq = luaL_checkinteger(L, 2) == 0 ? 0 : 1; // 重用irq当初始值用
    }
    else {
        conf.mode = Luat_GPIO_INPUT;
    }
    conf.pull = luaL_optinteger(L, 3, default_gpio_pull);
    int re = luat_gpio_setup(&conf);
    if (re == 0) {
        if (conf.mode == Luat_GPIO_IRQ) {
            int flag = 1;
            for (size_t i = 0; i < GPIO_IRQ_COUNT; i++) {
                if (irq_cbs[i].pin == conf.pin) {
                    if (irq_cbs[i].lua_ref && irq_cbs[i].lua_ref != conf.lua_ref) {
                        luaL_unref(L, LUA_REGISTRYINDEX, irq_cbs[i].lua_ref);
                        irq_cbs[i].lua_ref = conf.lua_ref;
                    }
                    flag = 0;
                    break;
                }
                if (irq_cbs[i].pin == -1) {
                    irq_cbs[i].pin = conf.pin;
                    irq_cbs[i].lua_ref = conf.lua_ref;
                    flag = 0;
                    break;
                }
            }
            if (flag) {
                LLOGE("luat.gpio", "too many irq setup!!!!");
                re = 1;
                luat_gpio_close(conf.pin);
            }
        }
        else if (conf.mode == Luat_GPIO_OUTPUT) {
            luat_gpio_set(conf.pin, conf.irq); // irq被重用为OUTPUT的初始值
        }
    }
    // 生成闭包包
    if (re != 0) {
        return 0;
    }
    lua_settop(L, 1);
    if (conf.mode == Luat_GPIO_OUTPUT) {
        lua_pushcclosure(L, l_gpio_set, 1);
    }
    else {
        lua_pushcclosure(L, l_gpio_get, 1);
    }
    return 1;
}

/*
设置管脚电平
@api gpio.set(pin, value)
@int pin 针脚编号,必须是数值
@int value 电平, 可以是 高电平gpio.HIGH, 低电平gpio.LOW, 或者直接写数值1或0
@return nil 无返回值
@usage
-- 设置gpio17为低电平
gpio.set(17, 0)
*/
static int l_gpio_set(lua_State *L) {
    if (lua_isinteger(L, lua_upvalueindex(1)))
        luat_gpio_set(lua_tointeger(L, lua_upvalueindex(1)), luaL_checkinteger(L, 1));
    else
        luat_gpio_set(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2));
    return 0;
}

/*
获取管脚电平
@api gpio.get(pin)
@int pin 针脚编号,必须是数值
@return value 电平, 高电平gpio.HIGH, 低电平gpio.LOW, 对应数值1和0
@usage
-- 获取gpio17的当前电平
gpio.get(17)
*/
static int l_gpio_get(lua_State *L) {
    if (lua_isinteger(L, lua_upvalueindex(1)))
        lua_pushinteger(L, luat_gpio_get(luaL_checkinteger(L, lua_upvalueindex(1))) & 0x01 ? 1 : 0);
    else
        lua_pushinteger(L, luat_gpio_get(luaL_checkinteger(L, 1)) & 0x01 ? 1 : 0);
    return 1;
}

/*
关闭管脚功能(高阻输入态),关掉中断
@api gpio.close(pin)
@int pin 针脚编号,必须是数值
@return nil 无返回值,总是执行成功
@usage
-- 关闭gpio17
gpio.close(17)
*/
static int l_gpio_close(lua_State *L) {
    int pin = luaL_checkinteger(L, 1);
    luat_gpio_close(pin);
    for (size_t i = 0; i < GPIO_IRQ_COUNT; i++) {
        if (irq_cbs[i].pin == pin) {
            irq_cbs[i].pin = -1;
            if (irq_cbs[i].lua_ref) {
                luaL_unref(L, LUA_REGISTRYINDEX, irq_cbs[i].lua_ref);
                irq_cbs[i].lua_ref = 0;
            }
        }
    }
    return 0;
}

/*
设置GPIO脚的默认上拉/下拉设置, 默认是平台自定义(一般为开漏).
@api gpio.setDefaultPull(val)
@int val 0平台自定义,1上拉, 2下拉
@return boolean 传值正确返回true,否则返回false
@usage
-- 设置gpio.setup的pull默认值为上拉
gpio.setDefaultPull(1)
*/
static int l_gpio_set_default_pull(lua_State *L) {
    int value = luaL_checkinteger(L, 1);
    if (value >= 0 && value <= 2) {
        default_gpio_pull = value;
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_gpio[] =
{
    { "setup" ,         l_gpio_setup ,0},
    { "set" ,           l_gpio_set,   0},
    { "get" ,           l_gpio_get,   0 },
    { "close" ,         l_gpio_close, 0 },
    { "setDefaultPull", l_gpio_set_default_pull, 0},

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
    // int i;
    for (size_t i = 0; i < GPIO_IRQ_COUNT; i++) {
        irq_cbs[i].pin = -1;
    }
    luat_newlib(L, reg_gpio);
    return 1;
}

// -------------------- 一些辅助函数

void luat_gpio_mode(int pin, int mode, int pull, int initOutput) {
    luat_gpio_t conf = {0};
    conf.pin = pin;
    conf.mode = mode == Luat_GPIO_INPUT ? Luat_GPIO_INPUT : Luat_GPIO_OUTPUT; // 只能是输入/输出, 不能是中断.
    conf.pull = pull;
    conf.irq = initOutput;
    conf.lua_ref = 0;
    luat_gpio_setup(&conf);
    if (conf.mode == Luat_GPIO_OUTPUT)
        luat_gpio_set(pin, initOutput);
}
