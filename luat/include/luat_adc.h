
#ifndef Luat_ADC
#define Luat_ADC

#include "luat_base.h"

int luat_adc_open(int pin, void* args);
int luat_adc_read(int pin, int* val, int* val2);
int luat_adc_close(int pin);

#endif
