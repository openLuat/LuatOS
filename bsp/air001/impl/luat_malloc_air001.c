


#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "luat_base.h"
#include "luat_malloc.h"

void  luat_heap_init(void) {
    return; // nop
}
void* luat_heap_malloc(size_t len) {
    return malloc(len);
}
void  luat_heap_free(void* ptr) {
    return free(ptr);
}
void* luat_heap_realloc(void* ptr, size_t len) {
    return realloc(ptr, len);
}
void* luat_heap_calloc(size_t count, size_t _size) {
    return calloc(count, _size);
}
//size_t luat_heap_getfree(void);
static void *l_alloc (void *ud, void *ptr, size_t osize, size_t nsize) {
  (void)ud; (void)osize;  /* not used */
  if (nsize == 0) {
    free(ptr);
    return NULL;
  }
  else
    return realloc(ptr, nsize);
}
// 这部分是LuaVM专属内存
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    return l_alloc(ud, ptr, osize, nsize);
}

// 两个获取内存信息的方法,单位字节
void luat_meminfo_luavm(size_t* total, size_t* used, size_t* max_used) {
    *total = 0;
    *used = 0;
    *max_used = 0;
}
void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used) {
    *total = 0;
    *used = 0;
    *max_used = 0;
}
