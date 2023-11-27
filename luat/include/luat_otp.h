
#ifndef LUAT_OTP_H
#define LUAT_OTP_H
#include "luat_base.h"


int luat_otp_read(int zone, char* buff, size_t offset, size_t len);
int luat_otp_write(int zone, char* buff, size_t offset, size_t len);
int luat_otp_erase(int zone, size_t offset, size_t len);
int luat_otp_lock(int zone);
size_t luat_otp_size(int zone);

#endif
