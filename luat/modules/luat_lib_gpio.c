
/*
@module  gpio
@summary GPIO操作
@catalog 外设API
@version 1.0
@date    2020.03.30
@demo gpio
@video https://www.bilibili.com/video/BV1hr4y1p7dt
*/
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "gpio"
#include "luat_log.h"

static int l_gpio_set(lua_State *L);
static int l_gpio_get(lua_State *L);
static int l_gpio_close(lua_State *L);
#ifdef LUAT_GPIO_NUMS
#define GPIO_IRQ_COUNT LUAT_GPIO_NUMS
#else
#define GPIO_IRQ_COUNT 16
#endif
typedef struct luat_lib_gpio_cb
{
    int pin;
    int lua_ref;
} luat_lib_gpio_cb_t;

// 保存中断回调的数组
static luat_lib_gpio_cb_t irq_cbs[GPIO_IRQ_COUNT];
static uint8_t default_gpio_pull = Luat_GPIO_DEFAULT;


// 记录GPIO电平,仅OUTPUT时可用
#define PIN_MAX (128)
static uint8_t gpio_out_levels[PIN_MAX / 8] = {0};

static uint8_t gpio_bit_get(int pin) {
    if (pin < 0 || pin >= PIN_MAX)
        return 0;
    return (gpio_out_levels[pin/8] >> (pin%8)) & 0x01;
}

static void gpio_bit_set(int pin, uint8_t value) {
    if (pin < 0 || pin >= PIN_MAX)
        return;
    uint8_t val = (gpio_out_levels[pin/8] >> (pin%8)) & 0x01;
    if (val == value)
        return; // 不变呀
    if (value == 0) {
        gpio_out_levels[pin/8] -= (1 << (pin%8));
    }
    else {
        gpio_out_levels[pin/8] += (1 << (pin%8));
    }
}

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
-- 设置gpio17为输出
gpio.setup(17, 0)
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
    conf.irq_cb = 0;
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
    int pin = 0;
    int value = 0;
    if (lua_isinteger(L, lua_upvalueindex(1))) {
        pin = lua_tointeger(L, lua_upvalueindex(1));
        value = luaL_checkinteger(L, 1);
    }
    else {
        pin = luaL_checkinteger(L, 1);
        value = luaL_checkinteger(L, 2);
    }
    luat_gpio_set(pin, value);
    gpio_bit_set(pin, (uint8_t)value);
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

/*
变换GPIO脚输出电平,仅输出模式可用
@api gpio.toggle(pin)
@int 管脚的GPIO0AB4276E.png
@return nil 无返回值
@usage
-- 本API于 2022.05.17 添加
-- 假设GPIO16上有LED, 每500ms切换一次开关
gpio.setup(16, 0)
sys.timerLoopStart(function()
    gpio.toggle(16)
end, 500)
*/
static int l_gpio_toggle(lua_State *L) {
    int pin = 0;
    if (lua_isinteger(L, lua_upvalueindex(1)))
        pin = lua_tointeger(L, lua_upvalueindex(1));
    else
        pin = luaL_checkinteger(L, 1);
    if (pin < 0 || pin >= PIN_MAX) {
        LLOGD("pin id out of range (0-127)");
        return 0;
    }
    uint8_t value = gpio_bit_get(pin);
    luat_gpio_set(pin, value == 0 ? Luat_GPIO_HIGH : Luat_GPIO_LOW);
    gpio_bit_set(pin, value == 0 ? 1 : 0);
    return 0;
}

/*
在同一个GPIO输出一组脉冲, 注意, len的单位是bit, 高位在前.
@api gpio.pulse(pin,level,len,delay)
@int gpio号
@int/string 数值或者字符串. 
@int len 长度 单位是bit, 高位在前.
@int delay 延迟,当前无固定时间单位
@return nil 无返回值
@usage
-- 通过PB06脚输出输出8个电平变化.
gpio.pulse(pin.PB06,0xA9, 8, 0)
*/
static int l_gpio_pulse(lua_State *L) {
    int pin,delay = 0;
    size_t len;
    char* level = NULL;
    if (lua_isinteger(L, lua_upvalueindex(1))){
        pin = lua_tointeger(L, lua_upvalueindex(1));
        if (lua_isinteger(L, 1)){
            *level = (char)luaL_checkinteger(L, 1);
        }else if (lua_isstring(L, 1)){
            level = (char*)luaL_checklstring(L, 1, &len);
        }
        len = luaL_checkinteger(L, 2);
        delay = luaL_checkinteger(L, 3);
    }else{
        pin = luaL_checkinteger(L, 1);
        if (lua_isinteger(L, 2)){
            *level = (char)luaL_checkinteger(L, 2);
        }else if (lua_isstring(L, 2)){
            level = (char*)luaL_checklstring(L, 2, &len);
        }
        len = luaL_checkinteger(L, 3);
        delay = luaL_checkinteger(L, 4);
    }
    if (pin < 0 || pin >= PIN_MAX) {
        LLOGD("pin id out of range (0-127)");
        return 0;
    }
    luat_gpio_pulse(pin,(uint8_t*)level,len,delay);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_gpio[] =
{
    { "setup" ,         ROREG_FUNC(l_gpio_setup )},
    { "set" ,           ROREG_FUNC(l_gpio_set)},
    { "get" ,           ROREG_FUNC(l_gpio_get)},
    { "close" ,         ROREG_FUNC(l_gpio_close)},
    { "toggle",         ROREG_FUNC(l_gpio_toggle)},
    { "setDefaultPull", ROREG_FUNC(l_gpio_set_default_pull)},
#ifndef LUAT_COMPILER_NOWEAK
    { "pulse",          ROREG_FUNC(l_gpio_pulse)},
#endif

    { "LOW",            ROREG_INT(Luat_GPIO_LOW)},
    { "HIGH",           ROREG_INT(Luat_GPIO_HIGH)},

    { "OUTPUT",         ROREG_INT(Luat_GPIO_OUTPUT)},
    { "INPUT",          ROREG_INT(Luat_GPIO_INPUT)},
    { "IRQ",            ROREG_INT(Luat_GPIO_IRQ)},

    { "PULLUP",         ROREG_INT(Luat_GPIO_PULLUP)},
    { "PULLDOWN",       ROREG_INT(Luat_GPIO_PULLDOWN)},

    { "RISING",         ROREG_INT(Luat_GPIO_RISING)},
    { "FALLING",        ROREG_INT(Luat_GPIO_FALLING)},
    { "BOTH",           ROREG_INT(Luat_GPIO_BOTH)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_gpio( lua_State *L ) {
    // int i;
    for (size_t i = 0; i < GPIO_IRQ_COUNT; i++) {
        irq_cbs[i].pin = -1;
    }
    luat_newlib2(L, reg_gpio);
    return 1;
}

// -------------------- 一些辅助函数

void luat_gpio_mode(int pin, int mode, int pull, int initOutput) {
    if (pin == 255) return;
    luat_gpio_t conf = {0};
    conf.pin = pin;
    conf.mode = mode == Luat_GPIO_INPUT ? Luat_GPIO_INPUT : Luat_GPIO_OUTPUT; // 只能是输入/输出, 不能是中断.
    conf.pull = pull;
    conf.irq = initOutput;
    conf.lua_ref = 0;
    conf.irq_cb = 0;
    luat_gpio_setup(&conf);
    if (conf.mode == Luat_GPIO_OUTPUT)
        luat_gpio_set(pin, initOutput);
}

#ifndef LUAT_COMPILER_NOWEAK
void LUAT_WEAK luat_gpio_pulse(int pin, uint8_t *level, uint16_t len, uint16_t delay_ns) {

}
#endif
