#pragma once

#include "luat_base.h"

// 标识符, id类, 可读可写
int luat_mobile_get_imei(int index, char* buff, *size_t len);
int luat_mobile_get_muid(int index, char* buff, *size_t len);
int luat_mobile_get_imsi(int index, char* buff, *size_t len);
// int luat_mobile_get_sn(int index, char* buff, *size_t len);
int luat_mobile_get_apn(int index, char* buff, *size_t len);
// int luat_mobile_set_imei(int index, char* buff, *size_t len);
// int luat_mobile_set_muid(int index, char* buff, *size_t len);
// int luat_mobile_set_sn(int index, char* buff, *size_t len);
int luat_mobile_set_apn(int index, char* buff, *size_t len);

// 信号,基站类, 基本上是可读不可写
int luat_mobile_get_csq(int index);
int luat_mobile_get_rssi(int index);
int luat_mobile_get_rsrp(int index);
int luat_mobile_get_rsrq(int index);
int luat_mobile_get_snq(int index);
// 更复杂的基站信息, 还是结构体吧, TODO

// 进出飞行模式
int luat_mobile_flymode(int index, int mode);
