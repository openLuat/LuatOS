#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_timer.h"

typedef struct luat_statm_op {
    uint8_t tp;
    uint8_t arg1;
    uint8_t arg2;
    uint8_t arg3;
}luat_statm_op_t;

typedef struct luat_statem
{
    uint8_t id;
    int16_t repeat;
    uint16_t op_count;
    uint16_t pc;
    uint8_t gpio_input_offset;
    uint32_t gpio_inputs[8]; // 按位存储的GPIO输入值,共256位
    luat_statm_op_t op_list[1];
}luat_statem_t;

#define LUAT_SM_OP_END 0x00

#define LUAT_SM_OP_USLEEP 0x08
#define LUAT_SM_OP_GPIO_SET 0x80
#define LUAT_SM_OP_GPIO_GET 0x81

void luat_statem_init(luat_statem_t* sm);
void luat_statem_addop(luat_statem_t* sm, uint8_t tp, uint8_t arg1, uint8_t arg2, uint8_t arg3);
void luat_statem_exec(luat_statem_t* sm);
