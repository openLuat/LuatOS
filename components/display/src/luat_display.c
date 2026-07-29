#include "luat_base.h"
#include "luat_display.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "display"
#include "luat_log.h"

/*显示组件*/
static struct luat_display *display_component[LUAT_DISPLAY_COMPONENT_COUNT] = { NULL };


/*获取默认显示组件*/
struct luat_display* luat_display_get_default(void) 
{
    for (size_t i = 0; i < LUAT_DISPLAY_COMPONENT_COUNT; i++) 
    {
        if (display_component[i] != NULL) 
        {
            return display_component[i];
        }
    }
    return NULL;
}

/*注册显示组件*/
int luat_display_register(struct luat_display *disp) 
{
    for (size_t i = 0; i < LUAT_DISPLAY_COMPONENT_COUNT; i++) 
    {
        if (display_component[i] == NULL) 
        {
            display_component[i] = disp;
            return i;
        }
    }
    return -1;
}

/*获取显示组件名称*/
const char* luat_display_name(struct luat_display *disp) 
{
    return disp->name;
}



/*初始化引脚*/
int luat_display_init_pin(struct panel_pin_device *pin)
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
    if (pin->dc != LUAT_GPIO_NONE) {
        luat_gpio_mode(pin->dc, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
    }
    return 0;
}

/*设置一个默认的显示层*/
int luat_display_layer_setup(struct luat_display *disp) 
{
    int ret = 0;

    struct luat_display_fb_info *fb_info = disp->fb_info;
    struct luat_display_panel *panel = disp->panel;
    struct luat_display_layer_data ui_layer = {0};

    ui_layer.enable = 1;
    ui_layer.layer_id = 0;
    ui_layer.area_id = 0;

    /*设置默认层的区域*/
    ui_layer.area.x1 = panel->screen_win->x;
    ui_layer.area.y1 = panel->screen_win->y;
    ui_layer.area.x2 = panel->screen_win->x + panel->screen_win->w;
    ui_layer.area.y2 = panel->screen_win->y + panel->screen_win->h;

    ui_layer.buffer = fb_info->fb_start;
    ui_layer.format = fb_info->format;

    ret = disp->display_funcs->set_layer(&ui_layer);
    if (ret != 0) {
        LLOGE("set_layer failed, ret = %d", ret);
        return ret;
    }

    return 0;
}

/*初始化显示*/
int luat_display_init(struct luat_display *disp) 
{
    int ret = 0;

    /*初始化引脚*/
    ret = luat_display_init_pin(disp->panel->pin);
    if (ret) {
        LLOGE("init_pin failed, ret = %d", ret);
        return ret;
    }

    /*创建FB信息*/
    disp->fb_info = luat_heap_zalloc(sizeof(struct luat_display_fb_info));
    disp->fb_info->inited = 0;
    
    /*初始化面板*/
    disp->panel->panel_funcs->panel_init(disp->panel);

    /*根据面板信息探测FB信息*/
    ret = disp->display_funcs->fb_probe(disp->panel, disp->fb_info);

    if (ret) {
        LLOGE("fb_probe failed, ret = %d", ret);
        return ret;
    }

    /*初始化接口，在这里设置timing参数*/
    ret = disp->display_funcs->inf_init(disp->panel);
    if (ret) {
        LLOGE("inf_init failed, ret = %d", ret);
        return ret;
    }

    /*设置默认层*/
    ret = luat_display_layer_setup(disp);

    if (ret) {
        LLOGE("layer_setup failed, ret = %d", ret);
        return ret;
    }

    return 0;
}


/*打开显示*/
int luat_display_on(struct luat_display *disp)
{
    if (disp == NULL || disp->panel == NULL) {
        return -1;
    }

    luat_display_power_on(disp);

    if (disp->panel->panel_funcs != NULL &&
        disp->panel->panel_funcs->panel_ctrl != NULL) {
        disp->panel->panel_funcs->panel_ctrl(disp->panel, LUAT_DISPLAY_POWER_ON, NULL);
    }

    return 0;
}

/*关闭显示*/
int luat_display_off(struct luat_display *disp)
{
    if (disp == NULL || disp->panel == NULL) {
        return -1;
    }

    luat_display_power_off(disp);

    if (disp->panel->panel_funcs != NULL &&
        disp->panel->panel_funcs->panel_ctrl != NULL) {
        disp->panel->panel_funcs->panel_ctrl(disp->panel, LUAT_DISPLAY_POWER_OFF, NULL);
    }

    return 0;
}

/*关闭显示*/
int luat_display_close(struct luat_display_panel *panel) 
{
    // struct panel_pin_device *pin = panel->pin;
    
    // if (pin->pwr != LUAT_GPIO_NONE) {
    //     luat_gpio_set(pin->pwr, Luat_GPIO_LOW);
    // }
    // if (pin->bl != LUAT_GPIO_NONE) {
    //     luat_gpio_set(pin->bl, Luat_GPIO_LOW);
    // }
    // // if (disp->if_ops && disp->if_ops->deinit) {
    // //     disp->if_ops->deinit(disp);
    // // }
    // // disp->power_state = LUAT_DISPLAY_POWER_OFF;
    return 0;
}



int luat_display_sleep(struct luat_display *disp) 
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

int luat_display_wakeup(struct luat_display *disp) 
{
    // uint8_t wakeup_cmd = disp->panel_ops->wakeup_cmd ? disp->panel_ops->wakeup_cmd : LUAT_DISPLAY_DEFAULT_WAKEUP;
    // luat_display_write_cmd_data(disp, wakeup_cmd, NULL, 0);
    return 0;
}

int luat_display_set_rotation(struct luat_display *disp, uint8_t rotation) 
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

int luat_display_flush_default(struct luat_display *disp) 
{
    // if (disp->fb_info.addr == NULL) {
    //     return 0;
    // }
    // if (disp->if_ops && disp->if_ops->fb_flush) {
    //     disp->if_ops->fb_flush(disp, 0, 0, disp->width - 1, disp->height - 1, NULL);
    // }
    return 0;
}

LUAT_WEAK int luat_display_flush(struct luat_display *disp) 
{
    return 0;
}

LUAT_WEAK int luat_display_fb_probe(struct luat_display *disp, struct luat_display_fb_info *info) 
{
    return 0;
}

LUAT_WEAK int luat_display_fb_allocate(struct luat_display *disp, uint32_t num_buffers)
{
    return 0;
}
