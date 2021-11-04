
#include "luat_base.h"

uint8_t echo_enable;
uint8_t cmux_state;

void luat_shell_write(char* buff, size_t len);
void luat_shell_print(const char* str);
char* luat_shell_read(size_t *len);
void luat_shell_notify_recv(void);
void luat_shell_notify_read(void);

