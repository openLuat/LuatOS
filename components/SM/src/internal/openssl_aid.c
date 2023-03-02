#include <internal/openssl_aid.h>
#include <stdio.h>
/*
 * Pointer to memset is volatile so that compiler must de-reference
 * the pointer and can't assume that it points to any function in
 * particular (such as memset, which it then might further "optimize")
 */
typedef void *(*memset_t)(void *, int, size_t);

static volatile memset_t memset_func = memset;

void OPENSSL_cleanse(void *ptr, size_t len)
{
    memset_func(ptr, 0, len);
}

int CRYPTO_memcmp(const void *in_a, const void *in_b, size_t len)
{
    size_t i;
    const volatile unsigned char *a = in_a;
    const volatile unsigned char *b = in_b;
    unsigned char x = 0;

    for (i = 0; i < len; i++)
        x |= a[i] ^ b[i];

    return x;
}

void CRYPTO_free(void *str, const char *file, int line)
{
    printf("%s %d \n", file, line);
    free(str);
}

void CRYPTO_clear_free(void *str, size_t num, const char *file, int line)
{

    if (str == NULL)
        return;
    if (num)
        OPENSSL_cleanse(str, num);
    CRYPTO_free(str, file, line);
}

void *CRYPTO_malloc(size_t num, const char *file, int line)
{
    void *ret = NULL;
    if (num == 0)
        return NULL;
    printf("%s %d \n", file, line);
    ret = malloc(num);

    return ret;
}
