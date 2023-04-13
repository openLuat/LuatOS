
/*
@module  ioqueue
@summary io序列操作
@version 1.0
@date    2022.03.13
@demo io_queue
@tag LUAT_USE_IO_QUEUE
*/
#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "io_queue"
#include "luat_log.h"
int l_io_queue_done_handler(lua_State *L, void* ptr)
{
	rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
	lua_pop(L, 1);
	lua_getglobal(L, "sys_pub");
	lua_pushfstring(L, "IO_QUEUE_DONE_%d", msg->ptr);
	lua_call(L, 1, 0);
	return 1;
}

int l_io_queue_capture_handler(lua_State *L, void* ptr)
{
	volatile uint64_t tick;
	uint32_t pin;
	uint32_t val;
	rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
	lua_getglobal(L, "sys_pub");
	pin = ((uint32_t)msg->ptr >> 8) & 0x000000ff;
	val = (uint32_t)msg->ptr & 0x00000001;
	tick = ((uint64_t)msg->arg1 << 32) | (uint32_t)msg->arg2;
//	LLOGD("%u, %x,%x, %llu",pin, msg->arg1, msg->arg2, tick);
	lua_pushfstring(L, "IO_QUEUE_EXTI_%d", pin);
	lua_pushinteger(L, val);
	lua_pushlstring(L, &tick, 8);
	lua_call(L, 3, 0);
	return 1;
}

/*
初始化一个io操作队列
@api  ioqueue.init(hwtimer_id,cmd_cnt,repeat_cnt)
@int  硬件定时器id，默认用0，根据实际MCU确定，air105为0~5，与pwm共用，同一个通道号不能同时为pwm和ioqueue
@int  一个完整周期需要的命令，可以比实际的多
@int  重复次数,默认是1，如果写0则表示无限次数循环
@return 无
@usage
ioqueue.init(0,10,5) --以timer0为时钟源初始化一个io操作队列，有10个有效命令，循环5次
*/
static int l_io_queue_init(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	int cmd_cnt = luaL_optinteger(L, 2, 0);
	int repeat_cnt = luaL_optinteger(L, 3, 1);
	luat_io_queue_init(timer_id, cmd_cnt, repeat_cnt);
	return 0;
}

/*
对io操作队列增加延时命令
@api  ioqueue.setdelay(hwtimer_id,time_us,time_tick,continue)
@int  硬件定时器id
@int  延时时间,0~65535us
@int  延时微调时间,0~255tick,总的延时时间是time_us * 1us_tick + time_tick
@boolean 是否连续是连续延时，默认否，如果是，定时器在时间到后不会停止而是重新计时，
从而实现在下一个setdelay命令前，每次调用delay都会重复相同时间延时，提高连续定时的精度
@return 无
@usage
ioqueue.setdelay(0,10,0) --延时10us+0个tick
ioqueue.setdelay(0,9,15,true) --延时9us+15个tick,在之后遇到delay命令时，会延时9us+15个tick
*/
static int l_io_queue_set_delay(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint16_t us_delay = luaL_optinteger(L, 2, 1);
	uint8_t us_delay_tick = luaL_optinteger(L, 3, 0);
	uint8_t is_continue = 0;
	if (lua_isboolean(L, 4))
	{
		is_continue = lua_toboolean(L, 4);
	}
	luat_io_queue_set_delay(timer_id, us_delay, us_delay_tick, is_continue);
	return 0;
}

/*
对io操作队列增加一次重复延时，在前面必须有setdelay且是连续延时
@api  ioqueue.delay(hwtimer_id)
@int  硬件定时器id
@return 无
@usage
ioqueue.setdelay(0,9,15,true) --延时9us+15个tick,在之后遇到delay命令时，会延时9us+15个tick
ioqueue.delay(0)
*/
static int l_io_queue_delay(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	luat_io_queue_repeat_delay(timer_id);
	return 0;
}



/*
对io操作队列增加设置gpio命令
@api  ioqueue.setgpio(hwtimer_id,pin,is_input,pull_mode,init_level)
@int  硬件定时器id
@int pin
@boolean  是否是输入
@int 上下拉模式,只能是0,gpio.PULLUP,gpio.PULLDOWN
@int 初始输出电平
@return 无
@usage
ioqueue.setgpio(0,pin.PB01,true,gpio.PULLUP,0) --PB01设置成上拉输入
ioqueue.setgpio(0,pin.PB01,false,0,1)--PB01设置成默认上下拉输出高电平
*/
static int l_io_queue_set_gpio(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint8_t pin = luaL_checkinteger(L, 2);
	uint8_t pull_mode = luaL_optinteger(L, 4, 0);
	uint8_t init_level = luaL_optinteger(L, 5, 0);
	uint8_t is_input = 0;
	if (lua_isboolean(L, 3))
	{
		is_input = lua_toboolean(L, 3);
	}

	luat_io_queue_add_io_config(timer_id, pin, is_input, pull_mode, init_level);
	return 0;
}

/*
对io操作队列增加读取gpio命令
@api  ioqueue.input(hwtimer_id,pin)
@int  硬件定时器id
@int pin
@return 无
@usage
ioqueue.input(0,pin.PB01)

*/
static int l_io_queue_gpio_input(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint8_t pin = luaL_checkinteger(L, 2);
	luat_io_queue_add_io_in(timer_id, pin, NULL, NULL);
	return 0;
}

/*
对io操作队列增加输出GPIO命令
@api  ioqueue.output(hwtimer_id,pin,level)
@int  硬件定时器id
@int pin
@int 输出电平
@return 无
@usage
ioqueue.output(0,pin.PB01,0)
*/
static int l_io_queue_gpio_output(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint8_t pin = luaL_checkinteger(L, 2);
	uint8_t level = luaL_optinteger(L, 3, 0);
	luat_io_queue_add_io_out(timer_id, pin, level);
	return 0;
}

/*
对io操作队列增加设置捕获某个IO命令
@api  ioqueue.setcap(hwtimer_id,pin,pull_mode,irq_mode,max_tick)
@int  硬件定时器id
@int  pin
@int 上下拉模式,只能是0,gpio.PULLUP,gpio.PULLDOWN
@int 中断模式,只能是gpio.BOTH,gpio.RISING,gpio.FALLING
@int 定时器最大计时时间 考虑到lua是int类型，最小0x10000, 最大值为0x7fffffff，默认为最大值
@return 无
@usage
ioqueue.setcap(0,pin.PB01,gpio.PULLUP,gpio.FALLING,48000000)
*/
static int l_io_queue_set_capture(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint8_t pin = luaL_checkinteger(L, 2);
	uint8_t pull_mode = luaL_optinteger(L, 3, 0);
	uint8_t irq_mode = luaL_optinteger(L, 4, 0);
	int max_cnt = luaL_optinteger(L, 5, 0x7fffffff);
	if (max_cnt < 65536)
	{
		max_cnt = 65536;
	}
	luat_io_queue_capture_set(timer_id, max_cnt, pin, pull_mode, irq_mode);
	return 0;
}

/*
对io操作队列增加捕获一次IO状态命令
@api  ioqueue.capture(hwtimer_id)
@int  硬件定时器id
@return 无
@usage
ioqueue.capture(0)
*/
static int l_io_queue_capture_pin(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	luat_io_queue_capture(timer_id, NULL, NULL);
	return 0;
}

/*
对io操作队列增加结束捕获某个IO命令
@api  ioqueue.capend(hwtimer_id,pin)
@int  硬件定时器id
@int  pin
@return 无
@usage
ioqueue.capend(0,pin.PB01)
*/
static int l_io_queue_capture_end(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint8_t pin = luaL_checkinteger(L, 2);
	luat_io_queue_capture_end(timer_id, pin);
	return 0;
}

/*
 * 获取io操作队列中输入和捕获的数据
@api  ioqueue.get(hwtimer_id, input_buff, capture_buff)
@int  硬件定时器id
@zbuff 存放IO输入数据的buff，按照1byte pin + 1byte level 形式存放数据
@zbuff 存放IO捕获数据的buff，按照1byte pin + 1byte level + 4byte tick形式存放数据
@return int 返回多少组IO输入数据
@return int 返回多少组IO捕获数据
@usage
local input_cnt, capture_cnt = ioqueue.get(0, input_buff, capture_buff)
*/
static int l_io_queue_get(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	luat_zbuff_t *buff1 = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
	luat_zbuff_t *buff2 = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
	uint32_t input_cnt, capture_cnt;
	uint32_t size = luat_io_queue_get_size(timer_id);
	if (buff1->len < (size * 2)) __zbuff_resize(buff1, (size * 2));
	if (buff2->len < (size * 6)) __zbuff_resize(buff2, (size * 6));
	luat_io_queue_get_data(timer_id, buff1->addr, &input_cnt, buff2->addr, &capture_cnt);
	buff1->used = input_cnt * 2;
	buff2->used = capture_cnt * 6;
	lua_pushinteger(L, input_cnt);
	lua_pushinteger(L, capture_cnt);
	return 2;
}

/*
启动io操作队列
@api  ioqueue.start(hwtimer_id)
@int  硬件定时器id
@return 无
@usage
ioqueue.start(0)
*/
static int l_io_queue_start(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	luat_io_queue_start(timer_id);
	return 0;
}

/*
停止io操作队列，可以通过start从头开始
@api  ioqueue.stop(hwtimer_id)
@int  硬件定时器id
@return int 返回已经循环的次数，如果是0，表示一次循环都没有完成
@return int 返回单次循环中已经执行的cmd次数，如果是0，可能是一次循环刚刚结束
@usage
ioqueue.stop(0)
*/
static int l_io_queue_stop(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	uint32_t repeat_cnt = 0;
	uint32_t cmd_cnt = 0;
	luat_io_queue_stop(timer_id, &repeat_cnt, &cmd_cnt);
	lua_pushinteger(L, repeat_cnt);
	lua_pushinteger(L, cmd_cnt);
	return 2;
}


/*
释放io操作队列的资源，下次使用必须重新init
@api  ioqueue.release(hwtimer_id)
@int  硬件定时器id
@return 无
@usage
ioqueue.clear(0)
*/
static int l_io_queue_release(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	luat_io_queue_release(timer_id);
	return 0;
}

/*
清空io操作队列
@api  ioqueue.clear(hwtimer_id)
@int  硬件定时器id
@return 无
@usage
ioqueue.clear(0)
*/
static int l_io_queue_clear(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	luat_io_queue_clear(timer_id);
	return 0;
}

/*
检测io操作队列是否已经执行完成
@api  ioqueue.done(hwtimer_id)
@int  硬件定时器id
@return boolean 队列是否执行完成，
@usage
local result = ioqueue.done(0)
*/
static int l_io_queue_is_done(lua_State *L) {
	uint8_t timer_id = luaL_optinteger(L, 1, 0);
	lua_pushboolean(L, luat_io_queue_check_done(timer_id));
	return 1;
}

/*
启动/停止一个带系统tick返回的外部中断
@api  ioqueue.exti(pin,pull_mode,irq_mode,onoff)
@int  pin
@int 上下拉模式,只能是0,gpio.PULLUP,gpio.PULLDOWN
@int 中断模式,只能是gpio.BOTH,gpio.RISING,gpio.FALLING
@boolean  开关，默认是false关
@return 无
@usage
ioqueue.exti(pin.PB01, gpio.PULLUP, gpio.BOTH, true)
ioqueue.exti(pin.PB01)
*/
static int l_io_queue_exti(lua_State *L) {
	uint8_t pin = luaL_checkinteger(L, 1);
	uint8_t pull_mode = luaL_optinteger(L, 2, 0);
	uint8_t irq_mode = luaL_optinteger(L, 3, 0);
	uint8_t on_off = 0;
	if (lua_isboolean(L, 4)) {
		on_off = lua_toboolean(L, 4);
	}
	if (on_off) {
		luat_io_queue_capture_start_with_sys_tick(pin, pull_mode, irq_mode);
	} else {
		luat_io_queue_capture_end_with_sys_tick(pin);
	}
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_io_queue[] =
{
    { "init" ,       ROREG_FUNC(l_io_queue_init)},
    { "setdelay" ,   ROREG_FUNC(l_io_queue_set_delay)},
	{ "delay" ,      ROREG_FUNC(l_io_queue_delay)},
	{ "setgpio",	 ROREG_FUNC(l_io_queue_set_gpio)},
	{ "input",		 ROREG_FUNC(l_io_queue_gpio_input)},
	{ "output",      ROREG_FUNC(l_io_queue_gpio_output)},
	{ "set_cap",     ROREG_FUNC(l_io_queue_set_capture)},
	{ "capture",     ROREG_FUNC(l_io_queue_capture_pin)},
	{ "cap_done",    ROREG_FUNC(l_io_queue_capture_end)},
	{ "clear",	     ROREG_FUNC(l_io_queue_clear)},
    { "start",       ROREG_FUNC(l_io_queue_start)},
    { "stop",        ROREG_FUNC(l_io_queue_stop)},
	{ "done",        ROREG_FUNC(l_io_queue_is_done)},
	{ "get",         ROREG_FUNC(l_io_queue_get)},
	{ "release",     ROREG_FUNC(l_io_queue_release)},
	{ "exti",        ROREG_FUNC(l_io_queue_exti)},
	{ NULL,          {}}
};

LUAMOD_API int luaopen_io_queue( lua_State *L ) {
    luat_newlib2(L, reg_io_queue);
    return 1;
}
