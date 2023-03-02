/* ====================================================================
 * Copyright (c) 2014 - 2017 The GmSSL Project.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. All advertising materials mentioning features or use of this
 *    software must display the following acknowledgment:
 *    "This product includes software developed by the GmSSL Project.
 *    (http://gmssl.org/)"
 *
 * 4. The name "GmSSL Project" must not be used to endorse or promote
 *    products derived from this software without prior written
 *    permission. For written permission, please contact
 *    guanzhi1980@gmail.com.
 *
 * 5. Products derived from this software may not be called "GmSSL"
 *    nor may "GmSSL" appear in their names without prior written
 *    permission of the GmSSL Project.
 *
 * 6. Redistributions of any form whatsoever must retain the following
 *    acknowledgment:
 *    "This product includes software developed by the GmSSL Project
 *    (http://gmssl.org/)"
 *
 * THIS SOFTWARE IS PROVIDED BY THE GmSSL PROJECT ``AS IS'' AND ANY
 * EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE GmSSL PROJECT OR
 * ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 * ====================================================================
 */

#ifndef HEADER_SM4_H
#define HEADER_SM4_H

// #include <openssl/opensslconf.h>
#ifndef NO_GMSSL

# define SM4_ENCRYPT     1
# define SM4_DECRYPT     0

#define SM4_KEY_LENGTH		16
#define SM4_BLOCK_SIZE		16
#define SM4_IV_LENGTH		(SM4_BLOCK_SIZE)
#define SM4_NUM_ROUNDS		32

#include <sys/types.h>
#include <stdint.h>
#include <string.h>
#include <openssl/modes.h>
#include "stdlib.h"
#include "stdio.h"

//#define SIMPLE_EXTERNAL_ENCODINGS

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sm4_key_t {
	uint32_t rk[SM4_NUM_ROUNDS];
#ifdef SIMPLE_EXTERNAL_ENCODINGS
    uint8_t G[SM4_NUM_ROUNDS+1][256];
    uint8_t F[SM4_NUM_ROUNDS+1][256];
#endif //SIMPLE_EXTERNAL_ENCODINGS
} sm4_key_t;

typedef struct sm4_key_t SM4_KEY;

/**
 sm4_set_encrypt_key

 @param key SM4_KEY
 @param user_key key
 */
void sm4_set_encrypt_key(sm4_key_t *key, const unsigned char *user_key);

/**
 sm4_set_decrypt_key

 @param key SM4_KEY
 @param user_key key
 */
void sm4_set_decrypt_key(sm4_key_t *key, const unsigned char *user_key);

/**
 sm4_encrypt

 @param in in
 @param out out
 @param key SM4_KEY
 */
void sm4_encrypt(const unsigned char *in, unsigned char *out, const sm4_key_t *key);
#define sm4_decrypt(in,out,key)  sm4_encrypt(in,out,key)

/**
 sm4_encrypt_init

 @param key SM4_KEY
 */
void sm4_encrypt_init(sm4_key_t *key);
void sm4_encrypt_8blocks(const unsigned char *in, unsigned char *out, const sm4_key_t *key);
void sm4_encrypt_16blocks(const unsigned char *in, unsigned char *out, const sm4_key_t *key);

/**
 sm4_ecb_encrypt

 @param in in
 @param out out
 @param key key
 @param enc 1 to SM4_ENCRYPT, 0 to SM4_DECRYPT
 */
void sm4_ecb_encrypt(const unsigned char *in, unsigned char *out,
	const sm4_key_t *key, int enc);

/**
 sm4_cbc_encrypt

 @param in in
 @param out out
 @param len byte size of in
 @param key key
 @param iv iv
 @param enc 1 to SM4_ENCRYPT, 0 to SM4_DECRYPT
 */
void sm4_cbc_encrypt(const unsigned char *in, unsigned char *out,
	size_t len, const sm4_key_t *key, unsigned char *iv, int enc);
void sm4_cfb128_encrypt(const unsigned char *in, unsigned char *out,
	size_t len, const sm4_key_t *key, unsigned char *iv, int *num, int enc);
void sm4_ofb128_encrypt(const unsigned char *in, unsigned char *out,
	size_t len, const sm4_key_t *key, unsigned char *iv, int *num);
/**
 sm4_ctr128_encrypt
 The input encrypted as though 128bit counter mode is being used.  The
 extra state information to record how much of the 128bit block we have
 used is contained in *num, and the encrypted counter is kept in
 ecount_buf.  Both *num and ecount_buf must be initialised with zeros
 before the first call to sm4_ctr128_encrypt(). This algorithm assumes
 that the counter is in the x lower bits of the IV (ivec), and that the
 application has full control over overflow and the rest of the IV.  This
 implementation takes NO responsibility for checking that the counter
 doesn't overflow into the rest of the IV when incremented.

 @param in in
 @param out out
 @param len byte size of in
 @param key key
 @param iv iv
 @param ecount_buf extra state, must be initialised with zeros before the first call
 @param num extra state, must be initialised with zeros before the first call
 */
void sm4_ctr128_encrypt(const unsigned char *in, unsigned char *out,
	size_t len, const sm4_key_t *key, unsigned char *iv,
	unsigned char ecount_buf[SM4_BLOCK_SIZE], unsigned int *num);

/**
 sm4_wrap_key

 @param key key
 @param iv iv
 @param out out
 @param in in
 @param inlen byte size of in
 @return 1 to successful, otherwise fault
 */
int sm4_wrap_key(sm4_key_t *key, const unsigned char *iv,
	unsigned char *out, const unsigned char *in, unsigned int inlen);
/**
 sm4_unwrap_key

 @param key key
 @param iv iv
 @param out out
 @param in in
 @param inlen byte size of in
 @return 1 to successful, otherwise fault
 */
int sm4_unwrap_key(sm4_key_t *key, const unsigned char *iv,
	unsigned char *out, const unsigned char *in, unsigned int inlen);

typedef GCM128_CONTEXT SM4_GCM128_CONTEXT;

/**
 sm4_gcm128_init

 @param ctx SM4_GCM128_CONTEXT
 @param key SM4_KEY
 */
void sm4_gcm128_init(SM4_GCM128_CONTEXT *ctx, SM4_KEY *key);

/**
 sm4_gcm128_setiv

 @param ctx SM4_GCM128_CONTEXT
 @param ivec iv
 @param len byte size of iv
 */
void sm4_gcm128_setiv(SM4_GCM128_CONTEXT *ctx, const unsigned char *ivec,
                      size_t len);

/**
 addition message of gcm

 @param ctx SM4_GCM128_CONTEXT
 @param aad addition message
 @param len byte size of aad
 @return 1 to successful, otherwises fault
 */
int sm4_gcm128_aad(SM4_GCM128_CONTEXT *ctx, const unsigned char *aad,
                    size_t len);

/**
 sm4_gcm128_encrypt

 @param in in
 @param out out
 @param length byte size of in
 @param ctx SM4_GCM128_CONTEXT
 @param enc 1 to SM4_ENCRYPT, 0 to SM4_DECRYPT
 @return 1 to successful, otherwises fault
 */
int sm4_gcm128_encrypt(const unsigned char *in, unsigned char *out,
                        size_t length, SM4_GCM128_CONTEXT *ctx, const int enc);

/**
 get tag of sm4_gcm128

 @param ctx SM4_GCM128_CONTEXT
 @param tag memory for storage tag
 @param len byte size of tag
 */
void sm4_gcm128_tag(SM4_GCM128_CONTEXT *ctx, unsigned char *tag,
                    size_t len);

/**
 sm4_gcm128_finish

 @param ctx SM4_GCM128_CONTEXT
 @param tag memory for storage tag
 @param len byte size of tag
 @return 1 to successful, otherwises fault
 */
int sm4_gcm128_finish(SM4_GCM128_CONTEXT *ctx, const unsigned char *tag,
                      size_t len);

/**
 release SM4_GCM128_CONTEXT

 @param ctx SM4_GCM128_CONTEXT
 */
void sm4_gcm128_release(SM4_GCM128_CONTEXT *ctx);

/*
void sm4_avx2_encrypt_init(sm4_key_t *key);
void sm4_avx2_encrypt_8blocks(const unsigned char *in, unsigned char *out, const sm4_key_t *key);
void sm4_avx2_encrypt_16blocks(const unsigned char *in, unsigned char *out, const sm4_key_t *key);

void sm4_knc_encrypt_init(sm4_key_t *key);
void sm4_knc_encrypt_8blocks(const unsigned char *in, unsigned char *out, const sm4_key_t *key);
void sm4_knc_encrypt_16blocks(const unsigned char *in, unsigned char *out, const sm4_key_t *key);

#define SM4_EDE_KEY_LENGTH	32

typedef struct {
	sm4_key_t k1;
	sm4_key_t k2;
} sm4_ede_key_t;

void sm4_ede_set_encrypt_key(sm4_ede_key_t *key, const unsigned char *user_key);
void sm4_ede_set_decrypt_key(sm4_ede_key_t *key, const unsigned char *user_key);
void sm4_ede_encrypt(sm4_ede_key_t *key, const unsigned char *in, unsigned char *out);
void sm4_ede_encrypt_8blocks(sm4_ede_key_t *key, const unsigned char *in, unsigned char *out);
void sm4_ede_encrypt_16blocks(sm4_ede_key_t *key, const unsigned char *in, unsigned char *out);
void sm4_ede_decrypt(sm4_ede_key_t *key, const unsigned char *in, unsigned char *out);
void sm4_ede_decrypt_8blocks(sm4_ede_key_t *key, const unsigned char *in, unsigned char *out);
void sm4_ede_decrypt_16blocks(sm4_ede_key_t *key, const unsigned char *in, unsigned char *out);
*/

/**
 * sm4 gcm file context
 */
typedef gcmf_context sm4_gcmf_context;

/**
 * init the sm4 gcm file context
 *
 * @param  ctx [in]		gcm file context
 *
 * @param  sm4_key [in]		sm4 key
 *
 * @return     [flag]		if successful o,otherwise failed
 */
int sm4_gcmf_init(sm4_gcmf_context *ctx, const SM4_KEY *sm4_key);

/**
 * gcm file context free
 *
 * @param  ctx [in]		gcm file context
 *
 * @return     [flag]		if successful o,otherwise failed
 */
int sm4_gcmf_free(sm4_gcmf_context *ctx);

/**
 * set sm4 iv param
 *
 * @param  ctx [in]		gcm file context
 *
 * @param  iv  [iv]		iv array
 *
 * @param  len [in]		iv array length
 *
 * @return     [flag]		if successful o,otherwise failed
 */
int sm4_gcmf_set_iv(sm4_gcmf_context *ctx, const unsigned char * iv, size_t len);


/**
 * encrypte file
 *
 * @param  ctx      [in]		gcm file context
 *
 * @param  infpath  [in]		plaintext file input path
 *
 * @param  outfpath [in]		cipher file output path
 *
 * @return          [fage]		if successful o,otherwise failed
 */
int sm4_gcmf_encrypt_file(sm4_gcmf_context * ctx, char *infpath, char *outfpath);


/**
 * decrypt file
 *
 * @param  ctx      [in]		gcm file context
 *
 * @param  infpath  [in]		cipher file input path
 *
 * @param  outfpath [in]		plaintext file output path
 *
 * @return          [flag]		if successful o,otherwise failed
 */
int sm4_gcmf_decrypt_file(sm4_gcmf_context * ctx, char *infpath, char *outfpath);

//same as fucntion rfc3686_init
//4Bytes nounce + 8bytes iv + 4bytes counter
void sm4_ctr128_ctr_init(unsigned char nonce[4], unsigned char iv[8], unsigned char ctr_buf[16]);

///* increment counter (128-bit int) by 1 */
void sm4_ctr128_ctr_inc(unsigned char *counter);

/* decrement counter (128-bit int) by 1 */
void sm4_ctr128_ctr_dec(unsigned char *counter);

void sm4_ctr128_subctr(unsigned char *counter, const unsigned char *in, unsigned char *out,
                        size_t length, const SM4_KEY *key);

#ifdef __cplusplus
}
#endif
#endif
#endif
