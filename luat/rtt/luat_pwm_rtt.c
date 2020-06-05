
#include "luat_base.h"
#include "luat_pwm.h"

#include "luat_log.h"

#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#define DBG_TAG           "luat.pwm"
#define DBG_LVL           DBG_WARN
#include <rtdbg.h>

#ifdef RT_USING_PWM

#define DEVICE_ID_MAX 6
static struct pwm_devs *pwm_devs[DEVICE_ID_MAX];

static int luat_pwm_rtt_init() {
    char name[8];
    name[0] = 'p';
    name[1] = 'w';
    name[2] = 'm';
    name[4] = 0x00;
    
    // 搜索pwm0,pwm1,pwm2 ....
    for (size_t i = 0; i <= DEVICE_ID_MAX; i++)
    {
        name[3] = '0' + i;
        pwm_devs[i] = (struct rt_device_pwm *)rt_device_find(name);
        LOG_D("search pwm name=%s ptr=0x%08X", name, pwm_devs[i]);
    }
    // 看看有没有pwm
    if (pwm_devs[0] == RT_NULL) {
        pwm_devs[0] = (struct rt_device_pwm *)rt_device_find("pwm");
        LOG_D("search pwm name=%s ptr=0x%08X", "pwm", pwm_devs[0]);
    }
}

INIT_COMPONENT_EXPORT(luat_pwm_rtt_init);

int luat_pwm_open(int channel, size_t period, size_t pulse) {
    if (channel < 0 || channel >= DEVICE_ID_MAX )
        return -1;
    return -1;
}

int luat_pwm_close(int channel) {
    return -1;
}

#endif
