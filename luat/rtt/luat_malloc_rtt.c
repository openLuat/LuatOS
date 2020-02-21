
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"

#define DBG_TAG           "luat.heap"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

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

#ifdef RT_USING_MEMHEAP



#define RT_MEMHEAP_SIZE         RT_ALIGN(sizeof(struct rt_memheap_item), RT_ALIGN_SIZE)
typedef struct rt_memheap rt_memheap_t;
static rt_memheap_t heap;
#ifdef BSP_USING_WM_LIBRARIES
#define HEAP2_SIZE (128*1024)
    static rt_memheap_t heap2;
#else
    #define HEAP_SIZE (32*1024)
    static char HEAP[HEAP_SIZE];
#endif

static rt_err_t luat_memheap_init() {
    #ifdef BSP_USING_WM_LIBRARIES
        // TODO: w60x应该先使用哪部分的内存呢?值得讨论
        //rt_memheap_init(&heap, "heap", &(HEAP[0]), HEAP_SIZE);
        rt_memheap_init(&heap, "heap", (void*)0x20028000, HEAP2_SIZE);
    #else
        rt_memheap_init(&heap, "heap", &(HEAP[0]), HEAP_SIZE);
    #endif
    return 0;
}
#endif
INIT_COMPONENT_EXPORT(luat_memheap_init);

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  (void)ud; (void)osize;  /* not used */
  #ifdef RT_USING_MEMHEAP
    if (nsize == 0) {
        rt_memheap_free(ptr);
        return NULL;
    }
    //#ifdef BSP_USING_WM_LIBRARIES
    #if 0
        void* tmp = RT_NULL;
        // 场景A, ptr本来就没东西, 直接malloc
        if (ptr == RT_NULL) {
            tmp = rt_memheap_alloc(&heap, nsize);
            if (tmp == RT_NULL)
                tmp = rt_memheap_alloc(&heap2, nsize);
            return tmp;
        }
        // 原本属于哪个memheap呢?
        rt_memheap_t* origin;
        struct rt_memheap_item *header_ptr;
        header_ptr    = (struct rt_memheap_item *) ((rt_uint8_t *)ptr - RT_MEMHEAP_SIZE);
        origin = header_ptr->pool_ptr;
        // 尝试在原有memheap进行缩放
        tmp = rt_memheap_realloc(origin, ptr, nsize);
        if (tmp == RT_NULL) {
            // 缩放失败了, 那肯定是扩展失败
            // 那么, 我们从另外一个heap分配一个nsize的空间试试
            if (origin == &heap) {
                tmp = rt_memheap_alloc(&heap2, nsize);
            }
            else {
                tmp = rt_memheap_alloc(&heap, nsize);
            }
            // 申请成功了吗?
            if (tmp != RT_NULL) {
                // 成功了, 把老的ptr释放掉
                rt_memcpy(tmp, ptr, osize);
                rt_memheap_free(ptr);
                ptr = tmp;
            }
        }
        return tmp;
    #else
        return rt_memheap_realloc(&heap, ptr, nsize);
    #endif
  #else
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
  #endif
}
