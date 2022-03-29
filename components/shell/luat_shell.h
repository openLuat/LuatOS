#ifndef LUAT_SHELL_H
#define LUAT_SHELL_H
#include "luat_base.h"

#define LUAT_CMUX_CMD_INIT "AT+CMUX=1,0,5"

typedef struct luat_shell
{
    uint8_t echo_enable;
    uint8_t ymodem_enable;
}luat_shell_t;

typedef void (*luat_shell_cmd)(char* buff, size_t len);

typedef struct luat_shell_cmd_reg
{
    const char* prefix;
    luat_shell_cmd cmd;
}luat_shell_cmd_reg_t;



void luat_shell_write(char* buff, size_t len);
void luat_shell_print(const char* str);
char* luat_shell_read(size_t *len);
void luat_shell_notify_recv(void);
void luat_shell_notify_read(void);
void luat_shell_exec(char* uart_buff, size_t rcount);

// new shell
void luat_shell_push(char* uart_buff, size_t rcount);

#endif
