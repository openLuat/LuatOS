/* LuatOS allocator adapter for libsrtp; replaces upstream crypto/kernel/alloc.c. */
#include "config.h"
#include <stddef.h>
#include "../crypto/include/alloc.h"
#include "../crypto/include/crypto_kernel.h"
#include "luat_malloc.h"

srtp_debug_module_t srtp_mod_alloc = {0, "alloc"};

void *srtp_crypto_alloc(size_t size)
{
    return size ? luat_heap_calloc(1, size) : NULL;
}

void srtp_crypto_free(void *ptr)
{
    luat_heap_free(ptr);
}
