// crypto库的软件实现, 基于mbedtls

#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"
#include "mbedtls/config.h"
#include "mbedtls/cipher.h"
#include "mbedtls/sha1.h"
#include "mbedtls/sha256.h"
#include "mbedtls/sha512.h"
#include "mbedtls/md5.h"

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

int l_crypto_cipher_xxx(lua_State *L, uint8_t flags) {
    size_t cipher_size = 0;
    size_t pad_size = 0;
    size_t str_size = 0;
    size_t key_size = 0;
    size_t iv_size = 0;
    const char* cipher = luaL_optlstring(L, 1, "AES-128-ECB", &cipher_size);
    const char* pad = luaL_optlstring(L, 2, "PKCS7", &pad_size);
    const char* str = luaL_checklstring(L, 3, &str_size);
    const char* key = luaL_checklstring(L, 4, &key_size);
    const char* iv = luaL_optlstring(L, 5, "", &iv_size);
    uint8_t *temp = NULL;
    int ret = 0;

    unsigned char output[32] = {0};
    size_t input_size = 0;
    size_t output_size = 0;
    size_t block_size = 0;

    luaL_Buffer buff;
    luaL_buffinit(L, &buff);

    mbedtls_cipher_context_t ctx;
    mbedtls_cipher_init(&ctx);

    const mbedtls_cipher_info_t * _cipher = mbedtls_cipher_info_from_string(cipher);
    if (_cipher == NULL) {
    	LLOGE("mbedtls_cipher_info fail %s not support", cipher);
        goto _error_exit;
    }


	ret = mbedtls_cipher_setup(&ctx, _cipher);
    if (ret) {
        LLOGE("mbedtls_cipher_setup fail -0x%04x", -ret);
        goto _error_exit;
    }
    ret = mbedtls_cipher_setkey(&ctx, key, key_size * 8, flags & 0x1);
    if (ret) {
        LLOGE("mbedtls_cipher_setkey fail -0x%04x", -ret);
        goto _error_exit;
    }

    if (iv_size) {
        ret = mbedtls_cipher_set_iv(&ctx, iv, iv_size);
        if (ret) {
            LLOGE("mbedtls_cipher_set_iv fail -0x%04x", -ret);
            goto _error_exit;
        }
    }

    mbedtls_cipher_reset(&ctx);

    if (!strcmp("PKCS7", pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_PKCS7);
    }
    else if (!strcmp("ZERO", pad) || !strcmp("ZEROS", pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ZEROS);
    }
    else if (!strcmp("ONE_AND_ZEROS", pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ONE_AND_ZEROS);
    }
    else if (!strcmp("ZEROS_AND_LEN", pad)) {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ZEROS_AND_LEN);
    }
    else {
        mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_NONE);
    }

    // 开始注入数据
    block_size = mbedtls_cipher_get_block_size(&ctx);

    if ((ctx.cipher_info->mode == MBEDTLS_MODE_ECB) && !strcmp("PKCS7", pad) && (flags & 0x1)) {
    	uint32_t new_len  = ((str_size / block_size) + 1) * block_size;
    	temp = luat_heap_malloc(new_len);
    	memcpy(temp, str, str_size);
    	add_pkcs_padding(temp + str_size - str_size % block_size, block_size, str_size % block_size);
    	str_size = new_len;
    	str = temp;
    }
    for (size_t i = 0; i < str_size; i+=block_size) {
        input_size = str_size - i;
        if (input_size > block_size) {
            input_size = block_size;
            ret = mbedtls_cipher_update(&ctx, str+i, input_size, output, &output_size);
        }
        else if ((ctx.cipher_info->mode == MBEDTLS_MODE_ECB) && !strcmp("PKCS7", pad) && !flags)
        {
        	ret = mbedtls_cipher_update(&ctx, str+i, input_size, output, &output_size);
        	get_pkcs_padding(output, output_size, &output_size);
        }
        else {
        	ret = mbedtls_cipher_update(&ctx, str+i, input_size, output, &output_size);
        }
        if (ret) {
            LLOGE("mbedtls_cipher_update fail %ld", ret);
            goto _exit;
        }
        //else LLOGD("mbedtls_cipher_update, output size=%ld", output_size);
        if (output_size > 0) {
            luaL_addlstring(&buff, output, output_size);
        }
        output_size = 0;
    }
    output_size = 0;
    ret = mbedtls_cipher_finish(&ctx, output, &output_size);
    if (ret) {
        LLOGE("mbedtls_cipher_finish fail %ld", ret);
        goto _exit;
    }
    //else LLOGD("mbedtls_cipher_finish, output size=%ld", output_size);
    if (output_size > 0)
        luaL_addlstring(&buff, output, output_size);

_exit:
	luat_heap_free(temp);
    mbedtls_cipher_free(&ctx);
    luaL_pushresult(&buff);
    return 1;
_error_exit:
	luat_heap_free(temp);
	mbedtls_cipher_free(&ctx);
	return 0;
}


void luat_crypto_HmacSha1(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);
void luat_crypto_HmacSha256(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);
void luat_crypto_HmacSha512(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);
void luat_crypto_HmacMd5(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);

int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_md5_context ctx;
    mbedtls_md5_init(&ctx);

    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_md5_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_md5_free(&ctx);
    return 0;
}

int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacMd5((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}

int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_sha1_context ctx;
    mbedtls_sha1_init(&ctx);

    mbedtls_sha1_starts(&ctx);
    mbedtls_sha1_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_sha1_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_sha1_free(&ctx);
    return 0;
}

int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacSha1((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}

int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);

    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_sha256_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_sha256_free(&ctx);
    return 0;
}

int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_sha512_context ctx;
    mbedtls_sha512_init(&ctx);

    mbedtls_sha512_starts(&ctx, 0);
    mbedtls_sha512_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_sha512_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_sha512_free(&ctx);
    return 0;
}

int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacSha256((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}

int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacSha512((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}


///----------------------------

#define ALI_SHA1_KEY_IOPAD_SIZE (64)
#define ALI_SHA1_DIGEST_SIZE    (20)

#define ALI_SHA256_KEY_IOPAD_SIZE   (64)
#define ALI_SHA256_DIGEST_SIZE      (32)

#define ALI_SHA512_KEY_IOPAD_SIZE   (128)
#define ALI_SHA512_DIGEST_SIZE      (64)

#define ALI_MD5_KEY_IOPAD_SIZE  (64)
#define ALI_MD5_DIGEST_SIZE     (16)


/*
 * output = SHA-1( input buffer )
 */
void luat_crypto_HmacSha1(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_sha1_context ctx;
    unsigned char k_ipad[ALI_SHA1_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_SHA1_KEY_IOPAD_SIZE] = {0};
    unsigned char tempbuf[ALI_SHA1_DIGEST_SIZE];

    memset(k_ipad, 0x36, ALI_SHA1_KEY_IOPAD_SIZE);
    memset(k_opad, 0x5C, ALI_SHA1_KEY_IOPAD_SIZE);

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_SHA1_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_sha1_init(&ctx);

    mbedtls_sha1_starts(&ctx);
    mbedtls_sha1_update(&ctx, k_ipad, ALI_SHA1_KEY_IOPAD_SIZE);
    mbedtls_sha1_update(&ctx, input, ilen);
    mbedtls_sha1_finish(&ctx, tempbuf);

    mbedtls_sha1_starts(&ctx);
    mbedtls_sha1_update(&ctx, k_opad, ALI_SHA1_KEY_IOPAD_SIZE);
    mbedtls_sha1_update(&ctx, tempbuf, ALI_SHA1_DIGEST_SIZE);
    mbedtls_sha1_finish(&ctx, tempbuf);

    memcpy(output, tempbuf, ALI_SHA1_DIGEST_SIZE);

    mbedtls_sha1_free(&ctx);
}
/*
 * output = SHA-256( input buffer )
 */
void luat_crypto_HmacSha256(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_sha256_context ctx;
    unsigned char k_ipad[ALI_SHA256_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_SHA256_KEY_IOPAD_SIZE] = {0};

    memset(k_ipad, 0x36, 64);
    memset(k_opad, 0x5C, 64);

    if ((NULL == input) || (NULL == key) || (NULL == output)) {
        return;
    }

    if (keylen > ALI_SHA256_KEY_IOPAD_SIZE) {
        return;
    }

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_SHA256_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_sha256_init(&ctx);

    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, k_ipad, ALI_SHA256_KEY_IOPAD_SIZE);
    mbedtls_sha256_update(&ctx, input, ilen);
    mbedtls_sha256_finish(&ctx, output);

    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, k_opad, ALI_SHA256_KEY_IOPAD_SIZE);
    mbedtls_sha256_update(&ctx, output, ALI_SHA256_DIGEST_SIZE);
    mbedtls_sha256_finish(&ctx, output);

    mbedtls_sha256_free(&ctx);
}

void luat_crypto_HmacSha512(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_sha512_context ctx;
    unsigned char k_ipad[ALI_SHA512_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_SHA512_KEY_IOPAD_SIZE] = {0};

    memset(k_ipad, 0x36, ALI_SHA512_KEY_IOPAD_SIZE);
    memset(k_opad, 0x5C, ALI_SHA512_KEY_IOPAD_SIZE);

    if ((NULL == input) || (NULL == key) || (NULL == output)) {
        return;
    }

    if (keylen > ALI_SHA512_KEY_IOPAD_SIZE) {
        return;
    }

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_SHA512_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_sha512_init(&ctx);

    mbedtls_sha512_starts(&ctx, 0);
    mbedtls_sha512_update(&ctx, k_ipad, ALI_SHA512_KEY_IOPAD_SIZE);
    mbedtls_sha512_update(&ctx, input, ilen);
    mbedtls_sha512_finish(&ctx, output);

    mbedtls_sha512_starts(&ctx, 0);
    mbedtls_sha512_update(&ctx, k_opad, ALI_SHA512_KEY_IOPAD_SIZE);
    mbedtls_sha512_update(&ctx, output, ALI_SHA512_DIGEST_SIZE);
    mbedtls_sha512_finish(&ctx, output);

    mbedtls_sha512_free(&ctx);
}

void luat_crypto_HmacMd5(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_md5_context ctx;
    unsigned char k_ipad[ALI_MD5_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_MD5_KEY_IOPAD_SIZE] = {0};
    unsigned char tempbuf[ALI_MD5_DIGEST_SIZE];

    memset(k_ipad, 0x36, ALI_MD5_KEY_IOPAD_SIZE);
    memset(k_opad, 0x5C, ALI_MD5_KEY_IOPAD_SIZE);

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_MD5_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_md5_init(&ctx);

    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, k_ipad, ALI_MD5_KEY_IOPAD_SIZE);
    mbedtls_md5_update(&ctx, input, ilen);
    mbedtls_md5_finish(&ctx, tempbuf);

    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, k_opad, ALI_MD5_KEY_IOPAD_SIZE);
    mbedtls_md5_update(&ctx, tempbuf, ALI_MD5_DIGEST_SIZE);
    mbedtls_md5_finish(&ctx, tempbuf);

    memcpy(output, tempbuf, ALI_MD5_DIGEST_SIZE);
    mbedtls_md5_free(&ctx);
}
