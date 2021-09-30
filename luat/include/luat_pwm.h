
#ifndef Luat_PWM
#define Luat_PWM

#include "luat_base.h"

int luat_pwm_open(int channel, size_t period, size_t pulse,int pnum);
int luat_pwm_capture(int channel,int freq);
int luat_pwm_close(int channel);

#endif
