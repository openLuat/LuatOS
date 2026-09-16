#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_if_comm.h"
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

/*按 ID 获取显示组件*/
struct luat_display* luat_display_get_by_id(uint8_t id) 
{
    if (id >= LUAT_DISPLAY_COMPONENT_COUNT) {
        return NULL;
    }
    return display_component[id];
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

/*按指定 ID 注册显示组件*/
int luat_display_register_with_id(struct luat_display *disp, uint8_t id) 
{
    if (id >= LUAT_DISPLAY_COMPONENT_COUNT) {
        return -1;
    }
    if (display_component[id] != NULL) {
        return -1;
    }
    display_component[id] = disp;
    return id;
}

/*注销显示组件*/
void luat_display_unregister(struct luat_display *disp) 
{
    if (disp == NULL) {
        return;
    }
    for (size_t i = 0; i < LUAT_DISPLAY_COMPONENT_COUNT; i++) 
    {
        if (display_component[i] == disp) 
        {
            display_component[i] = NULL;
            return;
        }
    }
}

/*销毁显示组件，释放其占用的所有资源*/
int luat_display_destroy(struct luat_display *disp) 
{
    if (disp == NULL) {
        return 0;
    }

    /*先从管理数组中移除，防止后续操作访问到半销毁状态*/
    luat_display_unregister(disp);

    /*调用接口层的反初始化*/
    if (disp->display_funcs != NULL && disp->display_funcs->deinit != NULL) {
        disp->display_funcs->deinit(disp);
    }

    /*释放显示缓冲区信息*/
    if (disp->fb_info != NULL) {
        luat_heap_free(disp->fb_info);
        disp->fb_info = NULL;
    }

    /*释放引脚配置*/
    if (disp->panel != NULL && disp->panel->pin != NULL) {
        luat_heap_free(disp->panel->pin);
        disp->panel->pin = NULL;
    }

    /*注意：panel 结构体通常是全局静态模板，screen_win 可能跨 display 共享，
      因此不在此处释放。binding 层若自行分配了 screen_win，应在 init 失败
      路径中单独处理。*/

    luat_heap_free(disp);
    return 0;
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
        luat_gpio_mode(pin->cs, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);   // CS引脚默认高电平
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
    ui_layer.layer_id = 0;  //UI层ID
    ui_layer.area_id = 0;
    ui_layer.alpha = 0xFF;

    /*设置默认层的区域*/
    ui_layer.area.x1 = panel->screen_win->x;
    ui_layer.area.y1 = panel->screen_win->y;
    ui_layer.area.x2 = panel->screen_win->x + panel->screen_win->w;
    ui_layer.area.y2 = panel->screen_win->y + panel->screen_win->h;

    /*默认显示层应指向 LCDC 显存（fb_start）；SDL/软件渲染无 fb_start 时才回退到 draw_buf*/
    ui_layer.buffer = fb_info->fb_start ? fb_info->fb_start : fb_info->draw_buf.buffer;
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

    /*初始化面板*/
    ret = disp->panel->panel_funcs->panel_init(disp->panel);
    if (ret) {
        LLOGW("panel_init failed, ret = %d", ret);
    }
    
    /*根据面板信息探测FB信息*/
    ret = disp->display_funcs->fb_probe(disp->panel, disp->fb_info);

    if (ret) {
        LLOGE("fb_probe failed, ret = %d", ret);
        return ret;
    }

    /*初始化接口，在这里设置timing参数*/
    ret = disp->display_funcs->inf_init(disp);
    if (ret) {
        LLOGE("inf_init failed, ret = %d", ret);
        return ret;
    }

    /*这里设置图层，让图层指向fb_start*/
    ret = luat_display_layer_setup(disp);

    if (ret) {
        LLOGE("layer_setup failed, ret = %d", ret);
        return ret;
    }

    return 0;
}

/*刷新显示缓冲区，全屏刷新*/
int luat_display_flush(struct luat_display *disp) 
{
    if (disp == NULL || disp->display_funcs == NULL || disp->display_funcs->fb_flush == NULL || disp->fb_info == NULL) {
        return 0;
    }

    struct luat_display_fb_info *info = disp->fb_info;
    const void *data = info->draw_buf.buffer ? info->draw_buf.buffer : info->fb_start;

    if (data == NULL) {
        return 0;
    }

    struct luat_display_rect rect = {
        .x = 0,
        .y = 0,
        .w = info->draw_buf.width,
        .h = info->draw_buf.height,
    };

    info->fb_index = (info->fb_index + 1) % info->fb_count;

    return disp->display_funcs->fb_flush(disp, &rect, data, disp->rotation);
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

/*设置旋转方向
 * fb_info 保留物理尺寸（LCDC/显存布局权威，不随旋转改变）；
 * draw_buf 跟随旋转，保存当前旋转状态的逻辑布局（宽高互换、stride 重算）——
 * 注意：这只是逻辑元数据，draw_buf 的像素数据仍按物理布局紧排（LVGL 按物理
 * 分辨率渲染，旋转由驱动层 flush 时完成），访问像素数据必须用 info->stride。*/
int luat_display_set_rotation(struct luat_display *disp, enum disp_rotate rotation) 
{
    if (disp == NULL || disp->fb_info == NULL) {
        return -1;
    }

    if(rotation == disp->rotation) {
        return 0;
    }

    if(rotation == LUAT_DISPLAY_ROTATE_90 || rotation == LUAT_DISPLAY_ROTATE_270) {
        /*旋转 90/270：draw_buf 宽高互换，stride 按旋转后行宽重算*/
        int w = disp->fb_info->width;
        int h = disp->fb_info->height;

        disp->fb_info->draw_buf.width = h;
        disp->fb_info->draw_buf.height = w;
        disp->fb_info->draw_buf.stride = h * disp->fb_info->bits_per_pixel / 8;
    }else{
        /*旋转 0/180：draw_buf 恢复物理布局*/
        int w = disp->fb_info->width;
        int h = disp->fb_info->height;

        disp->fb_info->draw_buf.width = w;
        disp->fb_info->draw_buf.height = h;
        disp->fb_info->draw_buf.stride = w * disp->fb_info->bits_per_pixel / 8;
    }

    disp->rotation = rotation;

    return 0;
}

/*关闭显示*/
int luat_display_close(struct luat_display_panel *panel) 
{

    return 0;
}



/*显示休眠：
 * 1) 关闭背光，避免睡眠瞬间亮屏残留
 * 2) 下发 SLPIN(0x10) 让屏控制器进入低功耗
 * 注意：只关背光/下命令，不断开电源(那属于 power_off)*/
int luat_display_sleep(struct luat_display *disp) 
{
    if (disp == NULL || disp->panel == NULL || disp->panel->pin == NULL) {
        return -1;
    }
    struct panel_pin_device *pin = disp->panel->pin;

    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->bl, Luat_GPIO_LOW);
    }

    if (disp->panel->panel_funcs != NULL &&
        disp->panel->panel_funcs->panel_ctrl != NULL) {
        disp->panel->panel_funcs->panel_ctrl(disp->panel, LUAT_DISPLAY_POWER_SLEEP, NULL);
    }

    return 0;
}

/*显示唤醒：
 * 1) 下发 SLPOUT(0x11) 唤醒屏控制器
 * 2) 恢复背光*/
int luat_display_wakeup(struct luat_display *disp) 
{
    if (disp == NULL || disp->panel == NULL || disp->panel->pin == NULL) {
        return -1;
    }
    struct panel_pin_device *pin = disp->panel->pin;

    if (disp->panel->panel_funcs != NULL &&
        disp->panel->panel_funcs->panel_ctrl != NULL) {
        disp->panel->panel_funcs->panel_ctrl(disp->panel, LUAT_DISPLAY_POWER_ON, NULL);
    }

    if (pin->bl != LUAT_GPIO_NONE) {
        luat_gpio_set(pin->bl, Luat_GPIO_HIGH);
    }

    return 0;
}




