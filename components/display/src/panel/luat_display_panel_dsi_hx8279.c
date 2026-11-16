#include "luat_base.h"
#include "luat_display_panel_comm.h"

#ifdef LUAT_USE_MIPI_INF
#include "luat_rtos.h"
#include "luat_gpio.h"


#define LUAT_LOG_TAG "hx8279"
#include "luat_log.h"


#define panel_dsi_send_seq(panel, ...) do {                         \
        static const unsigned char d[] = { __VA_ARGS__ };           \
        int ret;                                                    \
        ret = dsi_panel_send_sequence(panel, d, DISPLAY_ARRAY_SIZE(d));     \
        if (ret < 0)                                                \
            return ret;                                             \
    } while (0)

/*初始化面板
  两份已验证可点亮的实现（T113 hx8279_dsi.c、artinchip panel_dsi_hx8279.c）
  完全一致：没有任何厂内初始化表，只需退出睡眠 -> 开显示，
  两条 DCS 之间分别等待 200ms / 120ms。这里也严格只发这两条，
  不再补 COLMOD/MADCTL，避免引入与参考实现不同的变量。
  电源脚（本板 PC11，LuatOS 编号 75，高有效）必须先拉高：
  display.init 末尾的 power_on 晚于 panel_init，等它上电就来不及发命令。*/
static int panel_init(struct luat_display_panel *panel) 
{
    struct panel_pin_device *pin = panel->pin;

    if (pin != NULL && pin->pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->pwr, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(100);
    }

    /*默认复位时序：拉低 20ms，拉高后等 120ms*/
    luat_display_panel_reset(panel);

    panel_dsi_send_seq(panel, 0x11);   /*Sleep Out*/
    luat_rtos_task_sleep(200);

    panel_dsi_send_seq(panel, 0x29);   /*Display On*/
    luat_rtos_task_sleep(120);

    return 0;
}

/*关闭面板*/
static int panel_deinit(struct luat_display_panel *panel) 
{
    return 0;
}

/*控制面板
  display.off() 会把 pin_pwr 拉低给整屏掉电，控制器状态随之复位；
  此时 display.on() 只走通用的 SLPIN/SLPOUT 会漏掉 DISPON，屏幕保持黑屏。
  所以 POWER_ON 在 SLPOUT 之后补一次 DISPON。*/
static int panel_ctrl(struct luat_display_panel *panel, enum display_ctrl_cmd cmd, void *arg)
{
    int ret;

    if (cmd == LUAT_DISPLAY_POWER_ON) {
        ret = luat_display_panel_ctrl(panel, cmd, arg);   /*SLPOUT + 等 120ms*/
        if (ret < 0)
            return ret;

        panel_dsi_send_seq(panel, 0x29);
        luat_rtos_task_sleep(120);
        return 0;
    }

    return luat_display_panel_ctrl(panel, cmd, arg);
}

/*DSI面板操作接口*/
static struct luat_display_panel_funcs panel_funcs_dsi = {
    .panel_init     = panel_init,
    .panel_deinit   = panel_deinit,
    .panel_ctrl     = panel_ctrl,
};

/*DSI面板时序参数：直接取两份已验证可点亮的实现的消隐值。
  T113 lcd_cfg.c（lcd_ht=1555 / lcd_hbp=185 / lcd_hspw=15，Allwinner 的 hbp 含 hspw）
  与 artinchip panel_dsi_hx8279.c（hfp=170 / hbp=170 / hsync=15 / vfp=40 / vbp=40 /
  vsync=15）完全等价：
  TH = 1555 = 1200 + HSPW 15 + HBP 170 + HFP 170
  TV = 2015 = 1920 + VSPW 15 + VBP 40  + VFP 40
  屏规格书给的是最小消隐（TH 1341 / TV 1981），参考实现都留了更大余量，跟参考走。

  像素时钟受 MPLL 限制：pclk 必须等于 1.8GHz / lcd_mpll_div。
  T113 参考用的是 non-burst 视频模式 + 170MHz 像素时钟，折算 DSI 链路
  = pclk * 24 / lanes = 1020 Mbps（不乘 burst 余量），正好压在屏规格 955~1000 附近。
  这里对齐它：div=11 -> pclk 163.6MHz -> non-burst 链路 982 Mbps，
  刷新率 163.6e6 / (1555*2015) ≈ 52Hz（T113 是 54.3Hz）。
  burst 模式在 X2600 上要乘 1.5 余量，div=16 会算到 1015Mbps 且没法再降，
  这是改用 non-burst 的原因。*/
static struct luat_display_timing hx8279_timing = {
    .pclk_hz = 163636363,

    .hactive = 1200,
    .hfp = 170,
    .hbp = 170,
    .hspw = 15,

    .vactive = 1920,
    .vfp = 40,
    .vbp = 40,
    .vspw = 15,
};

/*DSI接口参数：与 T113 参考一致，4 lane / RGB888 / non-burst 视频模式*/
struct panel_dsi hx8279_dsi = 
{
    .mode = DSI_MOD_VID_PULSE,
    .format = DSI_FMT_RGB888,
    .lane_num = 4,
    .vc_num = 0,
};

/*对DSI面板的描述*/
struct luat_display_panel dsi_panel_hx8279 = {
    .name = "hx8279",
    .desc = "dsi",
    .connector_type = LUAT_DISPLAY_CONNECTOR_MIPI,
    .dsi = &hx8279_dsi,
    .panel_funcs = &panel_funcs_dsi,
    .timing = &hx8279_timing,
    .screen_win = NULL,
};

#endif /* LUAT_USE_MIPI_INF */
