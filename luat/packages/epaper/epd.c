

#include "epd.h"

static int cur_model = MODEL_1in54f;

void EPD_Model(UBYTE model) {
    cur_model = model;
}

int EPD_Init(UBYTE mode, size_t *w, size_t *h) {
    switch (cur_model)
    {
    case MODEL_1in02d:
        EPD_1IN02_Init();
        *w = EPD_1IN02_WIDTH;
        *h = EPD_1IN02_HEIGHT;
        break;
    case MODEL_1in54:
        *w = EPD_1IN54_WIDTH;
        *h = EPD_1IN54_HEIGHT;
        EPD_1IN54_Init(mode);
        break;
    case MODEL_1in54_V2:
        *w = EPD_1IN54_V2_WIDTH;
        *h = EPD_1IN54_V2_HEIGHT;
        EPD_1IN54_V2_Init();
        break;
    case MODEL_1in54b_V2:
        *w = EPD_1IN54B_V2_WIDTH;
        *h = EPD_1IN54B_V2_HEIGHT;
        EPD_1IN54B_V2_Init();
        break;
    case MODEL_1in54b:
        *w = EPD_1IN54B_WIDTH;
        *h = EPD_1IN54B_HEIGHT;
        EPD_1IN54B_Init();
        break;
    case MODEL_1in54c:
        *w = EPD_1IN54C_WIDTH;
        *h = EPD_1IN54C_HEIGHT;
        EPD_1IN54C_Init();
        break;
    case MODEL_1in54f:
        *w = EPD_1IN54F_WIDTH;
        *h = EPD_1IN54F_HEIGHT;
        EPD_1IN54FF_Init();
        break;
    case MODEL_2in13b_V3:
        *w = EPD_2IN13B_V3_WIDTH;
        *h = EPD_2IN13B_V3_HEIGHT;
        EPD_2IN13B_V3_Init();
        break;
    case MODEL_2in7:
        *w = EPD_2IN7_WIDTH;
        *h = EPD_2IN7_HEIGHT;
        EPD_2IN7_Init();
        break;
    case MODEL_2in7b:
        *w = EPD_2IN7B_WIDTH;
        *h = EPD_2IN7B_HEIGHT;
        EPD_2IN7B_Init();
        break;
    case MODEL_2in9:
        *w = EPD_2IN9_WIDTH;
        *h = EPD_2IN9_HEIGHT;
        EPD_2IN9_Init(mode);
        break;
    case MODEL_2in9b_V3:
        *w = EPD_2IN9B_V3_WIDTH;
        *h = EPD_2IN9B_V3_HEIGHT;
        EPD_2IN9B_V3_Init();
        break;
    case MODEL_2in9bc:
        *w = EPD_2IN9BC_WIDTH;
        *h = EPD_2IN9BC_HEIGHT;
        EPD_2IN9BC_Init();
        break;
    case MODEL_2in9d:
        *w = EPD_2IN9D_WIDTH;
        *h = EPD_2IN9D_HEIGHT;
        EPD_2IN9D_Init();
        break;
    case MODEL_2in9f:
        *w = EPD_2IN9F_WIDTH;
        *h = EPD_2IN9F_HEIGHT;
        EPD_2IN9D_Init();
        break;
    case MODEL_3in7:
        *w = EPD_3IN7_WIDTH;
        *h = EPD_3IN7_HEIGHT;
        EPD_3IN7_1Gray_Init();
        break;
    default:
        return -1;
    }
    return 0;
}
void EPD_Clear(void) {
    switch (cur_model)
    {
    case MODEL_1in02d:
        EPD_1IN02_Clear();
        break;
    case MODEL_1in54:
        EPD_1IN54_Clear();
        break;
    case MODEL_1in54_V2:
        EPD_1IN54_V2_Clear();
        break;
    case MODEL_1in54b_V2:
        EPD_1IN54B_V2_Clear();
        break;
    case MODEL_1in54b:
        EPD_1IN54B_Clear();
        break;
    case MODEL_1in54c:
        EPD_1IN54C_Clear();
        break;
    case MODEL_1in54f:
        EPD_1IN54FF_Clear();
        break;
    case MODEL_2in13b_V3:
        EPD_2IN13B_V3_Clear();
        break;
    case MODEL_2in7:
        EPD_2IN7_Clear();
        break;
    case MODEL_2in7b:
        EPD_2IN7B_Clear();
        break;
    case MODEL_2in9:
        EPD_2IN9_Clear();
        break;
    case MODEL_2in9b_V3:
        EPD_2IN9B_V3_Clear();
        break;
    case MODEL_2in9bc:
        EPD_2IN9BC_Clear();
        break;
    case MODEL_2in9d:
        EPD_2IN9D_Clear();
        break;
    case MODEL_2in9f:
        EPD_2IN9FF_Clear();
        break;
    case MODEL_3in7:
        EPD_3IN7_1Gray_Clear();
        break;

    default:
        break;
    }
}
void EPD_Display(UBYTE *Image, UBYTE *Image2) {
    switch (cur_model)
    {
    case MODEL_1in02d:
        EPD_1IN02_Display(Image);
        break;
    case MODEL_1in54:
        EPD_1IN54_Display(Image);
        break;
    case MODEL_1in54_V2:
        EPD_1IN54_V2_Display(Image);
        break;
    case MODEL_1in54b_V2:
        EPD_1IN54B_V2_Display(Image, Image2);
        break;
    case MODEL_1in54b:
        EPD_1IN54B_Display(Image, Image2);
        break;
    case MODEL_1in54c:
        EPD_1IN54C_Display(Image, Image2);
        break;
    case MODEL_1in54f:
        EPD_1IN54FF_Display(Image);
        break;
    case MODEL_2in13b_V3:
        EPD_2IN13B_V3_Display(Image, Image2);
        break;
    case MODEL_2in7:
        EPD_2IN7_Display(Image);
        break;
    case MODEL_2in7b:
        EPD_2IN7B_Display(Image, Image2);
        break;
    case MODEL_2in9:
        EPD_2IN9_Display(Image);
        break;
    case MODEL_2in9b_V3:
        EPD_2IN9B_V3_Display(Image, Image2);
        break;
    case MODEL_2in9bc:
        EPD_2IN9BC_Display(Image, Image2);
        break;
    case MODEL_2in9d:
        EPD_2IN9D_Display(Image);
        break;
    case MODEL_2in9f:
        EPD_2IN9FF_Display(Image);
        break;
    case MODEL_3in7:
        EPD_3IN7_1Gray_Display(Image);
        break;

    default:
        break;
    }
}
void EPD_Sleep(void) {
    switch (cur_model)
    {
    case MODEL_1in02d:
        EPD_1IN02_Sleep();
        break;
    case MODEL_1in54:
        EPD_1IN54_Sleep();
        break;
    case MODEL_1in54_V2:
        EPD_1IN54_V2_Sleep();
        break;
    case MODEL_1in54b_V2:
        EPD_1IN54B_V2_Sleep();
        break;
    case MODEL_1in54b:
        EPD_1IN54B_Sleep();
        break;
    case MODEL_1in54c:
        EPD_1IN54C_Sleep();
        break;
    case MODEL_1in54f:
        EPD_1IN54FF_Sleep();
        break;
    case MODEL_2in13b_V3:
        EPD_2IN13B_V3_Sleep();
        break;
    case MODEL_2in7:
        EPD_2IN7_Sleep();
        break;
    case MODEL_2in7b:
        EPD_2IN7B_Sleep();
        break;
    case MODEL_2in9:
        EPD_2IN9_Sleep();
        break;
    case MODEL_2in9b_V3:
        EPD_2IN9B_V3_Sleep();
        break;
    case MODEL_2in9bc:
        EPD_2IN9BC_Sleep();
        break;
    case MODEL_2in9d:
        EPD_2IN9D_Sleep();
        break;
    case MODEL_2in9f:
        EPD_2IN9FF_Sleep();
        break;
    case MODEL_3in7:
        EPD_3IN7_Sleep();
        break;

    default:
        break;
    }
}
