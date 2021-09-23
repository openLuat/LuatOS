
#include "luat_base.h"

#ifndef LUAT_CMUX
#define LUAT_CMUX

#define LUAT_CMUX_CH_MAIN 0
#define LUAT_CMUX_CH_LOG  1
#define LUAT_CMUX_CH_DBG  2

void luat_cmux_write(uint8_t ch, char* buff, size_t len);

#define LUAT_CMUX_CMD_INIT "AT+CMUX=1,0,5"
#define LUAT_CMUX_RESP_OK "OK"

#endif

