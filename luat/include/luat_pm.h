
#ifndef LUAT_PM_H
#define LUAT_PM_H
#include "luat_base.h"

#define LUAT_PM_SLEEP_MODE_NONE     0	//系统处于活跃状态，未采取任何的降低功耗状态
#define LUAT_PM_SLEEP_MODE_IDLE     1	//空闲模式，该模式在系统空闲时停止 CPU 和部分时钟，任意事件或中断均可以唤醒
#define LUAT_PM_SLEEP_MODE_LIGHT    2	//轻度睡眠模式，CPU 停止，多数时钟和外设停止，唤醒后需要进行时间补偿
#define LUAT_PM_SLEEP_MODE_DEEP     3	//深度睡眠模式，CPU 停止，仅少数低功耗外设工作，可被特殊中断唤醒
#define LUAT_PM_SLEEP_MODE_STANDBY	4	//待机模式，CPU 停止，设备上下文丢失(可保存至特殊外设)，唤醒后通常复位
//#define LUAT_PM_SLEEP_MODE_SHUTDOWN	5	//关断模式，比 Standby 模式功耗更低， 上下文通常不可恢复， 唤醒后复位

int luat_pm_request(int mode);

int luat_pm_release(int mode);

int luat_pm_dtimer_start(int id, size_t timeout);

int luat_pm_dtimer_stop(int id);

int luat_pm_dtimer_check(int id);

// void luat_pm_cb(int event, int arg, void* args);

int luat_pm_last_state(int *lastState, int *rtcOrPad);

int luat_pm_force(int mode);

int luat_pm_check(void);

int luat_pm_dtimer_list(size_t* count, size_t* list);

int luat_pm_dtimer_wakeup_id(int* id);

#endif
