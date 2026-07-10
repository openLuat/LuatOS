#include "luat_base.h"
#include "luat_display.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "display"
#include "luat_log.h"

/*显示组件*/
static luat_display_t *display_component[LUAT_DISPLAY_COMPONENT_COUNT] = { 0 };

void luat_display_execute_cmds(luat_display_t *disp) 
{
    // uint16_t cmd = 0;
    // uint8_t cmd_send = 0;
    // uint8_t cmd_len = 0;
    // uint8_t cmds[32] = {0};
    // for (size_t i = 0; i < disp->panel_ops->init_cmds_len; i++) {
    //     cmd = disp->panel_ops->init_cmds[i];
    //     switch ((cmd >> 8) & 0xFF) {
    //         case 0x00:
    //         case 0x02:
    //             if (i != 0) {
    //                 luat_display_write_cmd_data(disp, cmd_send, cmd_len ? cmds : NULL, cmd_len);
    //             }
    //             cmd_send = (uint8_t)(cmd & 0xFF);
    //             cmd_len = 0;
    //             break;
    //         case 0x01:
    //             luat_rtos_task_sleep(cmd & 0xFF);
    //             break;
    //         case 0x03:
    //             cmds[cmd_len] = (uint8_t)(cmd & 0xFF);
    //             cmd_len++;
    //             break;
    //         default:
    //             break;
    //     }
    //     if (i == disp->panel_ops->init_cmds_len - 1) {
    //         luat_display_write_cmd_data(disp, cmd_send, cmd_len ? cmds : NULL, cmd_len);
    //     }
    // }
}

int luat_display_write_cmd(luat_display_t *disp, uint8_t cmd) {
    // if (disp->if_ops && disp->if_ops->write_cmd) {
    //     return disp->if_ops->write_cmd(disp, cmd);
    // }
    // return luat_display_write_cmd_data(disp, cmd, NULL, 0);
    return -1;
}

int luat_display_write_data(luat_display_t *disp, const uint8_t *data, uint32_t len) {
    // if (disp->if_ops && disp->if_ops->write_data) {
    //     return disp->if_ops->write_data(disp, data, len);
    // }
    return -1;
}

int luat_display_write_cmd_data(luat_display_t *disp, uint8_t cmd,
                                 const uint8_t *data, uint32_t len) {
    // if (disp->if_ops && disp->if_ops->write_cmd_data) {
    //     return disp->if_ops->write_cmd_data(disp, cmd, data, len);
    // }
    return -1;
}

luat_display_t* luat_display_get_default(void) {
    // for (size_t i = 0; i < LUAT_DISPLAY_CONF_COUNT; i++) {
    //     if (display_confs[i] != NULL) {
    //         return display_confs[i];
    //     }
    // }
    return NULL;
}

int luat_display_register(luat_display_t *disp) {
    // for (size_t i = 0; i < LUAT_DISPLAY_CONF_COUNT; i++) {
    //     if (display_confs[i] == NULL) {
    //         display_confs[i] = disp;
    //         return i;
    //     }
    // }
    return -1;
}

const char* luat_display_name(luat_display_t *disp) {
    return 0;//disp->panel_ops ? disp->panel_ops->name : "unknown";
}

/*初始化引脚*/
int luat_display_init_pin_default(panel_pin_device_t *pin)
{
    /*配置用的SPI引脚*/
    if (pin->cs != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->cs, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
    if (pin->sdi != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->sdi, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
    if (pin->scl != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->scl, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
    if (pin->pwr != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->pwr, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
    if (pin->rst != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->bl, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
}

/*默认初始化函数*/
int luat_display_init_default(luat_display_t *disp) 
{
    /*初始化引脚*/
    luat_display_init_pin_default(disp->pin);

    /*可能还有极性问题，需要根据实际情况调整，待办事项*/

    /*液晶上电*/
    luat_gpio_set(disp->pin->pwr, Luat_GPIO_HIGH);

    /*复位液晶屏*/
    luat_gpio_set(disp->pin->rst, Luat_GPIO_LOW);
    luat_rtos_task_sleep(100);
    luat_gpio_set(disp->pin->rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(120);

    

    // luat_display_wakeup(disp);
    // luat_rtos_task_sleep(120);

    // if (disp->panel_ops->init) {
    //     disp->panel_ops->init(disp);
    // } else {
    //     luat_display_execute_cmds(disp);
    // }

    // luat_display_wakeup(disp);
    // luat_rtos_task_sleep(100);

// INIT_DONE:
//     disp->is_initialized = 1;
// INIT_NOT_DONE:
//     for (size_t i = 0; i < LUAT_DISPLAY_CONF_COUNT; i++) {
//         if (display_confs[i] == NULL) {
//             display_confs[i] = disp;
//             return 0;
//         }
//     }
    return -1;
}

/*默认初始化函数*/
LUAT_WEAK int luat_display_init(luat_display_t *disp) 
{
    return luat_display_init_default(disp);
}

int luat_display_close(luat_display_t *disp) 
{
    panel_pin_device_t *pin = disp->pin;
    
    if (pin->pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->pwr, Luat_GPIO_LOW);
    }
    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->bl, Luat_GPIO_LOW);
    }
    // if (disp->if_ops && disp->if_ops->deinit) {
    //     disp->if_ops->deinit(disp);
    // }
    // disp->power_state = LUAT_DISPLAY_POWER_OFF;
    return 0;
}

int luat_display_on(luat_display_t *disp) 
{
    panel_pin_device_t *pin = disp->pin;

    if (pin->pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->pwr, Luat_GPIO_HIGH);
    }
    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->bl, Luat_GPIO_HIGH);
    }

    return 0;
}

int luat_display_off(luat_display_t *disp) 
{
    // if (disp->pin_bl != LUAT_GPIO_NONE) {
    //     luat_gpio_set(disp->pin_bl, Luat_GPIO_LOW);
    // }
    // if (disp->pin_pwr != LUAT_GPIO_NONE) {
    //     luat_gpio_set(disp->pin_pwr, Luat_GPIO_LOW);
    // }
    return 0;
}

int luat_display_sleep(luat_display_t *disp) 
{
    // if (disp->pin_bl != LUAT_GPIO_NONE) {
    //     luat_gpio_set(disp->pin_bl, Luat_GPIO_LOW);
    // }
    // luat_rtos_task_sleep(5);
    // uint8_t sleep_cmd = disp->panel_ops->sleep_cmd ? disp->panel_ops->sleep_cmd : LUAT_DISPLAY_DEFAULT_SLEEP;
    // luat_display_write_cmd_data(disp, sleep_cmd, NULL, 0);
    // disp->power_state = LUAT_DISPLAY_POWER_SLEEP;
    return 0;
}

int luat_display_wakeup(luat_display_t *disp) 
{
    // uint8_t wakeup_cmd = disp->panel_ops->wakeup_cmd ? disp->panel_ops->wakeup_cmd : LUAT_DISPLAY_DEFAULT_WAKEUP;
    // luat_display_write_cmd_data(disp, wakeup_cmd, NULL, 0);
    return 0;
}

int luat_display_set_rotation(luat_display_t *disp, uint8_t rotation) 
{
    // if (disp->panel_ops->set_rotation) {
    //     return disp->panel_ops->set_rotation(disp, rotation);
    // }
    // uint8_t madctl = 0;
    // switch (rotation) {
    //     case LUAT_DISPLAY_ROTATE_0:   madctl = disp->panel_ops->madctl_0;   break;
    //     case LUAT_DISPLAY_ROTATE_90:  madctl = disp->panel_ops->madctl_90;  break;
    //     case LUAT_DISPLAY_ROTATE_180: madctl = disp->panel_ops->madctl_180; break;
    //     case LUAT_DISPLAY_ROTATE_270: madctl = disp->panel_ops->madctl_270; break;
    //     default: return -1;
    // }
    // luat_display_write_cmd_data(disp, 0x36, &madctl, 1);
    // disp->rotation = rotation;
    return 0;
}

int luat_display_flush_default(luat_display_t *disp) 
{
    // if (disp->fb_info.addr == NULL) {
    //     return 0;
    // }
    // if (disp->if_ops && disp->if_ops->fb_flush) {
    //     disp->if_ops->fb_flush(disp, 0, 0, disp->width - 1, disp->height - 1, NULL);
    // }
    return 0;
}

LUAT_WEAK int luat_display_flush(struct luat_display_t *disp) 
{
    return 0;
}

LUAT_WEAK int luat_display_fb_probe(struct luat_display_t *disp, luat_display_fb_info_t *info) 
{
    return 0;
}

LUAT_WEAK int luat_display_fb_allocate(luat_display_t *disp, uint32_t num_buffers)
{
    return 0;
}
