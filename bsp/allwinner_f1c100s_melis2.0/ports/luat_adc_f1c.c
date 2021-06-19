#include "luat_base.h"
#include "luat_adc.h"

int luat_adc_open(int pin, void* args) {
    return 0;
}

int luat_adc_read(int pin, int* val, int* val2) {
    return -1;
}

int luat_adc_close(int pin) {
    return 0;
}
