
#ifndef Luat_PWM_H
#define Luat_PWM_H

#include "luat_base.h"

/**
 * @defgroup luatos_device_PWM PWM接口
 * @{
*/
/**
 * @brief PWM控制参数
*/
typedef struct luat_pwm_conf {
    int channel; /**<PWM通道 可选通道为 0 / 1 / 2 / 4 总计4个通道*/
    int stop_level;
    size_t period;/**<频率, 1Hz - 13MHz*/
    size_t pulse; /**<占空比，0-100  如将pulse设为50时输出高电平时间占周期50%时间 */
    size_t pnum; /**<输出周期 0为持续输出, 1为单次输出, 其他为指定脉冲数输出*/
    size_t precision;/**<分频精度, 100/256/1000, 默认为100, 若设备不支持会有日志提示*/
    uint8_t reverse;
} luat_pwm_conf_t;

#ifdef __LUATOS__
#else
/**
 * @brief 设置PWM输出完成回调，只有open时，pnum不为0才有回调，必须在pwm open前设置
 * @param channel: 选择pwm通道 可选通道为 0 / 1 / 2 / 4 总计4个通道
 *        callback  ：回调函数
 *        param ：回调时用户参数
 * @return int
 */
int luat_pwm_set_callback(int channel, CBFuncEx_t callback, void *param);
#endif
/**
 * @brief 打开pwm 通道
 *
 * @param channel: 选择PWM通道 可选通道为 0 / 1 / 2 / 4 总计4个通道
 *        period : 设置产生的PWM频率
 *        pulse  : 设置产生的PWM占空比，单位0.1%
 *        pnum   ：设置产生的PWM个数，若pnum设为0将一直输出PWM
 * @return int
 *         返回值为 0 : 配置PWM成功
 *         返回值为 -1: PWM通道选择错误
 *         返回值为 -2: PWM频率设置错误
 *         返回值为 -3：PWM占空比设置错误
 *         返回值为 -4: 该PWM通道已被使用
 */
int luat_pwm_open(int channel, size_t period, size_t pulse, int pnum);
/**
 * @brief 配置pwm 参数
 *
 * @param conf->channel: 选择PWM通道 可选通道为 0 / 1 / 2 / 4 总计4个通道
 *        conf->period : 设置产生的PWM频率
 *        conf->pulse  : 设置产生的PWM占空比
 *        conf->pnum   : 设置产生的PWM个数，若pnum设为0将一直输出PWM
 * @return int
 *         返回值为 0 : 配置PWM成功
 *         返回值为 -1: PWM通道选择错误
 *         返回值为 -2: PWM频率设置错误
 *         返回值为 -3：PWM占空比设置错误
 *         返回值为 -4: 该PWM通道已被使用
 */
int luat_pwm_setup(luat_pwm_conf_t* conf);
/**
 * @brief 获取pwm 频率  本功能暂未实现
 *
 * @param id i2c_id
 * @return int
 */
int luat_pwm_capture(int channel,int freq);
/**
 * @brief 关闭pwm 接口
 *
 * @param channel: 选择PWM通道 可选通道为 0 / 1 / 2 / 4 总计4个通道
 * @return int
 */
int luat_pwm_close(int channel);
/**
 * @brief 修改占空比
 * @param channel: 选择pwm通道 可选通道为 0 / 1 / 2 / 4 总计4个通道
 *        pulse  ：修改pwm占空比值
 * @return int
 */
int luat_pwm_update_dutycycle(int channel, size_t pulse);
/** @}*/
#endif
