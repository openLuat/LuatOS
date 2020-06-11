
#include "luat_base.h"
#include "luat_crypto.h"

#include "rtthread.h"

#ifdef RT_USING_HWCRYPTO
#include "hwcrypto.h"

#ifdef RT_HWCRYPTO_USING_MD5
int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    struct rt_hwcrypto_ctx *ctx;

    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_MD5);
    if (ctx == NULL) {
        return -1; // 内存爆了??
    }
    rt_hwcrypto_hash_update(ctx, str, str_size);
    rt_hwcrypto_hash_finish(ctx, out_ptr, 32);
    rt_hwcrypto_hash_destroy(ctx);
    return 0;
}

int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return -1; // 未完成
}

#endif

#ifdef RT_HWCRYPTO_USING_SHA1
int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    struct rt_hwcrypto_ctx *ctx;

    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_SHA1);
    if (ctx == NULL) {
        return -1; // 内存爆了??
    }
    rt_hwcrypto_hash_update(ctx, str, str_size);
    rt_hwcrypto_hash_finish(ctx, out_ptr, 40);
    rt_hwcrypto_hash_destroy(ctx);
    return 0;
}
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return -1; // 未完成
}
#endif

#endif
