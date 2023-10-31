
#include "luat_base.h"
#include "luat_pwm.h"

LUAT_WEAK int luat_pwm_setup(luat_pwm_conf_t* conf) {
    return luat_pwm_open(conf->channel, conf->period, conf->pulse, conf->pnum);
}
