
#ifndef EPD_EPD
#define EPD_EPD

#include "stdio.h"
#include "DEV_Config.h"

void EPD_Model(UBYTE model);
int EPD_Init(UBYTE Mode, size_t *w, size_t *h, size_t* color_count);
void EPD_Clear(void);
void EPD_Display(UBYTE *Image, UBYTE *Image2);
void EPD_Sleep(void);
void EPD_Task(void *param);

enum EPD_MODEL {
        MODEL_1in02d = 1,
        MODEL_1in54,
        MODEL_1in54b,
        MODEL_1in54b_V2,
        MODEL_1in54c,
        // MODEL_1in54f,
        MODEL_1in54_V2,
        MODEL_1in54_V3,
        MODEL_1in54r,//红色三色屏
        MODEL_2in13,
        MODEL_2in13bc,
        MODEL_2in13b_V3,
        MODEL_2in13d,
        MODEL_2in13_V2,
        MODEL_2in66,
        MODEL_2in66b,
        MODEL_2in7,
        MODEL_2in7b,
        MODEL_2in9,
        MODEL_2in9bc,
        MODEL_2in9b_V3,
        MODEL_2in9d,
        // MODEL_2in9ff,
        MODEL_2in9_V2,
        MODEL_3in7,
        MODEL_4in2,
        MODEL_4in2bc,
        MODEL_4in2b_V2,
        MODEL_5in65f,
        MODEL_5in83,
        MODEL_5in83bc,
        MODEL_5in83b_V2,
        MODEL_5in83_V2,
        MODEL_7in5,
        MODEL_7in5bc,
        MODEL_7in5b_HD,
        MODEL_7in5b_V2,
        MODEL_7in5_HD,
        MODEL_7in5_V2,
        MODEL_MAX
};


#include "EPD_1in02d.h"
#include "EPD_1in54.h"
#include "EPD_1in54b.h"
#include "EPD_1in54b_V2.h"
#include "EPD_1in54c.h"
#include "EPD_1in54f.h"
#include "EPD_1in54_V2.h"
#include "EPD_1in54_V3.h"
#include "EPD_1in54r.h"
#include "EPD_2in13.h"
#include "EPD_2in13bc.h"
#include "EPD_2in13b_V3.h"
#include "EPD_2in13d.h"
#include "EPD_2in13_V2.h"
#include "EPD_2in66.h"
#include "EPD_2in66b.h"
#include "EPD_2in7.h"
#include "EPD_2in7b.h"
#include "EPD_2in9.h"
#include "EPD_2in9bc.h"
#include "EPD_2in9b_V3.h"
#include "EPD_2in9d.h"
#include "EPD_2in9ff.h"
#include "EPD_2in9_V2.h"
#include "EPD_3in7.h"
#include "EPD_4in2.h"
#include "EPD_4in2bc.h"
#include "EPD_4in2b_V2.h"
#include "EPD_5in65f.h"
#include "EPD_5in83.h"
#include "EPD_5in83bc.h"
#include "EPD_5in83b_V2.h"
#include "EPD_5in83_V2.h"
#include "EPD_7in5.h"
#include "EPD_7in5bc.h"
#include "EPD_7in5b_HD.h"
#include "EPD_7in5b_V2.h"
#include "EPD_7in5_HD.h"
#include "EPD_7in5_V2.h"

#endif
