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
	#include <internal/ssl_random.h>
#endif

#ifdef SIMPLE_EXTERNAL_ENCODINGS
    #include <internal/ssl_random.h>
#endif //SIMPLE_EXTERNAL_ENCODINGS

static uint32_t FK[4] = {
	0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc,
};

static uint32_t CK[32] = {
	0x00070e15, 0x1c232a31, 0x383f464d, 0x545b6269,
	0x70777e85, 0x8c939aa1, 0xa8afb6bd, 0xc4cbd2d9,
	0xe0e7eef5, 0xfc030a11, 0x181f262d, 0x343b4249,
	0x50575e65, 0x6c737a81, 0x888f969d, 0xa4abb2b9,
	0xc0c7ced5, 0xdce3eaf1, 0xf8ff060d, 0x141b2229,
	0x30373e45, 0x4c535a61, 0x686f767d, 0x848b9299,
	0xa0a7aeb5, 0xbcc3cad1, 0xd8dfe6ed, 0xf4fb0209,
	0x10171e25, 0x2c333a41, 0x484f565d, 0x646b7279,
};

#define L32_(x)					\
	((x) ^ 					\
	ROT32((x), 13) ^			\
	ROT32((x), 23))

#define ENC_ROUND(x0, x1, x2, x3, x4, i)	\
	x4 = x1 ^ x2 ^ x3 ^ *(CK + i);		\
	x4 = S32(x4);				\
	x4 = x0 ^ L32_(x4);			\
	*(rk + i) = x4

#define DEC_ROUND(x0, x1, x2, x3, x4, i)	\
	x4 = x1 ^ x2 ^ x3 ^ *(CK + i);		\
	x4 = S32(x4);				\
	x4 = x0 ^ L32_(x4);			\
	*(rk + 31 - i) = x4

#ifdef DUMMY_ROUND
#define ENC_DUMMY_ROUND(x0, x1, x2, x3, x4, i)	\
	x4 = x1 ^ x2 ^ x3 ^ *(dummyKey + i);		\
	x4 = S32(x4);				\
	x4 = x0 ^ L32_(x4);
#endif

void sm4_set_encrypt_key(sm4_key_t *key, const unsigned char *user_key)
{

	uint32_t *rk = key->rk;
	uint32_t x0, x1, x2, x3, x4;
    int _i;
    u8 et[256];

	x0 = GET32(user_key     ) ^ FK[0];
	x1 = GET32(user_key  + 4) ^ FK[1];
	x2 = GET32(user_key  + 8) ^ FK[2];
	x3 = GET32(user_key + 12) ^ FK[3];

#ifdef SIMPLE_EXTERNAL_ENCODINGS
    
    for (_i = 0; _i < 256; _i++) {
        key->G[1][_i] = key->F[SM4_NUM_ROUNDS][_i] = et[_i] = _i;
        key->F[0][_i] = _i;
    }
    
    for (_i = 1; _i < SM4_NUM_ROUNDS; _i++) {
        int _j;
        ssl_random_shuffle_u8(et, 256);
        memcpy(key->F[_i], et, 256);
        for (_j = 0; _j < 256; _j++) {
            key->G[_i+1][ key->F[_i][_j] ] = _j;
        }
    }
#endif //SIMPLE_EXTERNAL_ENCODINGS


#ifndef DUMMY_ROUND
    
    #define ROUND ENC_ROUND
	ROUNDS(x0, x1, x2, x3, x4);

	x0 = x1 = x2 = x3 = x4 = 0;
#else 

#define ROUND ENC_DUMMY_ROUND
	int r = 1;
    uint32_t s[2][5];

 	// 0xf31a34ed, 0xb7b4cc7c, 0xfba9f4bf, 0x5e89d810, 0xf31a34ed, 0xb7b4cc7c, 0xfba9f4bf, 0x5e89d810,
	// xor                                 0x1294e0d3, 0x563a1842, 0x1a272081, 0xbf070c2e
	// k0                                  0x63e591a2, 0x274b6933, 0x6b5651f0, 0xce767d5f
	// final 0x71717171
    const uint32_t beta[4] = {0xf31a34ed, 0xb7b4cc7c, 0xfba9f4bf, 0x5e89d810};
    const uint32_t k0[4] = {0x63e591a2, 0x274b6933, 0x6b5651f0, 0xce767d5f};

    memcpy(s[1], beta, 4*sizeof(uint32_t));

    uint32_t dummyKey[SM4_NUM_ROUNDS+4];

    memcpy(dummyKey+4, CK, SM4_NUM_ROUNDS*sizeof(uint32_t));
    memcpy(dummyKey, k0, 4*sizeof(uint32_t));

    s[0][0] = x0;
    s[0][1] = x1;
    s[0][2] = x2;
    s[0][3] = x3;

    int sm4_rounds = SM4_NUM_ROUNDS/4;


	enum _CONST_INT{
        E_RANDOM_NUMS = 100
    };
    
    int random_list[E_RANDOM_NUMS];
    
    int rcnt = E_RANDOM_NUMS;

    while(r <= sm4_rounds ) {

        if (rcnt >= E_RANDOM_NUMS)  {
            l_random_list(NULL, random_list, E_RANDOM_NUMS);
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

        rk[4*r - 4] = s[0][0] = s[0][0] ^ s[1][0] ^ beta[0];
        rk[4*r - 3] = s[0][1] = s[0][1] ^ s[1][1] ^ beta[1];
        rk[4*r - 2] = s[0][2] = s[0][2] ^ s[1][2] ^ beta[2];
        rk[4*r - 1] = s[0][3] = s[0][3] ^ s[1][3] ^ beta[3];

        r = r + lambda;
    }
#endif   // end of DUMMY_ROUND
}

void sm4_set_decrypt_key(sm4_key_t *key, const unsigned char *user_key)
{
	uint32_t *rk = key->rk;
	uint32_t x0, x1, x2, x3, x4;

	x0 = GET32(user_key     ) ^ FK[0];
	x1 = GET32(user_key  + 4) ^ FK[1];
	x2 = GET32(user_key  + 8) ^ FK[2];
	x3 = GET32(user_key + 12) ^ FK[3];

#undef ROUND
#define ROUND DEC_ROUND
	ROUNDS(x0, x1, x2, x3, x4);

	x0 = x1 = x2 = x3 = x4 = 0;
}
