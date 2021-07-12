#include "port.h"
#include "stdint.h"
#include "lcd_cfg.h"
#define FB_CNT  2

void luatos_main_entry(void);

typedef struct
{
    ES_FILE* hdis;
	__hdle hlayer;
	uint32_t * layer_buf[FB_CNT];    //一个图层使用2个FrameBuffer
    uint32_t width;
    uint32_t height;
    uint32_t layer_buf_len;
    uint32_t layer_pix;
	uint8_t fb_index;
    uint8_t color_byte;
    uint8_t test_color;
}display_ctrlstruct;

typedef union
{
    __disp_color_t color;
    uint32_t data;
    /* data */
}color_union;


static display_ctrlstruct g_display;
//初始化显示
static void disp_lcd_init(void)
{	
	__disp_layer_info_t     layer_para;
    __u32 arg[3];
	g_display.hdis   = eLIBs_fopen("b:\\DISP\\DISPLAY", "r+");
    arg[0] = (uint32_t)lcd_common_rgb_gpio_list;
	arg[1] = (uint32_t)LCD_common_rbg_cfg_panel_info;
	arg[2] = (uint32_t)LCD_common_rbg_cfg_panel_info1;
	eLIBs_fioctrl(g_display.hdis, DISP_CMD_RESERVE0, 0, (void *)arg);    //加入这句才能开始用驱动，后续还要加入参数来动态选择LCD屏
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LCD_ON, 0, NULL);    //加入这句才能开始启动LCD
    g_display.width = eLIBs_fioctrl(g_display.hdis, DISP_CMD_SCN_GET_WIDTH, SEL_SCREEN,0); //modified by Derek,2010.12.07.15:05
	g_display.height = eLIBs_fioctrl(g_display.hdis, DISP_CMD_SCN_GET_HEIGHT, SEL_SCREEN,0); //modified by Derek,2010.12.07.15:05
    g_display.fb_index = 0;
    g_display.color_byte = 4;//ARGB8888
    g_display.layer_buf_len = g_display.width*g_display.height*g_display.color_byte;
    g_display.layer_pix = g_display.width*g_display.height;
    g_display.layer_buf[0] = esMEMS_Palloc(( g_display.layer_buf_len + 1023 ) / 1024, 0);
    g_display.layer_buf[1] = esMEMS_Palloc(( g_display.layer_buf_len + 1023 ) / 1024, 0);
    eLIBs_memset(g_display.layer_buf[0], 0, g_display.layer_buf_len);
    eLIBs_memset(g_display.layer_buf[1], 0, g_display.layer_buf_len);


	eLIBs_memset(&layer_para, 0, sizeof(__disp_layer_info_t));

    layer_para.fb.addr[0] = (__u32)g_display.layer_buf[0];
    layer_para.fb.size.width = g_display.width;
    layer_para.fb.size.height = g_display.height;
    layer_para.fb.mode = DISP_MOD_INTERLEAVED;
    layer_para.fb.format = DISP_FORMAT_ARGB8888;
    layer_para.fb.br_swap = 0;
    layer_para.fb.seq = DISP_SEQ_BGRA;
    layer_para.ck_enable = 0;
    layer_para.alpha_en = 0;
    layer_para.alpha_val = 0;
    layer_para.pipe = 0;
    layer_para.prio = 0;
    layer_para.src_win.x = 0;
    layer_para.src_win.y = 0;
    layer_para.src_win.width = g_display.width;
    layer_para.src_win.height = g_display.height;
    layer_para.scn_win.x = 0;
    layer_para.scn_win.y = 0;
    layer_para.scn_win.width = g_display.width;
    layer_para.scn_win.height = g_display.height;
    layer_para.mode = DISP_LAYER_WORK_MODE_NORMAL;

    
	arg[0] = DISP_LAYER_WORK_MODE_NORMAL;
	arg[1] = 0;
	arg[2] = 0;
	g_display.hlayer = eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_REQUEST, 0, (void *)arg);
    DBG("layer %x", g_display.hlayer);

	arg[0] = g_display.hlayer;
	arg[1] = (__u32)&layer_para;
	arg[2] = 0;
	eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_SET_PARA, 0, (void *)arg);

	arg[0] = g_display.hlayer;
	arg[1] = 0;
	arg[2] = 0;
	eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_TOP, 0, (void *)arg);

    arg[0] = g_display.hlayer;
    arg[1] = 0;
    arg[2] = 0;
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_OPEN, 0, (void*)arg);
}

static void disp_lcd_test(void)
{
    uint32_t i;
    uint32_t *buf;
    uint8_t next_buffer_index = (g_display.fb_index + 1) % FB_CNT;
    __disp_fb_t fb;  
	color_union u_color;
    __u32 arg[3];

    g_display.test_color = (g_display.test_color + 1) % 3;  //R,G,B轮转测试
    buf = g_display.layer_buf[next_buffer_index];
    i = 0;
    
	u_color.data = 0;
	u_color.color.alpha = 0xff;
	switch(g_display.test_color)
	{
	case 0:
		u_color.color.red = 255;
        DBG("test red");
		break;
	case 1:
		u_color.color.green = 255;
        DBG("test green");
		break;
	case 2:
		u_color.color.blue = 255;
        DBG("test blue");
		break;
	}
	for(i = 0; i < g_display.layer_buf_len / 4; i++)
	{
		buf[i] = u_color.data;
	}

    arg[0] = g_display.hlayer;
    arg[1] = (__u32)&fb;
    arg[2] = 0;
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_GET_FB, 0, arg);


    fb.addr[0] = (__u32)buf;
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_SET_FB, 0, arg);
    g_display.fb_index = next_buffer_index;
}

//---------------------
//#include "lvgl.h"
//---------------------

// static lv_disp_buf_t my_disp_buff = {0};

// 执行渲染或者触摸屏输入等操作
// 真正的移植会发消息到msgbug,然后在luatos主线程内执行渲染
// static void lvgl_task_thread(void *arg) {
//     lv_task_handler();
// }

// 每5ms为lvgl的时钟添加5
// static void lvgl_timer_thread(void *arg) {
//     while (1) {
        //    timer_sleep(5); // 5ms
        //    lv_timer_incr(5);   
//     }
// }
// // 绘制buff到显示区域
// static void disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p) {
//     //-----
//     LLOGD("CALL disp_flush (%d, %d, %d, %d)", area->x1, area->y1, area->x2, area->y2);
//     lv_disp_flush_ready(disp_drv);
// }

static void port_thread(void *arg)
{
    disp_lcd_init();
    disp_lcd_test();
    // lv_init();
    // lv_color_t *fbuffer = NULL;
    // fbuffer = luat_heap_malloc(fbuff_size * sizeof(lv_color_t));
    // lv_disp_buf_init(&my_disp_buff, fbuffer, NULL, fbuff_size);

    // lv_disp_drv_t my_disp_drv;
    // lv_disp_drv_init(&my_disp_drv);

    // my_disp_drv.flush_cb = disp_flush;

    // my_disp_drv.hor_res = 1280;
    // my_disp_drv.ver_res = 720;
    // my_disp_drv.buffer = &my_disp_buff;
    //LLOGD(">>%s %d", __func__, __LINE__);
    // lv_disp_drv_register(&my_disp_drv);
    //luatos_main_entry();
    while(1)
    {
        esKRNL_TimeDly(1000/SYS_TICK);
        disp_lcd_test();
    }
}

int port_entry(void)
{
    u8 id;
    esKSRV_CloseLogo();
    DBG("entry luatos app!");
    id = esKRNL_TCreate(port_thread, NULL, 0x10000, KRNL_priolevel1);
    DBG("thread id %d!", id);

    // esKRNL_TCreate(lvgl_task_thread, NULL, 0x10000, KRNL_priolevel1);
    // esKRNL_TCreate(lvgl_timer_thread, NULL, 0x10000, KRNL_priolevel1);
}

//==========================================
#include <rt_misc.h>
__value_in_regs struct __initial_stackheap __user_initial_stackheap(unsigned i0, unsigned i1, unsigned i2, unsigned i3)
{
   struct __initial_stackheap config;

   config.heap_base = i1;
   config.heap_limit = i1;
   config.stack_base = i1; 
   config.stack_limit = 0;

   return config;
}
//==========================================
