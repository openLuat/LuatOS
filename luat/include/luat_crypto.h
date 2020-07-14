
#include "luat_base.h"

#define LUAT_CRYPTO_AES_ECB 1
#define LUAT_CRYPTO_AES_CBC 2
#define LUAT_CRYPTO_AES_CTR 3
#define LUAT_CRYPTO_AES_CFB 4
#define LUAT_CRYPTO_AES_OFB 5

#define LUAT_CRYPTO_AES_PAD_ZERO 1
#define LUAT_CRYPTO_AES_PAD_5 2
#define LUAT_CRYPTO_AES_PAD_7 3

int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr);
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr);

int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr);
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr);
