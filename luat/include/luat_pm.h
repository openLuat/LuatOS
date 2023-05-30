
#ifndef LUAT_PM_H
#define LUAT_PM_H
#include "luat_base.h"

#define LUAT_PM_SLEEP_MODE_NONE     0	//系统处于活跃状态，未采取任何的降低功耗状态
#define LUAT_PM_SLEEP_MODE_IDLE     1	//空闲模式，该模式在系统空闲时停止 CPU 和部分时钟，任意事件或中断均可以唤醒
#define LUAT_PM_SLEEP_MODE_LIGHT    2	//轻度睡眠模式，CPU 停止，多数时钟和外设停止
#define LUAT_PM_SLEEP_MODE_DEEP     3	//深度睡眠模式，CPU 停止，仅少数低功耗外设工作，可被特殊中断唤醒
#define LUAT_PM_SLEEP_MODE_STANDBY	4	//待机模式，CPU 停止，设备上下文丢失(可保存至特殊外设)，唤醒后通常复位
//#define LUAT_PM_SLEEP_MODE_SHUTDOWN	5	//关断模式，比 Standby 模式功耗更低， 上下文通常不可恢复， 唤醒后复位
#define LUAT_PM_POWER_MODE_NORMAL (0)	///< 去除所有降低功耗的措施
#define LUAT_PM_POWER_MODE_HIGH_PERFORMANCE (1)	///< 尽可能保持性能，兼顾低功耗，使用LUAT_PM_SLEEP_MODE_LIGHT
#define LUAT_PM_POWER_MODE_BALANCED (2) ///< 性能和功耗平衡，使用LUAT_PM_SLEEP_MODE_LIGHT
#define LUAT_PM_POWER_MODE_POWER_SAVER (3) ///< 超低功耗，使用LUAT_PM_SLEEP_MODE_STANDBY，进入PSM模式

// 开关类
enum
{
	LUAT_PM_POWER_USB,
	LUAT_PM_POWER_GPS,
	LUAT_PM_POWER_GPS_ANT,
	LUAT_PM_POWER_CAMERA,
	LUAT_PM_POWER_DAC_EN_PIN,
	LUAT_PM_POWER_POWERKEY_MODE,
	LUAT_PM_POWER_WORK_MODE
};

// 电平类
enum
{
	LUAT_PM_ALL_GPIO,
};

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

int luat_pm_poweroff(void);

int luat_pm_power_ctrl(int id, uint8_t val);

int luat_pm_get_poweron_reason(void);

int luat_pm_iovolt_ctrl(int id, int val);

int luat_pm_wakeup_pin(int pin, int val);
/**
 * @brief 设置联网低功耗模式，等同于AT+POWERMODE
 * @param 低功耗主模式 见LUAT_PM_POWER_MODE_XXX
 * @param 预留，低功耗次级模式，当主模式设置成LUAT_PM_POWER_MODE_BALANCED，可以微调功耗模式，当前不可用
 * @return int =0成功，其他失败
 * @note 和luat_pm_set_sleep_mode，luat_pm_set_usb_power冲突，不可以同时使用
 */
int luat_pm_set_power_mode(uint8_t mode, uint8_t sub_mode);
#endif
