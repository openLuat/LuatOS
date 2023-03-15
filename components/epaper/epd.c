

#include "epd.h"

static int cur_model_index = 1;

typedef void (*eink_init)(UBYTE mode);
typedef void (*eink_clear)(void);
typedef void (*eink_sleep)(void);
typedef void (*eink_display)(UBYTE *Image, UBYTE *Image2);

typedef struct eink_reg
{
    uint16_t tp;
    uint16_t colors;
    uint16_t w;
    uint16_t h;
    eink_init init;
    eink_clear clear;
    eink_sleep sleep;
    eink_display display;
}eink_reg_t;


static const eink_reg_t eink_regs[] = {
        {.tp=MODEL_1in02d,      .colors=1, .init=EPD_1IN02_Init, .w = EPD_1IN02_WIDTH, .h = EPD_1IN02_HEIGHT, .clear = EPD_1IN02_Clear, .sleep =EPD_1IN02_Sleep, .display=EPD_1IN02_Display},
        {.tp=MODEL_1in54,       .colors=1, .init=EPD_1IN54_Init, .w = EPD_1IN54_WIDTH, .h = EPD_1IN54_HEIGHT, .clear = EPD_1IN54_Clear, .sleep =EPD_1IN54_Sleep, .display=EPD_1IN54_Display},
        {.tp=MODEL_1in54b,      .colors=1, .init=EPD_1IN54B_Init, .w = EPD_1IN54B_WIDTH, .h = EPD_1IN54B_HEIGHT, .clear = EPD_1IN54B_Clear, .sleep =EPD_1IN54B_Sleep, .display=EPD_1IN54B_Display},
        {.tp=MODEL_1in54b_V2,   .colors=1, .init=EPD_1IN54B_V2_Init, .w = EPD_1IN54B_V2_WIDTH, .h = EPD_1IN54B_V2_HEIGHT, .clear = EPD_1IN54B_V2_Clear, .sleep =EPD_1IN54B_V2_Sleep, .display=EPD_1IN54B_V2_Display},
        {.tp=MODEL_1in54c,      .colors=1, .init=EPD_1IN54C_Init, .w = EPD_1IN54C_WIDTH, .h = EPD_1IN54C_HEIGHT, .clear = EPD_1IN54C_Clear, .sleep =EPD_1IN54C_Sleep, .display=EPD_1IN54C_Display},
        // {.tp=MODEL_1in54f,      .colors=1, .init=EPD_1IN54FF_Init, .w = EPD_1IN54F_WIDTH, .h = EPD_1IN54F_HEIGHT, .clear = EPD_1IN54FF_Clear, .sleep =EPD_1IN54FF_Sleep, .display=EPD_1IN54FF_Display},
        {.tp=MODEL_1in54_V2,    .colors=1, .init=EPD_1IN54_V2_Init, .w = EPD_1IN54_V2_WIDTH, .h = EPD_1IN54_V2_HEIGHT, .clear = EPD_1IN54_V2_Clear, .sleep =EPD_1IN54_V2_Sleep, .display=EPD_1IN54_V2_Display},       
        {.tp=MODEL_1in54_V3,    .colors=1, .init=EPD_1IN54_V3_Init, .w = EPD_1IN54_V3_WIDTH, .h = EPD_1IN54_V3_HEIGHT, .clear = EPD_1IN54_V3_Clear, .sleep =EPD_1IN54_V3_Sleep, .display=EPD_1IN54_V3_Display},       
        {.tp=MODEL_1in54r,      .colors=2, .init=EPD_1IN54R_Init, .w = EPD_1IN54R_WIDTH, .h = EPD_1IN54R_HEIGHT, .clear = EPD_1IN54R_Clear, .sleep =EPD_1IN54R_Sleep, .display=EPD_1IN54R_Display},       
        {.tp=MODEL_2in13,       .colors=1, .init=EPD_2IN13_Init, .w = EPD_2IN13_WIDTH, .h = EPD_2IN13_HEIGHT, .clear = EPD_2IN13_Clear, .sleep =EPD_2IN13_Sleep, .display=EPD_2IN13_Display},
        {.tp=MODEL_2in13bc,     .colors=1, .init=EPD_2IN13BC_Init, .w = EPD_2IN13BC_WIDTH, .h = EPD_2IN13BC_HEIGHT, .clear = EPD_2IN13BC_Clear, .sleep =EPD_2IN13BC_Sleep, .display=EPD_2IN13BC_Display},
        {.tp=MODEL_2in13b_V3,   .colors=1, .init=EPD_2IN13B_V3_Init, .w = EPD_2IN13B_V3_WIDTH, .h = EPD_2IN13B_V3_HEIGHT, .clear = EPD_2IN13B_V3_Clear, .sleep =EPD_2IN13B_V3_Sleep, .display=EPD_2IN13B_V3_Display},  
        {.tp=MODEL_2in13d,      .colors=1, .init=EPD_2IN13D_Init, .w = EPD_2IN13D_WIDTH, .h = EPD_2IN13D_HEIGHT, .clear = EPD_2IN13D_Clear, .sleep =EPD_2IN13D_Sleep, .display=EPD_2IN13D_Display},
        {.tp=MODEL_2in13_V2,    .colors=1, .init=EPD_2IN13_V2_Init, .w = EPD_2IN13_V2_WIDTH, .h = EPD_2IN13_V2_HEIGHT, .clear = EPD_2IN13_V2_Clear, .sleep =EPD_2IN13_V2_Sleep, .display=EPD_2IN13_V2_Display},
        {.tp=MODEL_2in66,       .colors=1, .init=EPD_2IN66_Init, .w = EPD_2IN66_WIDTH, .h = EPD_2IN66_HEIGHT, .clear = EPD_2IN66_Clear, .sleep =EPD_2IN66_Sleep, .display=EPD_2IN66_Display},
        {.tp=MODEL_2in66b,      .colors=1, .init=EPD_2IN66B_Init, .w = EPD_2IN66B_WIDTH, .h = EPD_2IN66B_HEIGHT, .clear = EPD_2IN66B_Clear, .sleep =EPD_2IN66B_Sleep, .display=EPD_2IN66B_Display},
        {.tp=MODEL_2in7,        .colors=1, .init=EPD_2IN7_Init, .w = EPD_2IN7_WIDTH, .h = EPD_2IN7_HEIGHT, .clear = EPD_2IN7_Clear, .sleep =EPD_2IN7_Sleep, .display=EPD_2IN7_Display},
        {.tp=MODEL_2in7b,       .colors=1, .init=EPD_2IN7B_Init, .w = EPD_2IN7B_WIDTH, .h = EPD_2IN7B_HEIGHT, .clear = EPD_2IN7B_Clear, .sleep =EPD_2IN7B_Sleep, .display=EPD_2IN7B_Display},
        {.tp=MODEL_2in9,        .colors=1, .init=EPD_2IN9_Init, .w = EPD_2IN9_WIDTH, .h = EPD_2IN9_HEIGHT, .clear = EPD_2IN9_Clear, .sleep =EPD_2IN9_Sleep, .display=EPD_2IN9_Display},
        {.tp=MODEL_2in9bc,      .colors=1, .init=EPD_2IN9BC_Init, .w = EPD_2IN9BC_WIDTH, .h = EPD_2IN9BC_HEIGHT, .clear = EPD_2IN9BC_Clear, .sleep =EPD_2IN9BC_Sleep, .display=EPD_2IN9BC_Display},
        {.tp=MODEL_2in9b_V3,    .colors=1, .init=EPD_2IN9B_V3_Init, .w = EPD_2IN9B_V3_WIDTH, .h = EPD_2IN9B_V3_HEIGHT, .clear = EPD_2IN9B_V3_Clear, .sleep =EPD_2IN9B_V3_Sleep, .display=EPD_2IN9B_V3_Display},
        {.tp=MODEL_2in9d,       .colors=1, .init=EPD_2IN9D_Init, .w = EPD_2IN9D_WIDTH, .h = EPD_2IN9D_HEIGHT, .clear = EPD_2IN9D_Clear, .sleep =EPD_2IN9D_Sleep, .display=EPD_2IN9D_Display},
        // {.tp=MODEL_2in9ff,      .colors=1, .init=EPD_2IN9FF_Init, .w = EPD_2IN9FF_WIDTH, .h = EPD_2IN9FF_HEIGHT, .clear = EPD_2IN9FF_Clear, .sleep =EPD_2IN9FF_Sleep, .display=EPD_2IN9FF_Display},
        {.tp=MODEL_2in9_V2,     .colors=1, .init=EPD_2IN9_V2_Init, .w = EPD_2IN9_V2_WIDTH, .h = EPD_2IN9_V2_HEIGHT, .clear = EPD_2IN9_V2_Clear, .sleep =EPD_2IN9_V2_Sleep, .display=EPD_2IN9_V2_Display},
        {.tp=MODEL_3in7,        .colors=1, .init=EPD_3IN7_1Gray_Init, .w = EPD_3IN7_WIDTH, .h = EPD_3IN7_HEIGHT, .clear = EPD_3IN7_1Gray_Clear, .sleep =EPD_3IN7_Sleep, .display=EPD_3IN7_1Gray_Display},
        {.tp=MODEL_4in2,        .colors=1, .init=EPD_4IN2_Init, .w = EPD_4IN2_WIDTH, .h = EPD_4IN2_HEIGHT, .clear = EPD_4IN2_Clear, .sleep =EPD_4IN2_Sleep, .display=EPD_4IN2_Display},
        {.tp=MODEL_4in2bc,      .colors=2, .init=EPD_4IN2BC_Init, .w = EPD_4IN2BC_WIDTH, .h = EPD_4IN2BC_HEIGHT, .clear = EPD_4IN2BC_Clear, .sleep =EPD_4IN2BC_Sleep, .display=EPD_4IN2BC_Display},
        {.tp=MODEL_4in2b_V2,    .colors=1, .init=EPD_4IN2B_V2_Init, .w = EPD_4IN2B_V2_WIDTH, .h = EPD_4IN2B_V2_HEIGHT, .clear = EPD_4IN2B_V2_Clear, .sleep =EPD_4IN2B_V2_Sleep, .display=EPD_4IN2B_V2_Display},
        {.tp=MODEL_5in65f,      .colors=1, .init=EPD_5IN65F_Init, .w = EPD_5IN65F_WIDTH, .h = EPD_5IN65F_HEIGHT, .clear = EPD_5IN65F_Clear, .sleep =EPD_5IN65F_Sleep, .display=EPD_5IN65F_Display},
        {.tp=MODEL_5in83,       .colors=1, .init=EPD_5IN83_Init, .w = EPD_5IN83_WIDTH, .h = EPD_5IN83_HEIGHT, .clear = EPD_5IN83_Clear, .sleep =EPD_5IN83_Sleep, .display=EPD_5IN83_Display},
        {.tp=MODEL_5in83bc,     .colors=1, .init=EPD_5IN83BC_Init, .w = EPD_5IN83BC_WIDTH, .h = EPD_5IN83BC_HEIGHT, .clear = EPD_5IN83BC_Clear, .sleep =EPD_5IN83BC_Sleep, .display=EPD_5IN83BC_Display},
        {.tp=MODEL_5in83b_V2,   .colors=1, .init=EPD_5IN83B_V2_Init, .w = EPD_5IN83B_V2_WIDTH, .h = EPD_5IN83B_V2_HEIGHT, .clear = EPD_5IN83B_V2_Clear, .sleep =EPD_5IN83B_V2_Sleep, .display=EPD_5IN83B_V2_Display},  
        //{.tp=MODEL_5in83_V2,  .colors=1, .init=EPD_5IN83_V2_Init, .w = EPD_5IN83_V2_WIDTH, .h = EPD_5IN83_V2_HEIGHT, .clear = EPD_5IN83_V2_Clear, .sleep =EPD_5IN83_V2_Sleep, .display=EPD_5IN83_V2_Display},
        {.tp=MODEL_7in5,        .colors=1, .init=EPD_7IN5_Init, .w = EPD_7IN5_WIDTH, .h = EPD_7IN5_HEIGHT, .clear = EPD_7IN5_Clear, .sleep =EPD_7IN5_Sleep, .display=EPD_7IN5_Display},
        {.tp=MODEL_7in5bc,      .colors=1, .init=EPD_7IN5BC_Init, .w = EPD_7IN5BC_WIDTH, .h = EPD_7IN5BC_HEIGHT, .clear = EPD_7IN5BC_Clear, .sleep =EPD_7IN5BC_Sleep, .display=EPD_7IN5BC_Display},
        {.tp=MODEL_7in5b_HD,    .colors=2, .init=EPD_7IN5B_HD_Init, .w = EPD_7IN5B_HD_WIDTH, .h = EPD_7IN5B_HD_HEIGHT, .clear = EPD_7IN5B_HD_Clear, .sleep =EPD_7IN5B_HD_Sleep, .display=EPD_7IN5B_HD_Display},
        {.tp=MODEL_7in5b_V2,    .colors=2, .init=EPD_7IN5B_V2_Init, .w = EPD_7IN5B_V2_WIDTH, .h = EPD_7IN5B_V2_HEIGHT, .clear = EPD_7IN5B_V2_Clear, .sleep =EPD_7IN5B_V2_Sleep, .display=EPD_7IN5B_V2_Display},
        {.tp=MODEL_7in5_HD,     .colors=2, .init=EPD_7IN5_HD_Init, .w = EPD_7IN5_HD_WIDTH, .h = EPD_7IN5_HD_HEIGHT, .clear = EPD_7IN5_HD_Clear, .sleep =EPD_7IN5_HD_Sleep, .display=EPD_7IN5_HD_Display},
        //{.tp=MODEL_7in5_V2, .colors=1, .init=EPD_7IN5_V2_Init, .w = EPD_7IN5_V2_WIDTH, .h = EPD_7IN5_V2_HEIGHT, .clear = EPD_7IN5_V2_Clear, .sleep =EPD_7IN5_V2_Sleep, .display=EPD_7IN5_V2_Display},
        {.tp = 0xFF}
};

void EPD_Model(UBYTE model) {
    if (model >= MODEL_MAX)
        return;
    const eink_reg_t* reg = eink_regs;
    int index = 0;
    while (reg->tp != 0xFF) {
        if (reg->tp == model) {
            cur_model_index = index;
            break;
        }
        reg ++;
        index ++;
    }
}

int EPD_Init(UBYTE mode, size_t *w, size_t *h, size_t* colors) {
    eink_regs[cur_model_index].init(mode);
    *w = eink_regs[cur_model_index].w;
    *h = eink_regs[cur_model_index].h;
    *colors = eink_regs[cur_model_index].colors;
    return 0;
}
void EPD_Clear(void) {
    eink_regs[cur_model_index].clear();
}
void EPD_Display(UBYTE *Image, UBYTE *Image2) {
    if (Image2 == NULL)
        Image2 = Image;
    eink_regs[cur_model_index].display(Image, Image2);
}
void EPD_Sleep(void) {
    eink_regs[cur_model_index].sleep();
}

void EPD_Task(void *param){
    uint8_t event;
    while (1) {
        luat_rtos_queue_recv(econf.eink_queue_handle, &event, sizeof(uint8_t), LUAT_WAIT_FOREVER);
        if (event){
            if (event & EPD_CLEAR){
                EPD_Clear();
            }
            if (event & EPD_SHOW){
                if(event & EPD_CLEAR)
                    EPD_Clear();
                if (econf.ctxs[1] == NULL)
                    EPD_Display(econf.ctxs[0]->fb, NULL);
                else
                    EPD_Display(econf.ctxs[0]->fb, econf.ctxs[1]->fb);
            }
            if (event & EPD_DRAW){//初始化时候已经创建缓冲区，zbuff好像意义不大了?

            }
            luat_cbcwait_noarg(econf.idp);
        }
	}
}

