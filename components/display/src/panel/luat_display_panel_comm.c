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
    &spi_panel_st7796,
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

/*通用函数，内部按照连接器类型发送一条命令序列，data 首字节为命令*/
int luat_display_send_sequence(struct luat_display_panel *panel, const void *data, uint32_t len)
{
    if (panel == NULL || data == NULL || len == 0) {
        return -1;
    }

    switch (panel->connector_type) {
    case LUAT_DISPLAY_CONNECTOR_RGB:
        return rgb_spi_panel_send_sequence(panel, data, len);
    case LUAT_DISPLAY_CONNECTOR_DBI:
        return spilcd_panel_send_sequence(panel, data, len);
    case LUAT_DISPLAY_CONNECTOR_MIPI:
        return dsi_panel_send_sequence(panel, data, len);
    default:
        return 0;
    }
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

/*发送面板自定义命令序列（Lua 传入的 custom_cmds）*/
int luat_display_panel_send_custom_cmds(struct luat_display_panel *panel)
{
    int ret = 0;
    uint32_t i;

    if (panel == NULL || panel->custom_cmds == NULL || panel->custom_cmd_count == 0) {
        return 0;
    }

    for (i = 0; i < panel->custom_cmd_count; i++) {
        const struct luat_display_seq_cmd *cmd = &panel->custom_cmds[i];

        ret = luat_display_send_sequence(panel, cmd->data, cmd->len);
        if (ret < 0) {
            LLOGE("send custom cmd[%u] failed, ret=%d", i, ret);
            return ret;
        }

        if (cmd->delay_ms > 0) {
            luat_rtos_task_sleep(cmd->delay_ms);
        }
    }

    return 0;
}

/*各面板 panel_ctrl 的通用实现：
  - LUAT_DISPLAY_SEND_SEQ：下发一条命令序列（arg 指向 struct luat_display_init_cmd）
  - LUAT_DISPLAY_POWER_SLEEP：下发 SLPIN(0x10) 让屏控制器进入低功耗
  - LUAT_DISPLAY_POWER_ON：下发 SLPOUT(0x11) 唤醒屏控制器*/
int luat_display_panel_ctrl(struct luat_display_panel *panel, enum display_ctrl_cmd cmd, void *arg)
{
    if (panel == NULL) {
        return -1;
    }

    if (cmd == LUAT_DISPLAY_SEND_SEQ && arg != NULL) {
        struct luat_display_seq_cmd *c = (struct luat_display_seq_cmd *)arg;
        return luat_display_send_sequence(panel, c->data, c->len);
        
    } else if (cmd == LUAT_DISPLAY_POWER_SLEEP || cmd == LUAT_DISPLAY_POWER_ON) {
        /*仅对具备命令通道的控制器下发 SLPIN/SLPOUT；
          RGB/LVDS 这一类走背光/电源控制，不在这里发命令*/
        if (panel->connector_type == LUAT_DISPLAY_CONNECTOR_DBI ||
            panel->connector_type == LUAT_DISPLAY_CONNECTOR_MIPI ||
            panel->connector_type == LUAT_DISPLAY_CONNECTOR_RGB) {
            static const unsigned char slpin[]  = {0x10};  /* Sleep In  */
            static const unsigned char slpout[] = {0x11};  /* Sleep Out */
            const unsigned char *c = (cmd == LUAT_DISPLAY_POWER_ON) ? slpout : slpin;

            luat_display_send_sequence(panel, c, 1);
            /*SLPOUT 需要一段时间才能恢复显示，SLPIN 后亦需保持*/
            luat_rtos_task_sleep(cmd == LUAT_DISPLAY_POWER_ON ? 120 : 5);
        }
    }
    return 0;
}


