
/*
@module  ir
@summary 红外遥控
@version 1.0
@date    2021.10.26
@demo ir
@tag LUAT_USE_IR
*/
#include "luat_base.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "ir"
#include "luat_log.h"

//发送指定数量脉冲，当pwm来用
static void send_pulse(int pin, size_t waith, size_t waitl, size_t count)
{
    while(count--)
    {
        luat_gpio_set(pin, Luat_GPIO_HIGH);
        luat_timer_us_delay(waith);
        luat_gpio_set(pin, Luat_GPIO_LOW);
        luat_timer_us_delay(waitl);
    }
}
#define IR_NEC_PWM_SEND_START(pin) send_pulse(pin, 7, 18, 375); luat_timer_us_delay(4500)
#define IR_NEC_PWM_SEND_REPEAT(pin) send_pulse(pin, 7, 18, 375); luat_timer_us_delay(2250); send_pulse(pin, 7, 17, 23)
#define IR_NEC_PWM_SEND_STOP(pin) send_pulse(pin, 7, 17, 23)
#define IR_NEC_PWM_SEND_0(pin) send_pulse(pin, 7, 17, 23); luat_timer_us_delay(560)
#define IR_NEC_PWM_SEND_1(pin) send_pulse(pin, 7, 17, 23); luat_timer_us_delay(1680)
static void ir_nec_pwm_send(int pin, uint8_t code)
{
    uint8_t c = 8;
    while(c--)
    {
        if(code & 0x01)
        {
            IR_NEC_PWM_SEND_1(pin);
        }
        else
        {
            IR_NEC_PWM_SEND_0(pin);
        }
        code = code >> 1;
    }
}
#define IR_NEC_SEND_START(pin)  luat_gpio_set(pin, Luat_GPIO_HIGH); \
                                luat_timer_us_delay(9000); \
                                luat_gpio_set(pin, Luat_GPIO_LOW); \
                                luat_timer_us_delay(4500)
#define IR_NEC_SEND_REPEAT(pin) luat_gpio_set(pin, Luat_GPIO_HIGH); \
                                luat_timer_us_delay(9000); \
                                luat_gpio_set(pin, Luat_GPIO_LOW); \
                                luat_timer_us_delay(2250); \
                                luat_gpio_set(pin, Luat_GPIO_HIGH); \
                                luat_timer_us_delay(560); \
                                luat_gpio_set(pin, Luat_GPIO_LOW)
#define IR_NEC_SEND_STOP(pin)   luat_gpio_set(pin, Luat_GPIO_HIGH); \
                                luat_timer_us_delay(560); \
                                luat_gpio_set(pin, Luat_GPIO_LOW)
#define IR_NEC_SEND_0(pin)  luat_gpio_set(pin, Luat_GPIO_HIGH); \
                            luat_timer_us_delay(560); \
                            luat_gpio_set(pin, Luat_GPIO_LOW); \
                            luat_timer_us_delay(560)
#define IR_NEC_SEND_1(pin)  luat_gpio_set(pin, Luat_GPIO_HIGH); \
                            luat_timer_us_delay(560); \
                            luat_gpio_set(pin, Luat_GPIO_LOW); \
                            luat_timer_us_delay(1690)
static void ir_nec_send(int pin, uint8_t code)
{
    uint8_t c = 8;
    while(c--)
    {
        if(code & 0x01)
        {
            IR_NEC_SEND_1(pin);
        }
        else
        {
            IR_NEC_SEND_0(pin);
        }
        code = code >> 1;
    }
}

/**
发送NEC数据
@api ir.sendNEC(pin, addr, cmd, repeat, disablePWM)
@int 使用的GPIO引脚编号
@int 用户码（大于0xff则采用Extended NEC模式）
@int 数据码
@int 可选，引导码发送次数（110ms一次），默认0次
@bool 可选，是否禁止直接发送pwm波，默认false
@usage
--直接发
ir.sendNEC(0, 0x11, 0x22)
--外接了38K的PWM载波，只控制电平
ir.sendNEC(0, 0x11, 0x22,0,true)
 */
static int l_ir_send_nec(lua_State *L) {
    uint8_t code1,code2,data1,data2;
    int pin = luaL_checkinteger(L, 1);
    int code = luaL_checkinteger(L, 2);
    if(code > 0xFF)
    {
        code1 = code % 256;
        code2 = code / 256;
    }
    else
    {
        code1 = code;
        code2 = ~code;
    }
    data1 = luaL_checkinteger(L, 3);
    data2 = ~data1;
    int count = luaL_optinteger(L, 4, 0);
    int pwm = !lua_toboolean(L, 5);
    luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    //38k载波，每周期26.31us
    //推荐载波占空比为1/3至1/4
    //此处高电平7us,低电平19us
    //http://www.taichi-maker.com/homepage/reference-index/arduino-library-index/irremote-library/nec-ir/
    luat_os_entry_cri();
    if(pwm)
    {
        IR_NEC_PWM_SEND_START(pin);
        ir_nec_pwm_send(pin, code1);
        ir_nec_pwm_send(pin, code2);
        ir_nec_pwm_send(pin, data1);
        ir_nec_pwm_send(pin, data2);
        while (count--)
        {
            IR_NEC_PWM_SEND_REPEAT(pin);
            luat_timer_us_delay(110000);
        }
        IR_NEC_PWM_SEND_STOP(pin);
    }
    else
    {
        IR_NEC_SEND_START(pin);
        ir_nec_send(pin, code1);
        ir_nec_send(pin, code2);
        ir_nec_send(pin, data1);
        ir_nec_send(pin, data2);
        while (count--)
        {
            IR_NEC_SEND_REPEAT(pin);
            luat_timer_us_delay(110000);
        }
        IR_NEC_SEND_STOP(pin);
    }
    luat_os_exit_cri();
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_ir[] =
{
    { "sendNEC" ,    ROREG_FUNC(l_ir_send_nec)},
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_ir( lua_State *L ) {
    luat_newlib2(L, reg_ir);
    return 1;
}
