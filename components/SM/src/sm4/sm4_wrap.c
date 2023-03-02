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

#include <sm4/sm4.h>
#include <openssl/modes.h>

/** Wrapping according to RFC 3394 section 2.2.1.
 *
 *  @param[in]  key    Key value.
 *  @param[in]  iv     IV value. Length = 8 bytes. NULL = use default_iv.
 *  @param[in]  in     Plaintext as n 64-bit blocks, n >= 2.
 *  @param[in]  inlen  Length of in.
 *  @param[out] out    Ciphertext. Minimal buffer length = (inlen + 8) bytes.
 *                     Input and output buffers can overlap if block function
 *                     supports that.
 *  @return            0 if inlen does not consist of n 64-bit blocks, n >= 2.
 *                     or if inlen > CRYPTO128_WRAP_MAX.
 *                     Output length if wrapping succeeded.
 */
int sm4_wrap_key(sm4_key_t *key, const unsigned char *iv,
	unsigned char *out, const unsigned char *in, unsigned int inlen)
{
	return CRYPTO_128_wrap(key, iv, out, in, inlen, (block128_f)sm4_encrypt);
}

/** Unwrapping according to RFC 3394 section 2.2.2 steps 1-2.
 *  The IV check (step 3) is responsibility of the caller.
 *
 *  @param[in]  key    Key value.
 *  @param[out] iv     Unchecked IV value. Minimal buffer length = 8 bytes.
 *  @param[out] out    Plaintext without IV.
 *                     Minimal buffer length = (inlen - 8) bytes.
 *                     Input and output buffers can overlap if block function
 *                     supports that.
 *  @param[in]  in     Ciphertext as n 64-bit blocks.
 *  @param[in]  inlen  Length of in.
 *  @return            0 if inlen is out of range [24, CRYPTO128_WRAP_MAX]
 *                     or if inlen is not a multiple of 8.
 *                     Output length otherwise.
 */
int sm4_unwrap_key(sm4_key_t *key, const unsigned char *iv,
	unsigned char *out, const unsigned char *in, unsigned int inlen)
{
	return CRYPTO_128_unwrap(key, iv, out, in, inlen, (block128_f)sm4_encrypt);
}
