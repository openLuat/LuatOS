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
#include "sm4_lcl.h"

#ifdef DUMMY_ROUND
	#include <string.h>
	#include <stdbool.h>
	#include <AisinoSSL/internal/aisinossl_random.h>
#endif

#ifdef SIMPLE_EXTERNAL_ENCODINGS

#define APPLY_G_ROW( x, y, i) \
    y = (G[i][(x >> 24) & 0xff] << 24) ^ \
        (G[i][(x >> 16) & 0xff] << 16) ^ \
        (G[i][(x >>  8) & 0xff] <<  8) ^ \
        (G[i][(x      ) & 0xff]      );   \
    x = y;

 #define APPLY_F_ROW( x, y, i) \
    y = (F[i][(x >> 24) & 0xff] << 24) ^ \
        (F[i][(x >> 16) & 0xff] << 16) ^ \
        (F[i][(x >>  8) & 0xff] <<  8) ^ \
        (F[i][(x      ) & 0xff]      );   \
    x = y;

 #define SIMPLE_EXTERNAL_ENCODINGS_G(x, y, i) \
    APPLY_G_ROW(x, y, i)

 #define SIMPLE_EXTERNAL_ENCODINGS_F(x, y, i) \
    APPLY_F_ROW(x, y, i)
    
#endif //SIMPLE_EXTERNAL_ENCODINGS

#define L32(x)						\
	((x) ^						\
	ROT32((x),  2) ^				\
	ROT32((x), 10) ^				\
	ROT32((x), 18) ^				\
	ROT32((x), 24))

#define ROUND(x0, x1, x2, x3, x4, i)			\
	x4 = x1 ^ x2 ^ x3 ^ *(rk + i);			\
	x4 = S32(x4);					\
	x4 = x0 ^ L32(x4)

void sm4_encrypt(const unsigned char *in, unsigned char *out, const sm4_key_t *key)
{
	const uint32_t *rk = key->rk;
	uint32_t x0, x1, x2, x3, x4;

	x0 = GET32(in     );
	x1 = GET32(in +  4);
	x2 = GET32(in +  8);
	x3 = GET32(in + 12);

#ifdef DUMMY_ROUND
	int r = 1;
    uint32_t s[2][5];

 	// 0xf31a34ed, 0xb7b4cc7c, 0xfba9f4bf, 0x5e89d810, 0xf31a34ed, 0xb7b4cc7c, 0xfba9f4bf, 0x5e89d810,
	// xor                                 0x1294e0d3, 0x563a1842, 0x1a272081, 0xbf070c2e
	// k0                                  0x63e591a2, 0x274b6933, 0x6b5651f0, 0xce767d5f
	// final 0x71717171
    // sbox[0x71] = 0
    const uint32_t beta[4] = {0xf31a34ed, 0xb7b4cc7c, 0xfba9f4bf, 0x5e89d810};
    const uint32_t k0[4] = {0x63e591a2, 0x274b6933, 0x6b5651f0, 0xce767d5f};

    memcpy(s[1], beta, 4*sizeof(uint32_t));

    uint32_t dummyKey[SM4_NUM_ROUNDS+4];
    memcpy(dummyKey+4, key->rk, SM4_NUM_ROUNDS*sizeof(uint32_t));
    memcpy(dummyKey, k0, 4*sizeof(uint32_t));

    s[0][0] = x0;
    s[0][1] = x1;
    s[0][2] = x2;
    s[0][3] = x3;

    rk = dummyKey;
    int sm4_rounds = SM4_NUM_ROUNDS/4;

    enum _CONST_INT{
        E_RANDOM_NUMS = 100
    };
    
    int random_list[E_RANDOM_NUMS];
    
    int rcnt = E_RANDOM_NUMS;

    while(r <= sm4_rounds ) {

        if (rcnt >= E_RANDOM_NUMS)  {
            aisinossl_random_list(NULL, random_list, E_RANDOM_NUMS);
            rcnt = 0;
        }   
        bool lambda  = ((random_list[rcnt++] %2)==1);  


        int kai = lambda*r;
        int tlambda = !lambda;  //turn lambda
        ROUND(s[tlambda][0], s[tlambda][1], s[tlambda][2], s[tlambda][3], s[tlambda][4], 4*kai + 0);
        ROUND(s[tlambda][1], s[tlambda][2], s[tlambda][3], s[tlambda][4], s[tlambda][0], 4*kai + 1);
        ROUND(s[tlambda][2], s[tlambda][3], s[tlambda][4], s[tlambda][0], s[tlambda][1], 4*kai + 2);
        ROUND(s[tlambda][3], s[tlambda][4], s[tlambda][0], s[tlambda][1], s[tlambda][2], 4*kai + 3);

        s[tlambda][3] = s[tlambda][2];
        s[tlambda][2] = s[tlambda][1];
        s[tlambda][1] = s[tlambda][0];
        s[tlambda][0] = s[tlambda][4];

        s[0][0] = s[0][0] ^ s[1][0] ^ beta[0];
        s[0][1] = s[0][1] ^ s[1][1] ^ beta[1];
        s[0][2] = s[0][2] ^ s[1][2] ^ beta[2];
        s[0][3] = s[0][3] ^ s[1][3] ^ beta[3];

        r = r + lambda;
    }
    x0 = s[0][3];
    x4 = s[0][2];
    x3 = s[0][1];
    x2 = s[0][0];

#else
    ROUNDS(x0, x1, x2, x3, x4);
#endif

	PUT32(x0, out     );
	PUT32(x4, out +  4);
	PUT32(x3, out +  8);
	PUT32(x2, out + 12);

	x0 = x1 = x2 = x3 = x4 = 0;
}
