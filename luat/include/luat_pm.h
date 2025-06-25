
#ifndef LUAT_PM_H
#define LUAT_PM_H
#include "luat_base.h"
/**
 * @defgroup luatos_device_pm 电源管理类（低功耗）
 * @{
*/
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


/**
 * @brief 开机原因
 */
typedef enum LUAT_PM_POWERON_REASON
{
	LUAT_PM_POWERON_REASON_NORMAL = 0,			/**<powerkey或者上电开机*/
	LUAT_PM_POWERON_REASON_FOTA,				/**<充电或者AT指令下载完成后开机*/
	LUAT_PM_POWERON_REASON_ALARM,				/**<闹钟开机*/
	LUAT_PM_POWERON_REASON_SWRESET,				/**<软件重启*/
	LUAT_PM_POWERON_REASON_UNKNOWN,				/**<未知原因*/
	LUAT_PM_POWERON_REASON_HWRESET,				/**<RESET键重启*/
	LUAT_PM_POWERON_REASON_EXCEPTION,			/**<异常重启*/
	LUAT_PM_POWERON_REASON_TOOL,				/**<工具控制重启*/
	LUAT_PM_POWERON_REASON_WDT,					/**<内部看门狗重启*/
	LUAT_PM_POWERON_REASON_EXTERNAL,			/**<外部重启*/
	LUAT_PM_POWERON_REASON_CHARGING,			/**<充电开机*/
} LUAT_PM_POWERON_REASON_E;

// 开关类
enum
{
	LUAT_PM_POWER_USB,
	LUAT_PM_POWER_GPS,
	LUAT_PM_POWER_GPS_ANT,
	LUAT_PM_POWER_CAMERA,
	LUAT_PM_POWER_DAC_EN_PIN,
	LUAT_PM_POWER_POWERKEY_MODE,
	LUAT_PM_POWER_WORK_MODE,
	LUAT_PM_POWER_LDO_CTL_PIN,
};

// 电平类
enum
{
	LUAT_PM_ALL_GPIO,
	LUAT_PM_LDO_TYPE_VMMC,
	LUAT_PM_LDO_TYPE_VLCD,
	LUAT_PM_LDO_TYPE_CAMA,
	LUAT_PM_LDO_TYPE_CAMD,
	LUAT_PM_LDO_TYPE_VLP33,//8910没有
	LUAT_PM_LDO_TYPE_VLP18,//8910没有
	LUAT_PM_LDO_TYPE_VIO18,
	LUAT_PM_LDO_TYPE_VIBR,	//8850没有
	LUAT_PM_LDO_TYPE_KEYLED,
	LUAT_PM_LDO_TYPE_VSIM1,	//不一定起作用，尽量不要用
	LUAT_PM_LDO_TYPE_QTY,
};

/**
 * @brief 请求进入指定的休眠模式
 * @param mode 休眠模式 见LUAT_PM_SLEEP_MODE_XXX
 * @return int =0成功，其他失败
 */
int luat_pm_request(int mode);
/**
 * @brief 退出休眠模式
 * @param mode 休眠模式 见LUAT_PM_SLEEP_MODE_XXX
 * @return int =0成功，其他失败
 */
int luat_pm_release(int mode);

/**
 * @brief 启动底层定时器,在休眠模式下依然生效. 只触发一次
 * @param id 定时器id, 通常为0-3
 * @param timeout 定时时长, 单位毫秒
 * @return int =0成功，其他失败
 */
int luat_pm_dtimer_start(int id, size_t timeout);

/**
 * @brief 停止底层定时器
 * @param id 定时器id, 通常为0-3
 * @return int =0成功，其他失败
 */
int luat_pm_dtimer_stop(int id);

/**
 * @brief 检查底层定时器运行状态
 * @param id 定时器id, 通常为0-3
 * @return int =1正在运行，0为未运行
 */
int luat_pm_dtimer_check(int id);

// void luat_pm_cb(int event, int arg, void* args);

/**
 * @brief 唤醒原因,用于判断是从开机是否是由休眠状态下开机/唤醒
 * @param lastState 0-普通开机(上电/复位),3-深睡眠开机,4-休眠开机
 * @param rtcOrPad 0-上电/复位开机, 1-RTC开机, 2-WakeupIn/Pad/IO开机, 3-Wakeup/RTC开机
 * @return int =0成功，其他失败
 */
int luat_pm_last_state(int *lastState, int *rtcOrPad);

/**
 * @brief 强制进入指定的休眠模式，忽略某些外设的影响，比如USB
 * @param mode 休眠模式 见LUAT_PM_SLEEP_MODE_XXX
 * @return int =0成功，其他失败
 */
int luat_pm_force(int mode);

/**
 * @brief 检查休眠状态
 * @return int ，见LUAT_PM_SLEEP_MODE_XXX
 */
int luat_pm_check(void);
/**
 * @brief 获取所有深度休眠定时器的剩余时间，单位ms
 * @param count [OUT]定时器数量
 * @param list [OUT]剩余时间列表
 * @return int =0成功，其他失败
 */
int luat_pm_dtimer_list(size_t* count, size_t* list);

/**
 * @brief 获取唤醒定时器id
 * @param id  唤醒的定时id
 * @return int =0成功，其他失败
 */
int luat_pm_dtimer_wakeup_id(int* id);

/**
 * @brief 关机
 * 
 */
int luat_pm_poweroff(void);

/**
 * @brief 重启
 * 
 */
int luat_pm_reset(void);

/**
 * @brief 开启内部的电源控制，注意不是所有的平台都支持，可能部分平台支持部分选项，看硬件
 * @param id  电源控制id, 见LUAT_PM_POWER_XXX 
 * @param val  开关true/1开，false/0关，默认关，部分选项支持数值
 * @return int =0成功，其他失败
 */
int luat_pm_power_ctrl(int id, uint8_t val);

/**
 * @brief 开机原因
 * @return int ，见LUAT_PM_POWERON_REASON
 */
int luat_pm_get_poweron_reason(void);

/**
 * @brief 设置IO电压域的电平
 * @param id 电压域ID，移芯平台忽略
 * @param val 期望的电平值，单位mv
 * @return int 成功返回0，其他失败
 */
int luat_pm_iovolt_ctrl(int id, int val);

/**
 * @brief 配置唤醒引脚，只针对esp系列
 * @param pin 引脚
 * @param val 电平
 * @return
 */
int luat_pm_wakeup_pin(int pin, int val);
/**
 * @brief 设置联网低功耗模式，等同于AT+POWERMODE
 * @param 低功耗主模式 见LUAT_PM_POWER_MODE_XXX
 * @param 预留，低功耗次级模式，当主模式设置成LUAT_PM_POWER_MODE_BALANCED，可以微调功耗模式，当前不可用
 * @return int =0成功，其他失败
 * @note 和luat_pm_set_sleep_mode，luat_pm_set_usb_power冲突，不可以同时使用
 */
int luat_pm_set_power_mode(uint8_t mode, uint8_t sub_mode);
/**
 * @brief 深度休眠定时器剩余时间，单位ms
 * @param id 定时器ID
 * @return uint32_t 0xffffffff失败，其他是剩余时间
 */
uint32_t luat_pm_dtimer_remain(int id);
/** @}*/
#endif
