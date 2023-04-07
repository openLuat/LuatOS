
/*
@module  gpio
@summary GPIO操作
@catalog 外设API
@version 1.0
@date    2020.03.30
@demo gpio
@video https://www.bilibili.com/video/BV1hr4y1p7dt
@tag LUAT_USE_GPIO
*/
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_rtos.h"
#include <math.h>

#define LUAT_LOG_TAG "gpio"
#include "luat_log.h"

// 若bsp没有定义最大PIN编号, 那么默认给个128吧
#ifndef LUAT_GPIO_PIN_MAX
#define LUAT_GPIO_PIN_MAX (128)
#endif

static int l_gpio_set(lua_State *L);
static int l_gpio_get(lua_State *L);
static int l_gpio_close(lua_State *L);
int l_gpio_handler(lua_State *L, void* ptr) ;

typedef struct gpio_ctx
{
    int lua_ref; // irq下的回调函数
    uint32_t latest_tick; // 防抖功能的最后tick数
    uint16_t conf_tick;   // 防抖设置的超时tick数
    uint8_t debounce_mode;
    uint8_t latest_state;
    luat_rtos_timer_t timer;
}gpio_ctx_t;

// 保存中断回调的数组
static gpio_ctx_t gpios[LUAT_GPIO_PIN_MAX] __attribute__((aligned (16)));
static uint32_t default_gpio_pull = Luat_GPIO_DEFAULT;


// 记录GPIO电平,仅OUTPUT时可用
static uint8_t gpio_out_levels[(LUAT_GPIO_PIN_MAX + 7) / 8] __attribute__((aligned (16)));

static uint8_t gpio_bit_get(int pin) {
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX)
        return 0;
    return (gpio_out_levels[pin/8] >> (pin%8)) & 0x01;
}

static void gpio_bit_set(int pin, uint8_t value) {
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX)
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

int l_gpio_debounce_timer_handler(lua_State *L, void* ptr) {
    (void)L;
    (void)ptr;

    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int pin = msg->arg1;
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX)
        return 0; // 超范围, 内存异常
    if (gpios[pin].lua_ref == 0)
        return 0; // 早关掉了
    if (gpios[pin].latest_state != luat_gpio_get(pin))
        return 0; // 电平变了
    lua_geti(L, LUA_REGISTRYINDEX, gpios[pin].lua_ref);
    if (!lua_isnil(L, -1)) {
        lua_pushinteger(L, gpios[pin].latest_state);
        lua_call(L, 1, 0);
    }
    return 0;
}

#ifndef LUAT_RTOS_API_NOTOK
static LUAT_RT_RET_TYPE l_gpio_debounce_mode1_cb(LUAT_RT_CB_PARAM) {
    int pin = (int)param;
    rtos_msg_t msg = {0};
    msg.handler = l_gpio_debounce_timer_handler;
    msg.arg1 = pin;
    luat_msgbus_put(&msg, 0);
}
#endif

int luat_gpio_irq_default(int pin, void* args) {
    rtos_msg_t msg = {0};

    if (pin < 0 || pin >= Luat_GPIO_MAX_ID) {
        return 0;
    }

    if (pin < LUAT_GPIO_PIN_MAX && gpios[pin].conf_tick > 0) {
        // 防抖模式0, 触发后冷却N个ms
        if (gpios[pin].debounce_mode == 0) {
            uint32_t ticks = (uint32_t)luat_mcu_ticks();
            uint32_t diff = (ticks > gpios[pin].latest_tick) ? (ticks - gpios[pin].latest_tick) : (gpios[pin].latest_tick - ticks);
            if (diff >= gpios[pin].conf_tick) {
                gpios[pin].latest_tick = ticks;
            }
            else {
                // 防抖生效, 直接返回
            return 0;
            }
        }
        #ifndef LUAT_RTOS_API_NOTOK
        // 防抖模式1, 触发后延时N个ms, 电平依然不变才触发
        else if (gpios[pin].debounce_mode == 1) {
            if (gpios[pin].timer == NULL || gpios[pin].conf_tick == 0) {
                return 0; // timer被释放了?
            }
            gpios[pin].latest_state = luat_gpio_get(pin);
            luat_rtos_timer_stop(gpios[pin].timer);
            luat_rtos_timer_start(gpios[pin].timer, gpios[pin].conf_tick, 0, l_gpio_debounce_mode1_cb, (void*)pin);
            return 0;
        }
        #endif
    }

    msg.handler = l_gpio_handler;
    msg.ptr = NULL;
    msg.arg1 = pin;
    msg.arg2 = (int)args;
    return luat_msgbus_put(&msg, 0);
}

int l_gpio_handler(lua_State *L, void* ptr) {
    (void)ptr; // unused
    // 给 sys.publish方法发送数据
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int pin = msg->arg1;
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX)
        return 0;
    if (gpios[pin].lua_ref == 0)
        return 0;
    lua_geti(L, LUA_REGISTRYINDEX, gpios[pin].lua_ref);
    if (!lua_isnil(L, -1)) {
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 1, 0);
    }
    return 0;
}

/*
设置管脚功能
@api gpio.setup(pin, mode, pull, irq)
@int pin gpio编号,必须是数值
@any mode 输入输出模式：<br>数字0/1代表输出模式<br>nil代表输入模式<br>function代表中断模式
@int pull 上拉下列模式, 可以是gpio.PULLUP 或 gpio.PULLDOWN, 需要根据实际硬件选用
@int irq 中断触发模式,默认gpio.BOTH。中断触发模式<br>上升沿gpio.RISING<br>下降沿gpio.FALLING<br>上升和下降都触发gpio.BOTH 
@return any 输出模式返回设置电平的闭包, 输入模式和中断模式返回获取电平的闭包
@usage
-- 设置gpio17为输入
gpio.setup(17, nil)
-- 设置gpio17为输出,且初始化电平为低,使用硬件默认上下拉配置
gpio.setup(17, 0)
-- 设置gpio17为输出,且初始化电平为高,且启用内部上拉
gpio.setup(17, 1, gpio.PULLUP)
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
    if (re != 0) {
        LLOGW("gpio setup fail pin=%d", conf.pin);
        return 0;
    }
    if (conf.mode == Luat_GPIO_IRQ) {
        if (gpios[conf.pin].lua_ref && gpios[conf.pin].lua_ref != conf.lua_ref) {
            luaL_unref(L, LUA_REGISTRYINDEX, gpios[conf.pin].lua_ref);
            gpios[conf.pin].lua_ref = conf.lua_ref;
        }
        gpios[conf.pin].lua_ref = conf.lua_ref;
    }
    else if (conf.mode == Luat_GPIO_OUTPUT) {
        luat_gpio_set(conf.pin, conf.irq); // irq被重用为OUTPUT的初始值
    }
    // 生成闭包
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
@int pin GPIO编号,必须是数值
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
@int pin GPIO编号,必须是数值
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
@int pin GPIO编号,必须是数值
@return nil 无返回值,总是执行成功
@usage
-- 关闭gpio17
gpio.close(17)
*/
static int l_gpio_close(lua_State *L) {
    int pin = luaL_checkinteger(L, 1);
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX)
        return 0;
    luat_gpio_close(pin);
    if (gpios[pin].lua_ref) {
        luaL_unref(L, LUA_REGISTRYINDEX, gpios[pin].lua_ref);
        gpios[pin].lua_ref = 0;
    }
#ifndef LUAT_RTOS_API_NOTOK
    if (gpios[pin].timer != NULL) {
        gpios[pin].conf_tick = 0;
        luat_rtos_timer_stop(gpios[pin].timer);
        luat_rtos_timer_delete(gpios[pin].timer);
        gpios[pin].timer = NULL;
    }
#endif
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
@int 管脚的GPIO号
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
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX) {
        LLOGW("pin id out of range (0-127)");
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
    char tmp;
    size_t len;
    char* level = NULL;
    if (lua_isinteger(L, lua_upvalueindex(1))){
        pin = lua_tointeger(L, lua_upvalueindex(1));
        if (lua_isinteger(L, 1)){
            tmp = (char)luaL_checkinteger(L, 1);
            level = &tmp;
        }else if (lua_isstring(L, 1)){
            level = (char*)luaL_checklstring(L, 1, &len);
        }
        len = luaL_checkinteger(L, 2);
        delay = luaL_checkinteger(L, 3);
    } else {
        pin = luaL_checkinteger(L, 1);
        if (lua_isinteger(L, 2)){
            tmp = (char)luaL_checkinteger(L, 2);
            level = &tmp;
        }else if (lua_isstring(L, 2)){
            level = (char*)luaL_checklstring(L, 2, &len);
        }
        len = luaL_checkinteger(L, 3);
        delay = luaL_checkinteger(L, 4);
    }
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX) {
        LLOGD("pin id out of range (0-127)");
        return 0;
    }
    luat_gpio_pulse(pin,(uint8_t*)level,len,delay);
    return 0;
}

/*
防抖设置, 根据硬件ticks进行防抖
@api gpio.debounce(pin, ms, mode)
@int gpio号, 0~127, 与硬件相关
@int 防抖时长,单位毫秒, 最大 65555 ms, 设置为0则关闭
@int 模式, 0冷却模式, 1延时模式. 默认是0
@return nil 无返回值
@usage
-- 消抖模式, 当前支持2种, 2022.12.16开始支持mode=1
-- 0 触发中断后,马上上报一次, 然后冷却N个毫秒后,重新接受中断
-- 1 触发中断后,延迟N个毫秒,期间没有新中断且电平没有变化,上报一次

-- 开启防抖, 模式0-冷却, 中断后马上上报, 但100ms内只上报一次
gpio.debounce(7, 100) -- 若芯片支持pin库, 可用pin.PA7代替数字7
-- 开启防抖, 模式1-延时, 中断后等待100ms,期间若保持该电平了,时间到之后上报一次
-- 对应的,如果输入的是一个 50hz的方波,那么不会触发任何上报
gpio.debounce(7, 100, 1)

-- 关闭防抖,时间设置为0就关闭
gpio.debounce(7, 0)
*/
static int l_gpio_debounce(lua_State *L) {
    uint8_t pin = luaL_checkinteger(L, 1);
    uint16_t timeout = luaL_checkinteger(L, 2);
    uint8_t mode = luaL_optinteger(L, 3, 0);
    if (pin >= LUAT_GPIO_PIN_MAX) {
        LLOGW("MUST pin < 128");
        return 0;
    }
    //LLOGD("debounce %d %d %d", pin, timeout, mode);
    gpios[pin].conf_tick = timeout;
    gpios[pin].latest_tick = 0;
    gpios[pin].debounce_mode = mode;
#ifndef LUAT_RTOS_API_NOTOK
    if ((mode == 0 && gpios[pin].timer != NULL) || timeout == 0) {
        luat_rtos_timer_stop(gpios[pin].timer);
        luat_rtos_timer_delete(gpios[pin].timer);
        gpios[pin].timer = NULL;
    }
    else if (mode == 1 && gpios[pin].timer == NULL && timeout > 0) {
        //LLOGD("GPIO debounce mode 1 %d %d", pin, timeout);
        if (gpios[pin].timer == NULL)
            luat_rtos_timer_create(&gpios[pin].timer);
        if (gpios[pin].timer == NULL) {
            LLOGE("out of memory when malloc debounce timer");
            return 0;
        }
    }
#endif
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
    { "debounce",       ROREG_FUNC(l_gpio_debounce)},
    { "pulse",          ROREG_FUNC(l_gpio_pulse)},
    { "setDefaultPull", ROREG_FUNC(l_gpio_set_default_pull)},

    //@const LOW number 低电平
    { "LOW",            ROREG_INT(Luat_GPIO_LOW)},
    //@const HIGH number 高电平
    { "HIGH",           ROREG_INT(Luat_GPIO_HIGH)},

    { "OUTPUT",         ROREG_INT(Luat_GPIO_OUTPUT)}, // 留着做兼容

    //@const PULLUP number 上拉
    { "PULLUP",         ROREG_INT(Luat_GPIO_PULLUP)},
    //@const PULLDOWN number 下拉
    { "PULLDOWN",       ROREG_INT(Luat_GPIO_PULLDOWN)},

    //@const RISING number 上升沿触发
    { "RISING",         ROREG_INT(Luat_GPIO_RISING)},
    //@const FALLING number 下降沿触发
    { "FALLING",        ROREG_INT(Luat_GPIO_FALLING)},
    //@const BOTH number 双向触发,部分设备支持
    { "BOTH",           ROREG_INT(Luat_GPIO_BOTH)},
    //@const HIGH_IRQ number 高电平触发,部分设备支持
    { "HIGH_IRQ",       ROREG_INT(Luat_GPIO_HIGH_IRQ)},
    //@const LOW_IRQ number 低电平触发,部分设备支持
    { "LOW_IRQ",        ROREG_INT(Luat_GPIO_LOW_IRQ)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_gpio( lua_State *L ) {
    memset(gpios, 0, sizeof(gpio_ctx_t) * LUAT_GPIO_PIN_MAX);
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
