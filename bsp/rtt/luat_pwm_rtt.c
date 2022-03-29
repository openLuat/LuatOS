
#include "luat_base.h"
#include "luat_pwm.h"


#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#define LUAT_LOG_TAG "rtt.pwm"
#include "luat_log.h"

#ifdef RT_USING_PWM

//------------------------------------------------------
// 这里初始化一下 pwm 设备，一般的来说 pwm0 ... pwm6 就够了
// 某些时候，还有设备直接叫 "pwm"
#define DEVICE_ID_MAX 6
static struct rt_device_pwm *pwm_devs[DEVICE_ID_MAX];

static int luat_pwm_rtt_init() {
    char name[8];
    name[0] = 'p';
    name[1] = 'w';
    name[2] = 'm';
    name[4] = 0x00;
    
    // 搜索pwm0,pwm1,pwm2 ....
    for (size_t i = 0; i < DEVICE_ID_MAX; i++)
    {
        name[3] = '0' + i;
        pwm_devs[i] = (struct rt_device_pwm *)rt_device_find(name);
        if (pwm_devs[i])
            LLOGD("found pwm name=%s ptr=0x%08X", name, pwm_devs[i]);
    }
    // 看看有没有pwm
    if (pwm_devs[0] == RT_NULL) {
        pwm_devs[0] = (struct rt_device_pwm *)rt_device_find("pwm");
        if (pwm_devs[0])
            LLOGD("found pwm name=%s ptr=0x%08X", "pwm", pwm_devs[0]);
    }
	return 0;
}

INIT_COMPONENT_EXPORT(luat_pwm_rtt_init);

//#ifdef SOC_FAMILY_STM32
#if 0
//------------------------------------------------------
// 在 RTT， rt_device_pwm 实际上是 stm32_pwm 结构的第一个属性
// 因此，暗戳戳的转成 (stm32_pwm *) 即可得到 channel



#else
//------------------------------------------------------
// 在 RTT， 用两个数字来确定 pwm 的 channel
// {I}{N}
//  - I: 表示在 pwm_devs 中的下标
//  - N: 表示在该设备的 channel
// 这两个数字通过 @channel 参数得到
//  - I: 十位
//  - N: 个位
// @return -1 打开失败。 0 打开成功
int luat_pwm_open(int channel, size_t period, size_t pulse,int pnum) {
    int i = channel / 10;
    int n = channel - (i * 10);
    if (i < 0 || i >= DEVICE_ID_MAX )
        return -1;
    if (period < 1 || period > 1000000)
        return -1;
    if (pulse > 100)
        pulse = 100;

    struct rt_device_pwm *dev = pwm_devs[i];
    if(RT_NULL == dev)
        return -1;

    // 与Luat的定义不同, rtt的period和pulse是按时长作为单位的,单位是ns,即1/1000000000秒
    // rt_period = 1000000000 / luat_period
    // rt_pulse = (1000000000 / luat_period) * pulse / 100
    
    rt_pwm_set(dev, n, 1000000000 / period, (1000000000 / period) * pulse / 100);
    rt_pwm_enable(dev, n);

    return 0;
}

int luat_pwm_setup(luat_pwm_conf_t* conf) {
    int channel = conf->channel;
	size_t period = conf->period;
	size_t pulse = conf->pulse;
	size_t pnum = conf->pnum;
	size_t precision = conf->precision;

    int i = channel / 10;
    int n = channel - (i * 10);
    if (i < 0 || i >= DEVICE_ID_MAX )
        return -1;
    if (period < 1 || period > 1000000)
        return -1;
    if (pulse > precision)
        pulse = precision;

    struct rt_device_pwm *dev = pwm_devs[i];
    if(RT_NULL == dev)
        return -1;

    // 与Luat的定义不同, rtt的period和pulse是按时长作为单位的,单位是ns,即1/1000000000秒
    // rt_period = 1000000000 / luat_period
    // rt_pulse = (1000000000 / luat_period) * pulse / 100
    
    rt_pwm_set(dev, n, 1000000000 / period, (1000000000 / period) * pulse / precision);
    rt_pwm_enable(dev, n);

    return 0;
}

int luat_pwm_capture(int channel,int freq) {
    return -1;
}


// @return -1 关闭失败。 0 关闭成功
int luat_pwm_close(int channel) {
    int i = channel / 10;
    int n = channel - (i * 10);
    if (i < 0 || i >= DEVICE_ID_MAX )
        return -1;

    struct rt_device_pwm *dev = pwm_devs[i];
    if(RT_NULL == dev)
        return -1;
    
    rt_pwm_disable(dev, n);

    return 0;
}

#endif
//------------------------------------------------------
#endif
