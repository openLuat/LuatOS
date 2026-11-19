
#ifndef LUAT_REPL_H
#define LUAT_REPL_H

#include "luat_base.h"

void luat_repl_init(void);
int luat_repl_enable(int enable);

void luat_repl_input_evt(size_t len);

// int luat_repl_read(char* buff, size_t len);
// int luat_repl_write(char* buff, size_t len);

#endif
