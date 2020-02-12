
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"

// 导入rt-thread的内存管理函数

void  luat_heap_init(void) {};
void* luat_heap_malloc(size_t len){
    return rt_malloc(len);
}
void  luat_heap_free(void* ptr) {
    rt_free(ptr);
}
void* luat_heap_realloc(void* ptr, size_t len) {
    return rt_realloc(ptr, len);
}
void* luat_heap_calloc(size_t count, size_t _size) {
    return rt_calloc(count, _size);
}
size_t luat_heap_getfree(void) {
    return 1024*1024*16;
}

/*
#define LUA_TNIL		0
#define LUA_TBOOLEAN		1
#define LUA_TLIGHTUSERDATA	2
#define LUA_TNUMBER		3
#define LUA_TSTRING		4
#define LUA_TTABLE		5
#define LUA_TFUNCTION		6
#define LUA_TUSERDATA		7
#define LUA_TTHREAD		8

#define LUA_NUMTAGS		9
*/

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  (void)ud; (void)osize;  /* not used */

#if 0
  if (ptr == RT_NULL) {
      // 新对象
      ptr = rt_realloc(ptr, nsize);
      switch (osize)
      {
      case 0:
          rt_kprintf("alloc nil    ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 1:
          rt_kprintf("alloc bool   ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 2:
          rt_kprintf("alloc ludata ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 3:
          rt_kprintf("alloc number ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 4:
          rt_kprintf("alloc string ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 5:
          rt_kprintf("alloc table  ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 6:
          rt_kprintf("alloc func   ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 7:
          rt_kprintf("alloc udata  ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 8:
          rt_kprintf("alloc thread ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      case 9:
          rt_kprintf("alloc ntags  ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
          break;
      
      default:
          break;
      }
      return ptr;
  }
  else if (nsize == 0) {
      rt_kprintf("free  ptr=0x%08X osize=%d\n", ptr, osize);
  }
  else {
      rt_kprintf("realloc ptr=0x%08X osize=%d nsize=%d\n", ptr, osize, nsize);
  }
#endif

  if (nsize == 0) {
    rt_free(ptr);
    return NULL;
  }
  else {
    // 是不是增减内存占用呢?
    #ifdef RT_MEM_STATS
    if (ptr == NULL || nsize > osize) {
        rt_uint32_t total;
        rt_uint32_t used;
        rt_uint32_t max_used;
        rt_memory_info(&total, &used, &max_used);
        #ifdef RT_WLAN_MANAGE_ENABLE
            #include "wlan_dev.h"
            #include <wlan_mgnt.h>
            if (!rt_wlan_is_ready()) {
                if (total - used < 10*1024) {
                    return RT_NULL;
                }
            }
        #endif
        if (total - used < 4*1024) {
            return RT_NULL;
        }
    }
    #endif
    return rt_realloc(ptr, nsize);
  }
    
}
