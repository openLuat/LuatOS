#ifndef LUAT_RTC_H
#define LUAT_RTC_H
#include "luat_base.h"
#include "time.h"
/**
 * @defgroup luatos_RTC  时钟接口(RTC)
 * @{
 */

/**
 * @brief 设置系统时间
 * 
 * @param tblock 
 * @return int =0成功，其他失败
 */
int luat_rtc_set(struct tm *tblock);
/**
 * @brief 获取系统时间
 * 
 * @param tblock 
 * @return int =0成功，其他失败
 */
int luat_rtc_get(struct tm *tblock);
/** @}*/
int luat_rtc_timer_start(int id, struct tm *tblock);
int luat_rtc_timer_stop(int id);
void luat_rtc_set_tamp32(uint32_t tamp);

int luat_rtc_timezone(int* timezone);

#endif
