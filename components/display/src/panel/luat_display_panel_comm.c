#include "luat_base.h"
#include "luat_display_panel_comm.h"
#include "luat_rtos.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "panel_comm"
#include "luat_log.h"

/*支持的显示面板列表*/
static struct luat_display_panel *panels[] = {
    &rgb_panel_custom,
    &rgb_panel_st7701s,
    &rgb_panel_nv3052c,
    &dsi_panel_st7701s,
    &spi_panel_st7789,
    &spi_panel_ili9341,
};

/*按照连接器类型查找显示面板*/
struct luat_display_panel *luat_display_find_panel(unsigned int connector_type)
{
    size_t i;

    for (i = 0; i < ARRAY_SIZE(panels); i++) {
        if (panels[i]->connector_type == connector_type) {
            break;
        }
    }

    if (i >= ARRAY_SIZE(panels))
        return NULL;

    LLOGI("find panel driver : %s\n", panels[i]->name);
    
    return panels[i];
}



/*默认复位显示面板*/
int luat_display_panel_reset(struct luat_display_panel *panel) 
{
    struct panel_pin_device *pin = panel->pin;

    if (pin->rst != LUAT_GPIO_NONE) 
    {
        luat_gpio_set(pin->rst, Luat_GPIO_LOW);
        luat_rtos_task_sleep(20);
        luat_gpio_set(pin->rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(120);
    }

    return 0;
}

/*默认显示面板上电*/
int luat_display_power_on(struct luat_display *disp) 
{
    if (disp == NULL || disp->panel == NULL || disp->panel->pin == NULL) {
        return 0;
    }
    struct panel_pin_device *pin = disp->panel->pin;

    if (pin->pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->pwr, Luat_GPIO_HIGH);
    }
    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->bl, Luat_GPIO_HIGH);
    }
    return 0;
}

/*默认显示面板下电*/
int luat_display_power_off(struct luat_display *disp) 
{
    if (disp == NULL || disp->panel == NULL || disp->panel->pin == NULL) {
        return 0;
    }
    struct panel_pin_device *pin = disp->panel->pin;

    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->bl, Luat_GPIO_LOW);
    }
    if (pin->pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->pwr, Luat_GPIO_LOW);
    }
    return 0;
}


