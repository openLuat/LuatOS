#include "luat_statem.h"

void luat_statem_init(luat_statem_t* sm) {
    memset(sm, 0, sizeof(luat_statem_t) + 4 * (sm->op_count - 1));
}

void luat_statem_addop(luat_statem_t* sm, uint8_t tp, uint8_t arg1, uint8_t arg2, uint8_t arg3) {
    sm->op_list[sm->pc].tp = tp;
    sm->op_list[sm->pc].arg1 = arg1;
    sm->op_list[sm->pc].arg2 = arg2;
    sm->op_list[sm->pc].arg3 = arg3;
    sm->pc ++;
}

void luat_statem_exec(luat_statem_t* sm) {
    luat_statm_op_t* op = NULL;
    int value = 0;
    for (sm->pc = 0; sm->pc < sm->op_count; sm->pc++)
    {
        op = (luat_statm_op_t*)(sm->op_list + sm->pc);
        if (op == NULL || op->tp == LUAT_SM_OP_END)
            break;

        switch (op->tp)
        {
        case LUAT_SM_OP_USLEEP:
            luat_timer_us_delay(op->arg1);
            break;
        case LUAT_SM_OP_GPIO_GET:
            value = luat_gpio_get(op->arg1);
            if (sm->gpio_input_offset < 256) {
                if (value) {
                    sm->gpio_inputs[(sm->gpio_input_offset) /32] |= 1 << (sm->gpio_input_offset & 0x1F);
                }
                sm->gpio_input_offset ++;
            }
            break;
        case LUAT_SM_OP_GPIO_SET:
            luat_gpio_set(op->arg1, op->arg2);
            break;
        default:
            break;
        }
    }
}
