
#include "luat_base.h"

int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr);
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr);

int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr);
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr);
