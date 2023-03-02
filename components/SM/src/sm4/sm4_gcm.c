/*
 * @Author: Weijie Li 
 * @Date: 2017-11-06 19:54:05 
 * @Last Modified by: Weijie Li
 * @Last Modified time: 2017-12-22 17:19:30
 */

#include <sm4/sm4.h>
#include <openssl/modes.h>

void sm4_gcm128_init(SM4_GCM128_CONTEXT *ctx, SM4_KEY *key) {
    CRYPTO_gcm128_init(ctx, key, (block128_f)sm4_encrypt);
}

void sm4_gcm128_setiv(SM4_GCM128_CONTEXT *ctx, const unsigned char *ivec,
                      size_t len) {
    CRYPTO_gcm128_setiv(ctx, ivec, len);
}

int sm4_gcm128_aad(SM4_GCM128_CONTEXT *ctx, const unsigned char *aad,
                    size_t len) {
    return CRYPTO_gcm128_aad(ctx, aad, len);
}

int sm4_gcm128_encrypt(const unsigned char *in, unsigned char *out,
                        size_t length, SM4_GCM128_CONTEXT *ctx, const int enc) {
    int ret;
    if (enc)
        ret = CRYPTO_gcm128_encrypt(ctx, in, out, length);
    else
        ret = CRYPTO_gcm128_decrypt(ctx, in, out, length);
    return ret;
}

void sm4_gcm128_tag(SM4_GCM128_CONTEXT *ctx, unsigned char *tag,
                    size_t len) {
    CRYPTO_gcm128_tag(ctx, tag, len);
}

int sm4_gcm128_finish(SM4_GCM128_CONTEXT *ctx, const unsigned char *tag,
                      size_t len) {
    return CRYPTO_gcm128_finish(ctx, tag, len);
}

void sm4_gcm128_release(SM4_GCM128_CONTEXT *ctx) {
    CRYPTO_gcm128_release(ctx);
}
