
/*
@module  max30102
@summary 心率模块(MAX30102)
@version 1.0
@date    2023.2.28
@tag LUAT_USE_MAX30102
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_rtos.h"

#include "MAX30102.h"
#include "algorithm.h"

#define LUAT_LOG_TAG "max30102"
#include "luat_log.h"

uint8_t max30102_i2c_id;
static uint8_t max30102_int;
static uint64_t max30102_idp;

#define MAX30102_CHIP_ID        0x15

#define SAMP_BUFF_LEN   1000
#define AVG_BUFF_LEN    37

/*
初始化MAX30102传感器
@api max30102.init(i2c_id,int)
@int 传感器所在的i2c总线id,默认为0
@int int引脚
@return bool 成功返回true, 否则返回nil或者false
@usage
if max30102.init(0,pin.PC05) then
    log.info("max30102", "init ok")
else
    log.info("max30102", "init fail")
end
*/
static int l_max30102_init(lua_State *L){
    uint8_t cmd,uch_dummy;
    max30102_i2c_id = luaL_optinteger(L, 1 , 0);
    max30102_int = luaL_checkinteger(L, 2);
    maxim_max30102_read_reg(REG_PART_ID, &cmd);
    if (cmd == MAX30102_CHIP_ID){
        luat_gpio_mode(max30102_int,LUAT_GPIO_INPUT, LUAT_GPIO_PULLUP, LUAT_GPIO_HIGH);
        maxim_max30102_reset();
        luat_timer_mdelay(20);
        maxim_max30102_read_reg(REG_INTR_STATUS_1,&uch_dummy);
        maxim_max30102_init();  //initializes the MAX30102
        luat_timer_mdelay(20);
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

luat_rtos_task_handle max30102_task_handle = NULL;

static int32_t l_max30102_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pushboolean(L, 1);
    lua_pushinteger(L, msg->arg1);
    lua_pushinteger(L, msg->arg2);
    luat_cbcwait(L, max30102_idp, 3);
    max30102_idp = 0;
    return 0;
}

void max30102_task(void *param){
    uint64_t red_sum = 0, ir_sum = 0;
    uint8_t red_avg_len = 0,ir_avg_len = 0;
    int32_t red_min = 0x3FFFF, red_max = 0,ir_min = 0x3FFFF, ir_max = 0, HR = 0,SpO2 = 0;

    uint32_t* samples_buffer = luat_heap_malloc(sizeof(uint32_t) * SAMP_BUFF_LEN * 2);
    if (samples_buffer == NULL) {
        LLOGE("out of memory");
        return;
    }
    int32_t* avg_buffer = luat_heap_malloc(sizeof(int32_t) * AVG_BUFF_LEN * 2);
    if (avg_buffer == NULL) {
        LLOGE("out of memory");
        luat_heap_free(samples_buffer);
        return;
    }

    for(size_t i=0;i<SAMP_BUFF_LEN;i++){
        while(luat_gpio_get(max30102_int) == 1){luat_timer_mdelay(1);}   //wait until the interrupt pin asserts
        maxim_max30102_read_fifo((samples_buffer+i), (samples_buffer+SAMP_BUFF_LEN+i));  //read from MAX30102 FIFO
    }

    for (size_t i = 0; i < AVG_BUFF_LEN; i++){
        int32_t sp02,heart;
        int8_t spo2_valid = 0,heart_valid = 0;
        maxim_heart_rate_and_oxygen_saturation(samples_buffer+SAMP_BUFF_LEN+i*25, 100, samples_buffer+i*25, &sp02, &spo2_valid, &heart, &heart_valid); 
        if (heart_valid == 1 && heart > 30 && heart < 150){
            avg_buffer[red_avg_len] = heart;
            red_avg_len++;
            if (heart<red_min) red_min = heart;
            if (heart>red_max) red_max = heart;
            red_sum += heart;
        }
        if (spo2_valid == 1 && sp02 > 90 && sp02 < 100){
            avg_buffer[ir_avg_len + AVG_BUFF_LEN] = sp02;
            ir_avg_len++;
            if (sp02<ir_min) ir_min = sp02;
            if (sp02>ir_max) ir_max = sp02;
            ir_sum += sp02;
        }
    }
    if (red_avg_len){
        HR = (red_sum - red_min - red_max) / (red_avg_len-2);
    }
    if (ir_avg_len){
        SpO2 = (ir_sum - ir_min - ir_max) / (ir_avg_len-2);
    }
    luat_heap_free(samples_buffer);
    luat_heap_free(avg_buffer);
    if (HR!=0 && SpO2!=0){
        rtos_msg_t msg = {
            .handler = l_max30102_callback,
            .arg1 = HR,
            .arg2 = SpO2
        };
        luat_msgbus_put(&msg, 0);
    }else{
        luat_cbcwait_noarg(max30102_idp);
        max30102_idp = 0;
    }
    luat_rtos_task_delete(max30102_task_handle);
}

/*
获取心率血氧(大概需要10s时间测量)
@api max30102.get()
@return bool 成功返回true, 否则返回nil或者false
@return number 心率
@return number 血氧
*/
static int l_max30102_get(lua_State *L) {
    if (max30102_idp){
        lua_pushboolean(L, 0);
        luat_pushcwait_error(L,1);
    }else{
        max30102_idp = luat_pushcwait(L);
        luat_rtos_task_create(&max30102_task_handle, 1024, 50, "max30102", max30102_task, NULL, 0);
    }
    return 1;
}

// /*
// 获取max30102温度
// @api max30102.temp()
// @return number 温度
// */
// static int l_max30102_temp(lua_State *L) {
//     int8_t temp_intr,temp_frac;
//     float temp;
//     maxim_max30102_read_reg(REG_TEMP_INTR, &temp_intr);
//     maxim_max30102_read_reg(REG_TEMP_FRAC, &temp_frac);
//     LLOGD("l_max30102_temp %d %d",temp_intr,temp_frac);
//     temp = temp_intr + temp_frac  * 0.0625;
//     lua_pushnumber(L, temp);
//     return 1;
// }

/*
关闭max30102
@api max30102.shutdown()
*/
static int l_max30102_shutdown(lua_State *L) {
    maxim_max30102_shutdown();
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_max30102[] =
{
    {"init",        ROREG_FUNC(l_max30102_init)},
    {"get",         ROREG_FUNC(l_max30102_get)},
    // {"temp",        ROREG_FUNC(l_max30102_temp)},
    {"shutdown",    ROREG_FUNC(l_max30102_shutdown)},

	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_max30102( lua_State *L ) {
    luat_newlib2(L, reg_max30102);
    return 1;
}
