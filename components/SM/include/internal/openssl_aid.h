#ifndef OPENSSL_AID_H
#define OPENSSL_AID_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>



void OPENSSL_cleanse(void *ptr, size_t len);

/*
 * CRYPTO_memcmp returns zero iff the |len| bytes at |a| and |b| are equal.
 * It takes an amount of time dependent on |len|, but independent of the
 * contents of |a| and |b|. Unlike memcmp, it cannot be used to put elements
 * into a defined order as the return value when a != b is undefined, other
 * than to be non-zero.
 */
int CRYPTO_memcmp(const void * in_a, const void * in_b, size_t len);

void CRYPTO_free(void *ptr, const char *file, int line);

void CRYPTO_clear_free(void *ptr, size_t num, const char *file, int line);

void *CRYPTO_malloc(size_t num, const char *file, int line);



#ifndef OPENSSL_FILE
# ifdef OPENSSL_NO_FILENAMES
#  define OPENSSL_FILE ""
#  define OPENSSL_LINE 0
# else
#  define OPENSSL_FILE __FILE__
#  define OPENSSL_LINE __LINE__
# endif
#endif

// #  define OPENSSL_FILE __FILE__
// #  define OPENSSL_LINE __LINE__


# define OPENSSL_clear_free(addr, num) \
        CRYPTO_clear_free(addr, num, OPENSSL_FILE, OPENSSL_LINE)
# define OPENSSL_malloc(num) \
        CRYPTO_malloc(num, OPENSSL_FILE, OPENSSL_LINE)

# define OPENSSL_free(addr) \
        CRYPTO_free(addr, OPENSSL_FILE, OPENSSL_LINE)

# define OSSL_NELEM(x)    (sizeof(x)/sizeof((x)[0]))



#endif //OPENSSL_AID_H