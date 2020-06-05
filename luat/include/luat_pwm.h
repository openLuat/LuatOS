
#ifndef Luat_PWM
#define Luat_PWM

#include "luat_base.h"

int luat_pwm_open(int channel, size_t period, size_t pulse);
int luat_pwm_close(int channel);

#endif
