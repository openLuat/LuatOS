// crypto库的软件实现, 基于mbedtls
#ifdef CHIP_EC616
#include "FreeRTOS.h"
#endif

#include <stdlib.h>
#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_mem.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"

#include "mbedtls/cipher.h"
#include "mbedtls/md.h"
#include "mbedtls/ssl_ciphersuites.h"
#include "mbedtls/base64.h"


static void add_pkcs_padding( unsigned char *output, size_t output_len,
        size_t data_len )
{
    size_t padding_len = output_len - data_len;
    unsigned char i;

    for( i = 0; i < padding_len; i++ )
        output[data_len + i] = (unsigned char) padding_len;
}

static int get_pkcs_padding( unsigned char *input, size_t input_len,
        size_t *data_len )
{
    size_t i, pad_idx;
    unsigned char padding_len, bad = 0;

    if( NULL == input || NULL == data_len )
        return( MBEDTLS_ERR_CIPHER_BAD_INPUT_DATA );

    padding_len = input[input_len - 1];
    *data_len = input_len - padding_len;

    /* Avoid logical || since it results in a branch */
    bad |= padding_len > input_len;
    bad |= padding_len == 0;

    /* The number of bytes checked must be independent of padding_len,
     * so pick input_len, which is usually 8 or 16 (one block) */
    pad_idx = input_len - padding_len;
    for( i = 0; i < input_len; i++ )
        bad |= ( input[i] ^ padding_len ) * ( i >= pad_idx );

    return( MBEDTLS_ERR_CIPHER_INVALID_PADDING * ( bad != 0 ) );
}


int luat_crypto_cipher_xxx(luat_crypto_cipher_ctx_t* cctx) {
    uint8_t *temp = NULL;
    int ret = 0;
    int cipher_mode = 0;
    int cipher_type = 0;

    unsigned char output[32] = {0};
    size_t input_size = 0;
    size_t output_size = 0;
    size_t block_size = 0;

    mbedtls_cipher_context_t ctx;
    mbedtls_cipher_init(&ctx);

    const mbedtls_cipher_info_t * _cipher = mbedtls_cipher_info_from_string(cctx->cipher);
    if (_cipher == NULL) {
    	LLOGE("mbedtls_cipher_info fail %s not support", cctx->cipher);
        goto _error_exit;
    }

    #if MBEDTLS_VERSION_NUMBER >= 0x03000000
    cipher_mode = mbedtls_cipher_info_get_mode(_cipher);
    cipher_type = mbedtls_cipher_info_get_type(_cipher);
    #else
    cipher_mode = _cipher->mode;
    cipher_type = _cipher->type;
    #endif

	ret = mbedtls_cipher_setup(&ctx, _cipher);
    if (ret) {
        LLOGE("mbedtls_cipher_setup fail -0x%04x %s", -ret, cctx->cipher);
        goto _error_exit;
    }
    ret = mbedtls_cipher_setkey(&ctx, (const unsigned char*)cctx->key, cctx->key_size * 8, cctx->flags & 0x1);
    if (ret) {
        LLOGE("mbedtls_cipher_setkey fail -0x%04x %s", -ret, cctx->cipher);
        goto _error_exit;
    }

    if (cctx->iv_size) {
        ret = mbedtls_cipher_set_iv(&ctx, (const unsigned char*)cctx->iv, cctx->iv_size);
        if (ret) {
            LLOGE("mbedtls_cipher_set_iv fail -0x%04x %s", -ret, cctx->cipher);
            goto _error_exit;
        }
        #if defined(MBEDTLS_GCM_C) || defined(MBEDTLS_CHACHAPOLY_C)
        if (MBEDTLS_MODE_GCM == cipher_mode || MBEDTLS_CIPHER_CHACHA20_POLY1305 == cipher_type) {
            ret = mbedtls_cipher_update_ad(&ctx, (const unsigned char*)"1234567890123456", 16);
            if (ret) {
                LLOGE("mbedtls_cipher_update_ad fail -0x%04x %s", -ret, cctx->cipher);
                goto _error_exit;
            }
        }
        #endif
    }
    

    if (!strcmp("PKCS7", cctx->pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_PKCS7);
    }
    else if (!strcmp("ZERO", cctx->pad) || !strcmp("ZEROS", cctx->pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ZEROS);
    }
    else if (!strcmp("ONE_AND_ZEROS", cctx->pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ONE_AND_ZEROS);
    }
    else if (!strcmp("ZEROS_AND_LEN", cctx->pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ZEROS_AND_LEN);
    }
    else {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_NONE);
    }

    mbedtls_cipher_reset(&ctx);

    // 开始注入数据
    block_size = mbedtls_cipher_get_block_size(&ctx);

    if ((cipher_mode == MBEDTLS_MODE_ECB) && (cctx->flags & 0x1) &&
        (!strcmp("PKCS7", cctx->pad) || !strcmp("ZERO", cctx->pad) ||
         !strcmp("ZEROS_AND_LEN", cctx->pad) || !strcmp("ONE_AND_ZEROS", cctx->pad))) {
    	uint32_t new_len  = ((cctx->str_size / block_size) + 1) * block_size;
    	temp = luat_heap_malloc(new_len);
        if (temp == NULL) {
            LLOGE("out of memory when malloc cipher buffer");
            goto _exit;
        }
        memset(temp, 0, new_len);
    	memcpy(temp, cctx->str, cctx->str_size);
    	if (!strcmp("PKCS7", cctx->pad))
    	{
    		add_pkcs_padding(temp + cctx->str_size - cctx->str_size % block_size, block_size, cctx->str_size % block_size);
    	}
    	else if (!strcmp("ZEROS_AND_LEN", cctx->pad))
    	{
    		size_t padding_len = new_len - cctx->str_size;
    		temp[new_len - 1] = (unsigned char)padding_len;
    	}
    	else if (!strcmp("ONE_AND_ZEROS", cctx->pad))
    	{
    		temp[cctx->str_size] = 0x80;
    	}
    	else
    	{
    		LLOGD("zero padding");
    	}
    	cctx->str_size = new_len;
    	cctx->str = (const char*)temp;
    }
    for (size_t i = 0; i < cctx->str_size; i+=block_size) {
        input_size = cctx->str_size - i;
        if (input_size > block_size) {
            input_size = block_size;
            ret = mbedtls_cipher_update(&ctx, (const unsigned char *)(cctx->str+i), input_size, output, &output_size);
        }
        else if ((cipher_mode == MBEDTLS_MODE_ECB) && !cctx->flags &&
                 (!strcmp("PKCS7", cctx->pad) || !strcmp("ZEROS_AND_LEN", cctx->pad) || !strcmp("ONE_AND_ZEROS", cctx->pad)))
        {
        	ret = mbedtls_cipher_update(&ctx, (const unsigned char *)(cctx->str+i), input_size, output, &output_size);
            if (ret == 0) {
                if (!strcmp("PKCS7", cctx->pad)) {
                    ret = get_pkcs_padding(output, output_size, &output_size);
                    if (ret) {
                        LLOGE("get_pkcs_padding fail 0x%04X %s", -ret, cctx->cipher);
                        goto _exit;
                    }
                } else if (!strcmp("ZEROS_AND_LEN", cctx->pad)) {
                    if (output_size > 0) {
                        size_t pad_len = output[output_size - 1];
                        if (pad_len > 0 && pad_len <= output_size) {
                            output_size -= pad_len;
                        }
                    }
                } else if (!strcmp("ONE_AND_ZEROS", cctx->pad)) {
                    if (output_size > 0) {
                        size_t j = output_size;
                        while (j > 0 && output[j - 1] == 0x00) {
                            j--;
                        }
                        if (j > 0 && output[j - 1] == 0x80) {
                            output_size = j - 1;
                        }
                    }
                }
            }
        }
        else {
        	ret = mbedtls_cipher_update(&ctx, (const unsigned char *)(cctx->str+i), input_size, output, &output_size);
        }
        if (ret) {
            LLOGE("mbedtls_cipher_update fail 0x%04X %s", -ret, cctx->cipher);
            goto _exit;
        }
        //else LLOGD("mbedtls_cipher_update, output size=%ld", output_size);
        if (output_size > 0) {
            memcpy(cctx->outbuff + cctx->outlen, (const char*)output, output_size);
            cctx->outlen += output_size;
        }
        output_size = 0;
    }
    // 还需要处理GCM的tag
    

    output_size = 0;
    ret = mbedtls_cipher_finish(&ctx, (unsigned char *)output, &output_size);
    if (ret) {
        LLOGE("mbedtls_cipher_finish fail 0x%04X %s", -ret, cctx->cipher);
        goto _exit;
    }
    // 还有额外的操作
    #if defined(MBEDTLS_GCM_C) || defined(MBEDTLS_CHACHAPOLY_C)
    if (MBEDTLS_MODE_GCM == cipher_mode || MBEDTLS_CIPHER_CHACHA20_POLY1305 == cipher_type) {
        if ((cctx->flags & 0x1) == 0 && cctx->tag_len == 16) {
            ret = mbedtls_cipher_check_tag(&ctx, cctx->tag, 16);
            if (ret) {
                LLOGE("mbedtls_cipher_check_tag fail 0x%04X %s", -ret, cctx->cipher);
                goto _exit;
            }
        }
        else if (cctx->flags & 0x1) {
            cctx->tag_len = 16;
            mbedtls_cipher_write_tag(&ctx, cctx->tag, 16);
        }
    }
    #endif
    

    //else LLOGD("mbedtls_cipher_finish, output size=%ld", output_size);
    if (output_size > 0) {
        memcpy(cctx->outbuff + cctx->outlen, (const char*)output, output_size);
        cctx->outlen += output_size;
    }

_exit:
    if (temp){
        luat_heap_free(temp);
    }
    mbedtls_cipher_free(&ctx);
    return 0;
_error_exit:
    if (temp){
        luat_heap_free(temp);
    }
	mbedtls_cipher_free(&ctx);
	return -1;
}

int luat_crypto_md(const char* md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len) {
    const mbedtls_md_info_t * info = mbedtls_md_info_from_string(md);
    if (info == NULL) {
        LLOGW("no such message digest %s", md);
        return -1;
    }
    if (key_len < 1) {
        mbedtls_md(info, (const unsigned char*)str, str_size, (unsigned char*)out_ptr);
    }
    else {
        mbedtls_md_hmac(info, (const unsigned char*)key, key_len, (const unsigned char*)str, str_size, (unsigned char*)out_ptr);
    }
    return 0;
}

int luat_crypto_md_v2(const char* md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len) {
    const mbedtls_md_info_t * info = mbedtls_md_info_from_string(md);
    if (info == NULL) {
        LLOGW("no such message digest %s", md);
        return -1;
    }
    if (key_len < 1) {
        mbedtls_md(info, (const unsigned char*)str, str_size, (unsigned char*)out_ptr);
    }
    else {
        mbedtls_md_hmac(info, (const unsigned char*)key, key_len, (const unsigned char*)str, str_size, (unsigned char*)out_ptr);
    }
    return mbedtls_md_get_size(info);
}

int luat_crypto_md_file(const char* md, void* out_ptr, const char* key, size_t key_len, const char* path) {
    const mbedtls_md_info_t * info = mbedtls_md_info_from_string(md);
    if (info == NULL) {
        LLOGI("no such message digest %s", md);
        return -1;
    }
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGI("no such file %s", path);
        return -1;
    }
    mbedtls_md_context_t ctx;

    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, info, key_len > 0 ? 1 : 0);

    uint8_t buff[512];
    int len = 0;

    if (key_len > 0) {
        mbedtls_md_hmac_starts(&ctx, (const unsigned char*)key, key_len);
    }
    else {
        mbedtls_md_starts(&ctx);
    }

    while (1) {
        len = luat_fs_fread(buff, 1, 512, fd);
        if (len < 1)
            break;
        if (key_len > 0) {
            mbedtls_md_hmac_update(&ctx, buff, len);
        }
        else {
            mbedtls_md_update(&ctx, buff, len);
        }
    }
    luat_fs_fclose(fd);

    int ret = 0;
    if (key_len > 0) {
        ret = mbedtls_md_hmac_finish(&ctx, out_ptr);
    }
    else {
        ret = mbedtls_md_finish(&ctx, out_ptr);
    }
    mbedtls_md_free(&ctx);
    if (ret == 0) {
        return mbedtls_md_get_size(info);
    }
    LLOGI("md finish ret %d", ret);
    return ret;
}

int luat_crypto_md_init(const char* md, const char* key, luat_crypt_stream_t *stream) {
    const mbedtls_md_info_t * info = mbedtls_md_info_from_string(md);
    if (info == NULL) {
        return -1;
    }
    stream->ctx = luat_heap_malloc(sizeof(mbedtls_md_context_t));
    mbedtls_md_init((mbedtls_md_context_t *)stream->ctx);
    mbedtls_md_setup((mbedtls_md_context_t *)stream->ctx, info, stream->key_len > 0 ? 1 : 0);
    stream->result_size = mbedtls_md_get_size(info);
    if (stream->key_len > 0){
        mbedtls_md_hmac_starts((mbedtls_md_context_t *)stream->ctx, (const unsigned char*)key, stream->key_len);
    }
    else {
        mbedtls_md_starts((mbedtls_md_context_t *)stream->ctx);
    }
    return 0;
}

int luat_crypto_md_update(const char* str, size_t str_size, luat_crypt_stream_t *stream) {
    if (stream->key_len > 0){
        mbedtls_md_hmac_update((mbedtls_md_context_t *)stream->ctx, (const unsigned char*)str, str_size);
    }
    else {
        mbedtls_md_update((mbedtls_md_context_t *)stream->ctx, (const unsigned char*)str, str_size);
    }
    return 0;
}

int luat_crypto_md_finish(void* out_ptr, luat_crypt_stream_t *stream) {
    int ret = 0;
    if (stream->key_len > 0) {
        ret = mbedtls_md_hmac_finish((mbedtls_md_context_t *)stream->ctx, out_ptr);
    }
    else {
        ret = mbedtls_md_finish((mbedtls_md_context_t *)stream->ctx, out_ptr);
    }
    mbedtls_md_free((mbedtls_md_context_t *)stream->ctx);
    luat_heap_free((mbedtls_md_context_t *)stream->ctx);
    stream->ctx = NULL;
    if (ret == 0) {
        return stream->result_size;
    }
    LLOGI("md finish ret %d", ret);
    return ret;
}

int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("MD5", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("MD5", str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("SHA1", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("SHA1", str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("SHA256", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("SHA256", str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("SHA512", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("SHA512", str, str_size, out_ptr, mac, mac_size);
}

const int *mbedtls_cipher_list( void );

int luat_crypto_cipher_list(const char** list, size_t* len) {
    size_t count = 0;
    size_t limit = *len;
    const int *cipher = mbedtls_cipher_list();
    for (size_t i = 0; i < limit; i++)
    {
        if (cipher[i] == 0)
            break;
        count ++;
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
        list[i] = mbedtls_cipher_info_get_name(mbedtls_cipher_info_from_type(cipher[i]));
#else
        list[i] = mbedtls_cipher_info_from_type(cipher[i])->name;
#endif
    }
    *len = count;
    return 0;
}

int luat_crypto_cipher_suites(const char** list, size_t* len) {
#if defined(MBEDTLS_SSL_TLS_C) && defined(LUAT_USE_NETWORK)
    size_t count = 0;
    size_t limit = *len;
    const int *suites = mbedtls_ssl_list_ciphersuites();
    const mbedtls_ssl_ciphersuite_t * suite = NULL;
    for (size_t i = 0; i < limit; i++)
    {
        if (suites[i] == 0)
            break;
        suite = mbedtls_ssl_ciphersuite_from_id(suites[i]);
        if (suite == NULL)
            continue;
        count ++;
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
        list[i] = mbedtls_ssl_ciphersuite_get_name(suite);
#else
        list[i] = suite->name;
#endif
    }
    *len = count;
#else
    (void)list;
    *len = 0;
#endif
    return 0;
}

/**
 * @brief BASE64加密
 * @param dst buffer
 * @param dlen buffer长度
 * @param olen 写入的字节数
 * @param src 加密密钥
 * @param slen 加密密钥长度
 * @return 0成功
 */
/* ============================================================
 * PK 签名 / 验签实现 (基于 mbedtls pk 系列 API)
 * 支持 RSA、ECDSA 等所有 mbedtls pk 支持的算法
 * 自动识别 PEM（检测 "-----" 前缀）和 DER 二进制格式
 * ============================================================ */
#if defined(MBEDTLS_PK_C) && defined(MBEDTLS_PK_PARSE_C)
#include "mbedtls/pk.h"

/* 简单 RNG 回调：优先使用平台 TRNG，回退到 rand() */
static int luat_pk_rng_cb(void *ctx, unsigned char *output, size_t len) {
    (void)ctx;
    if (luat_crypto_trng((char *)output, len) == 0)
        return 0;
    /* fallback */
    for (size_t i = 0; i < len; i++)
        output[i] = (unsigned char)rand();
    return 0;
}

/* 判断是否为 PEM 格式（以 "-----" 开头且末尾含 '\0'） */
static int luat_pk_is_pem(const uint8_t *data, size_t len) {
    return (len > 5 && memcmp(data, "-----", 5) == 0);
}

/* 申请一块含 NUL 终止的 PEM 缓冲区（PEM 解析需要 '\0'）*/
static uint8_t *luat_pk_dup_pem(const uint8_t *data, size_t len) {
    uint8_t *buf = (uint8_t *)luat_heap_malloc(len + 1);
    if (buf) {
        memcpy(buf, data, len);
        buf[len] = '\0';
    }
    return buf;
}

int luat_crypto_pk_sign(int md_type,
                        const uint8_t *hash, size_t hash_len,
                        const uint8_t *privkey, size_t privkey_len,
                        const char *password, size_t pwd_len,
                        uint8_t **sig_out, size_t *sig_len_out)
{
    int ret = -1;
    mbedtls_pk_context pk;
    uint8_t *pem_buf = NULL;

    *sig_out = NULL;
    *sig_len_out = 0;

    mbedtls_pk_init(&pk);

    /* 解析私钥 */
    if (luat_pk_is_pem(privkey, privkey_len)) {
        pem_buf = luat_pk_dup_pem(privkey, privkey_len);
        if (!pem_buf) goto cleanup;
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
        ret = mbedtls_pk_parse_key(&pk, pem_buf, privkey_len + 1,
                                   (const uint8_t *)password, pwd_len,
                                   luat_pk_rng_cb, NULL);
#else
        ret = mbedtls_pk_parse_key(&pk, pem_buf, privkey_len + 1,
                                   (const uint8_t *)password, pwd_len);
#endif
        luat_heap_free(pem_buf);
        pem_buf = NULL;
    } else {
        /* DER 格式 */
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
        ret = mbedtls_pk_parse_key(&pk, privkey, privkey_len,
                                   (const uint8_t *)password, pwd_len,
                                   luat_pk_rng_cb, NULL);
#else
        ret = mbedtls_pk_parse_key(&pk, privkey, privkey_len,
                                   (const uint8_t *)password, pwd_len);
#endif
    }
    if (ret != 0) {
        LLOGE("pk_sign: parse privkey failed -0x%04x", -ret);
        goto cleanup;
    }

    /* 分配签名缓冲区 */
    size_t sig_max = MBEDTLS_PK_SIGNATURE_MAX_SIZE;
    if (sig_max == 0) sig_max = 1024; /* 防御性回退 */
    *sig_out = (uint8_t *)luat_heap_malloc(sig_max);
    if (!*sig_out) {
        ret = -1;
        goto cleanup;
    }

    /* 执行签名 */
    size_t sig_len = 0;
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    ret = mbedtls_pk_sign(&pk, (mbedtls_md_type_t)md_type, hash, hash_len,
                          *sig_out, sig_max, &sig_len,
                          luat_pk_rng_cb, NULL);
#else
    ret = mbedtls_pk_sign(&pk, (mbedtls_md_type_t)md_type, hash, hash_len,
                          *sig_out, &sig_len,
                          luat_pk_rng_cb, NULL);
#endif
    if (ret != 0) {
        LLOGE("pk_sign: sign failed -0x%04x", -ret);
        luat_heap_free(*sig_out);
        *sig_out = NULL;
    } else {
        *sig_len_out = sig_len;
    }

cleanup:
    mbedtls_pk_free(&pk);
    return ret;
}

int luat_crypto_pk_verify(int md_type,
                          const uint8_t *hash, size_t hash_len,
                          const uint8_t *pubkey, size_t pubkey_len,
                          const uint8_t *sig, size_t sig_len)
{
    int ret = -1;
    mbedtls_pk_context pk;
    uint8_t *pem_buf = NULL;

    mbedtls_pk_init(&pk);

    /* 解析公钥 */
    if (luat_pk_is_pem(pubkey, pubkey_len)) {
        pem_buf = luat_pk_dup_pem(pubkey, pubkey_len);
        if (!pem_buf) goto cleanup;
        ret = mbedtls_pk_parse_public_key(&pk, pem_buf, pubkey_len + 1);
        luat_heap_free(pem_buf);
        pem_buf = NULL;
    } else {
        /* DER 格式 */
        ret = mbedtls_pk_parse_public_key(&pk, pubkey, pubkey_len);
    }
    if (ret != 0) {
        LLOGE("pk_verify: parse pubkey failed -0x%04x", -ret);
        goto cleanup;
    }

    ret = mbedtls_pk_verify(&pk, (mbedtls_md_type_t)md_type, hash, hash_len, sig, sig_len);
    if (ret != 0) {
        LLOGD("pk_verify: verify failed -0x%04x", -ret);
        ret = 1;
    }

cleanup:
    mbedtls_pk_free(&pk);
    return ret;
}

const char *luat_crypto_pk_type(const uint8_t *key, size_t key_len, int is_private)
{
    int ret;
    mbedtls_pk_context pk;
    uint8_t *pem_buf = NULL;
    const char *type_str = NULL;

    mbedtls_pk_init(&pk);

    if (luat_pk_is_pem(key, key_len)) {
        pem_buf = luat_pk_dup_pem(key, key_len);
        if (!pem_buf) goto done;
        if (is_private) {
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
            ret = mbedtls_pk_parse_key(&pk, pem_buf, key_len + 1,
                                       NULL, 0, luat_pk_rng_cb, NULL);
#else
            ret = mbedtls_pk_parse_key(&pk, pem_buf, key_len + 1, NULL, 0);
#endif
        } else {
            ret = mbedtls_pk_parse_public_key(&pk, pem_buf, key_len + 1);
        }
        luat_heap_free(pem_buf);
        pem_buf = NULL;
    } else {
        if (is_private) {
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
            ret = mbedtls_pk_parse_key(&pk, key, key_len,
                                       NULL, 0, luat_pk_rng_cb, NULL);
#else
            ret = mbedtls_pk_parse_key(&pk, key, key_len, NULL, 0);
#endif
        } else {
            ret = mbedtls_pk_parse_public_key(&pk, key, key_len);
        }
    }

    if (ret == 0) {
        switch (mbedtls_pk_get_type(&pk)) {
            case MBEDTLS_PK_RSA:      type_str = "rsa";     break;
            case MBEDTLS_PK_ECKEY:    type_str = "ec";      break;
            case MBEDTLS_PK_ECKEY_DH: type_str = "ec_dh";   break;
            case MBEDTLS_PK_ECDSA:    type_str = "ecdsa";   break;
            case MBEDTLS_PK_OPAQUE:   type_str = "opaque";  break;
            default:                  type_str = "unknown";  break;
        }
    }

done:
    mbedtls_pk_free(&pk);
    return type_str;
}

#if defined(MBEDTLS_PK_WRITE_C) && defined(MBEDTLS_GENPRIME)
#include "mbedtls/rsa.h"
#include "mbedtls/ecp.h"

/* 将ECP曲线名称字符串转换为mbedtls group id */
static mbedtls_ecp_group_id luat_pk_curve_from_name(const char *name) {
    if (!name || name[0] == '\0') return MBEDTLS_ECP_DP_SECP256R1; /* 默认P-256 */
    if (strcmp(name, "P-256") == 0 || strcmp(name, "secp256r1") == 0) return MBEDTLS_ECP_DP_SECP256R1;
    if (strcmp(name, "P-384") == 0 || strcmp(name, "secp384r1") == 0) return MBEDTLS_ECP_DP_SECP384R1;
    if (strcmp(name, "P-521") == 0 || strcmp(name, "secp521r1") == 0) return MBEDTLS_ECP_DP_SECP521R1;
    return MBEDTLS_ECP_DP_SECP256R1;
}

int luat_crypto_pk_generate(const char *key_type,
                            const char *param,
                            uint8_t **priv_pem, size_t *priv_len,
                            uint8_t **pub_pem,  size_t *pub_len) {
    if (!key_type || !priv_pem || !priv_len || !pub_pem || !pub_len) return -1;
    *priv_pem = NULL; *pub_pem = NULL; *priv_len = 0; *pub_len = 0;

    mbedtls_pk_context pk;
    mbedtls_pk_init(&pk);

    int ret = -1;
    /* PEM 缓冲区, 4096 对 RSA-4096 足够; EC 只需几百字节 */
    const size_t BUF_SIZE = 4096;
    uint8_t *priv_buf = (uint8_t *)luat_heap_malloc(BUF_SIZE);
    uint8_t *pub_buf  = (uint8_t *)luat_heap_malloc(BUF_SIZE);
    if (!priv_buf || !pub_buf) { ret = -2; goto done; }

    if (strcmp(key_type, "rsa") == 0) {
        int bits = 2048;
        if (param && param[0]) bits = atoi(param);
        if (bits < 512) bits = 512;
        if (bits > 8192) bits = 8192;

        ret = mbedtls_pk_setup(&pk, mbedtls_pk_info_from_type(MBEDTLS_PK_RSA));
        if (ret != 0) goto done;

        ret = mbedtls_rsa_gen_key(mbedtls_pk_rsa(pk), luat_pk_rng_cb, NULL, bits, 65537);
        if (ret != 0) goto done;

    } else if (strcmp(key_type, "ec") == 0 || strcmp(key_type, "ecdsa") == 0) {
        mbedtls_ecp_group_id gid = luat_pk_curve_from_name(param);

        ret = mbedtls_pk_setup(&pk, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
        if (ret != 0) goto done;

        ret = mbedtls_ecp_gen_key(gid, mbedtls_pk_ec(pk), luat_pk_rng_cb, NULL);
        if (ret != 0) goto done;

    } else {
        ret = -3; /* 不支持的密钥类型 */
        goto done;
    }

    ret = mbedtls_pk_write_key_pem(&pk, priv_buf, BUF_SIZE);
    if (ret != 0) goto done;

    ret = mbedtls_pk_write_pubkey_pem(&pk, pub_buf, BUF_SIZE);
    if (ret != 0) goto done;

    /* 成功: 将结果复制到精确大小的缓冲区 */
    {
        size_t pl = strlen((char *)priv_buf);
        size_t ql = strlen((char *)pub_buf);
        uint8_t *pp = (uint8_t *)luat_heap_malloc(pl + 1);
        uint8_t *qp = (uint8_t *)luat_heap_malloc(ql + 1);
        if (!pp || !qp) {
            luat_heap_free(pp); luat_heap_free(qp);
            ret = -2; goto done;
        }
        memcpy(pp, priv_buf, pl + 1);
        memcpy(qp, pub_buf,  ql + 1);
        *priv_pem = pp; *priv_len = pl;
        *pub_pem  = qp; *pub_len  = ql;
        ret = 0;
    }

done:
    luat_heap_free(priv_buf);
    luat_heap_free(pub_buf);
    mbedtls_pk_free(&pk);
    return ret;
}

#else
int luat_crypto_pk_generate(const char *key_type,
                            const char *param,
                            uint8_t **priv_pem, size_t *priv_len,
                            uint8_t **pub_pem,  size_t *pub_len) {
    (void)key_type; (void)param;
    (void)priv_pem; (void)priv_len; (void)pub_pem; (void)pub_len;
    return -1;
}
#endif /* MBEDTLS_PK_WRITE_C && MBEDTLS_GENPRIME */

#else
/* 无 mbedtls pk 支持时提供空实现 */
int luat_crypto_pk_sign(int md_type,
                        const uint8_t *hash, size_t hash_len,
                        const uint8_t *privkey, size_t privkey_len,
                        const char *password, size_t pwd_len,
                        uint8_t **sig_out, size_t *sig_len_out) {
    (void)md_type; (void)hash; (void)hash_len;
    (void)privkey; (void)privkey_len; (void)password; (void)pwd_len;
    *sig_out = NULL; *sig_len_out = 0;
    return -1;
}
int luat_crypto_pk_verify(int md_type,
                          const uint8_t *hash, size_t hash_len,
                          const uint8_t *pubkey, size_t pubkey_len,
                          const uint8_t *sig, size_t sig_len) {
    (void)md_type; (void)hash; (void)hash_len;
    (void)pubkey; (void)pubkey_len; (void)sig; (void)sig_len;
    return -1;
}
const char *luat_crypto_pk_type(const uint8_t *key, size_t key_len, int is_private) {
    (void)key; (void)key_len; (void)is_private;
    return NULL;
}
int luat_crypto_pk_generate(const char *key_type,
                            const char *param,
                            uint8_t **priv_pem, size_t *priv_len,
                            uint8_t **pub_pem,  size_t *pub_len) {
    (void)key_type; (void)param;
    (void)priv_pem; (void)priv_len; (void)pub_pem; (void)pub_len;
    return -1;
}
#endif /* MBEDTLS_PK_C && MBEDTLS_PK_PARSE_C */

int luat_crypto_base64_encode( unsigned char *dst, size_t dlen, size_t *olen, const unsigned char *src, size_t slen )
{
    mbedtls_base64_encode(dst, dlen, olen, src, slen);
    return 0;
}

/**
 * @brief BASE64解密
 * @param dst buffer
 * @param dlen buffer长度
 * @param olen 写入的字节数
 * @param src 密钥
 * @param slen 密钥长度
 * @return 0成功
 */
int luat_crypto_base64_decode( unsigned char *dst, size_t dlen, size_t *olen, const unsigned char *src, size_t slen )
{
    mbedtls_base64_decode(dst, dlen, olen, src, slen);
    return 0;
}

