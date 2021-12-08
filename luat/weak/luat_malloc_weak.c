
// 这个文件包含 系统heap和lua heap的默认实现


#include <stdlib.h>
#include <string.h>//add for memset
#include "bget.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "vmheap"
#include "luat_log.h"

#define LUAT_WEAK                     __attribute__((weak))

//------------------------------------------------
//  管理系统内存

LUAT_WEAK void* luat_heap_malloc(size_t len) {
    return malloc(len);
}

LUAT_WEAK void luat_heap_free(void* ptr) {
    free(ptr);
}

LUAT_WEAK void* luat_heap_realloc(void* ptr, size_t len) {
    return realloc(ptr, len);
}

LUAT_WEAK void* luat_heap_calloc(size_t count, size_t _size) {
    void *ptr = luat_heap_malloc(count * _size);
    if (ptr) {
        memset(ptr, 0, _size);
    }
    return ptr;
}
//------------------------------------------------

//------------------------------------------------
// ---------- 管理 LuaVM所使用的内存----------------
LUAT_WEAK void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    if (0) {
        if (ptr) {
            if (nsize) {
                // 缩放内存块
                LLOGD("realloc %p from %d to %d", ptr, osize, nsize);
            }
            else {
                // 释放内存块
                LLOGD("free %p ", ptr);
                brel(ptr);
                return NULL;
            }
        }
        else {
            // 申请内存块
            ptr = bget(nsize);
            LLOGD("malloc %p type=%d size=%d", ptr, osize, nsize);
            return ptr;
        }
    }

    if (nsize)
    {
    	void* ptmp = bgetr(ptr, nsize);
    	if(ptmp == NULL && osize >= nsize)
    	{
    		return ptr;
    	}
        return ptmp;
    }
    brel(ptr);
    return NULL;
}

LUAT_WEAK void luat_meminfo_luavm(size_t *total, size_t *used, size_t *max_used) {
	long curalloc, totfree, maxfree;
	unsigned long nget, nrel;
	bstats(&curalloc, &totfree, &maxfree, &nget, &nrel);
	*used = curalloc;
	*max_used = bstatsmaxget();
    *total = curalloc + totfree;
}

//-----------------------------------------------------------------------------
