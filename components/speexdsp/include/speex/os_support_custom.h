#ifndef LUAT_SPEEX_OS_SUPPORT_CUSTOM_H
#define LUAT_SPEEX_OS_SUPPORT_CUSTOM_H

#include <string.h>
#include <stdlib.h>

#include "luat_mem.h"

#define OVERRIDE_SPEEX_ALLOC
static inline void *speex_alloc(int size) {
    return luat_heap_calloc(1, size);
}

#define OVERRIDE_SPEEX_ALLOC_SCRATCH
static inline void *speex_alloc_scratch(int size) {
    return luat_heap_calloc(1, size);
}

#define OVERRIDE_SPEEX_REALLOC
static inline void *speex_realloc(void *ptr, int size) {
    return luat_heap_realloc(ptr, size);
}

#define OVERRIDE_SPEEX_FREE
static inline void speex_free(void *ptr) {
    luat_heap_free(ptr);
}

#define OVERRIDE_SPEEX_FREE_SCRATCH
static inline void speex_free_scratch(void *ptr) {
    luat_heap_free(ptr);
}

#define OVERRIDE_SPEEX_COPY
#define SPEEX_COPY(dst, src, n) (memcpy((dst), (src), (n) * sizeof(*(dst))))

#define OVERRIDE_SPEEX_MOVE
#define SPEEX_MOVE(dst, src, n) (memmove((dst), (src), (n) * sizeof(*(dst))))

#define OVERRIDE_SPEEX_MEMSET
#define SPEEX_MEMSET(dst, c, n) (memset((dst), (c), (n) * sizeof(*(dst))))

#define OVERRIDE_SPEEX_FATAL
static inline void _speex_fatal(const char *str, const char *file, int line) {
    (void)str;
    (void)file;
    (void)line;
}

#define OVERRIDE_SPEEX_WARNING
static inline void speex_warning(const char *str) {
    (void)str;
}

#define OVERRIDE_SPEEX_WARNING_INT
static inline void speex_warning_int(const char *str, int val) {
    (void)str;
    (void)val;
}

#define OVERRIDE_SPEEX_NOTIFY
static inline void speex_notify(const char *str) {
    (void)str;
}

#define OVERRIDE_SPEEX_PUTC
static inline void _speex_putc(int ch, void *file) {
    (void)ch;
    (void)file;
}

#endif