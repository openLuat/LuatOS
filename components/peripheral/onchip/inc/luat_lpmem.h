
#ifndef LUAT_LPMEM_H
#define LUAT_LPMEM_H
#include "luat_base.h"

int luat_lpmem_read(size_t offset, size_t size, void*buff);
int luat_lpmem_write(size_t offset, size_t size, void*buff);
int luat_lpmem_size(void);

#endif
