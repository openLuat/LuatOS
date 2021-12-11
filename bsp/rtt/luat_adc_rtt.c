
#include "luat_base.h"
#include "luat_adc.h"

#include "luat_log.h"

#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#define DBG_TAG           "luat.adc"
#define DBG_LVL           DBG_WARN
#include <rtdbg.h>

#ifdef RT_USING_ADC

int luat_adc_open(int pin, void* args) {
    return 0;
}

int luat_adc_read(int pin, int* val, int* val2) {
    return 0;
}

int luat_adc_close(int pin) {
    return 0;
}
//------------------------------------------------------
#endif
