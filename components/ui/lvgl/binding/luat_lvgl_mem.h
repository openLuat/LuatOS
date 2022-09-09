#ifndef LUAT_LVGL_MEM
#define LUAT_LVGL_MEM

//#include "luat_base.h"
//#include "luat_malloc.h"

void* luat_lvgl_malloc(int len);
void* luat_lvgl_free(void* ptr);
void* luat_lvgl_realloc(void* ptr, int _new);

int luat_lvgl_mem_get_size(void* ptr);

#endif
