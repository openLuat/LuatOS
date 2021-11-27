
#ifndef Luat_PWM_H
#define Luat_PWM_H

#include "luat_base.h"

int luat_pwm_open(int channel, size_t period, size_t pulse,int pnum);
int luat_pwm_capture(int channel,int freq);
int luat_pwm_close(int channel);

#endif
