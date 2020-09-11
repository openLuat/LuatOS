/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: brezen
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.12.24  brezen     创建文件
*********************************************************/
#ifndef OPENAT_SSLRSA_H
#define OPENAT_SSLRSA_H


#define THIRTY_TWO_BIT

#if defined (OPENSSL_SYS_VMS)
#undef BN_LLONG /* experimental, so far... */
#endif

#define OPENAT_BN_MUL_COMBA
#define OPENAT_BN_SQR_COMBA
#define OPENAT_BN_RECURSION

/* This next option uses the C libraries (2 word)/(1 word) function.
 * If it is not defined, I use my C version (which is slower).
 * The reason for this flag is that when the particular C compiler
 * library routine is used, and the library is linked with a different
 * compiler, the library is missing.  This mostly happens when the
 * library is built with gcc and then linked using normal cc.  This would
 * be a common occurrence because gcc normally produces code that is
 * 2 times faster than system compilers for the big number stuff.
 * For machines with only one compiler (or shared libraries), this should
 * be on.  Again this in only really a problem on machines
 * using "long long's", are 32bit, and are not using my assembler code. */
#if defined(OPENSSL_SYS_MSDOS) || defined(OPENSSL_SYS_WINDOWS) || \
    defined(OPENSSL_SYS_WIN32) || defined(linux)
# if !defined (BN_DIV2W)
#  define OPENAT_BN_DIV2W
# endif
#endif




#if defined (THIRTY_TWO_BIT)
#if defined(OPENSSL_SYS_WIN32) && !defined(__GNUC__)
#define OPENAT_BN_ULLONG	unsigned _int64
#else
#define OPENAT_BN_ULLONG	unsigned long long
#endif
#define OPENAT_BN_ULONG	unsigned long
#define OPENAT_BN_LONG		long
#define OPENAT_BN_BITS		64
#define OPENAT_BN_BYTES	4
#define OPENAT_BN_BITS2	32
#define OPENAT_BN_BITS4	16
#if defined (OPENSSL_SYS_WIN32)
/* VC++ doesn't like the LL suffix */
#define OPENAT_BN_MASK		(0xffffffffffffffffL)
#else
#define OPENAT_BN_MASK		(0xffffffffffffffffLL)
#endif
#define OPENAT_BN_MASK2	(0xffffffffL)
#define OPENAT_BN_MASK2l	(0xffff)
#define OPENAT_BN_MASK2h1	(0xffff8000L)
#define OPENAT_BN_MASK2h	(0xffff0000L)
#define OPENAT_BN_TBIT		(0x80000000L)
#define OPENAT_BN_DEC_CONV	(1000000000L)
#define OPENAT_BN_DEC_FMT1	"%lu"
#define OPENAT_BN_DEC_FMT2	"%09lu"
#define OPENAT_BN_DEC_NUM	9
#endif


#define OPENAT_BN_DEFAULT_BITS	1280

#if defined (OPENAT_BIGNUM)
#undef OPENAT_BIGNUM
#endif

#define OPENAT_BN_FLG_MALLOCED		0x01
#define OPENAT_BN_FLG_STATIC_DATA	0x02
#define OPENAT_BN_FLG_FREE		0x8000	/* used for debuging */
#define OPENAT_BN_set_flags(b,n)	((b)->flags|=(n))
#define OPENAT_BN_get_flags(b,n)	((b)->flags&(n))

typedef struct OPENAT_bignum_st
	{
	OPENAT_BN_ULONG *d;	/* Pointer to an array of 'BN_BITS2' bit chunks. */
	int top;	/* Index of last used d +1. */
	/* The next are internal book keeping for bn_expand. */
	int dmax;	/* Size of the d array. */
	int neg;	/* one if the number is negative */
	int flags;
	} OPENAT_BIGNUM;

/* Used for temp variables (declaration hidden in bn_lcl.h) */
typedef struct bignum_ctx OPENAT_BN_CTX;

typedef struct OPENAT_bn_blinding_st
	{
	int init;
	OPENAT_BIGNUM *A;
	OPENAT_BIGNUM *Ai;
	OPENAT_BIGNUM *mod; /* just a reference */
	} OPENAT_BN_BLINDING;

/* Used for montgomery multiplication */
typedef struct OPENAT_bn_mont_ctx_st
	{
	int ri;        /* number of bits in R */
	OPENAT_BIGNUM RR;     /* used to convert to montgomery form */
	OPENAT_BIGNUM N;      /* The modulus */
	OPENAT_BIGNUM Ni;     /* R*(1/R mod N) - N*Ni = 1
	                * (Ni is only stored for bignum algorithm) */
	OPENAT_BN_ULONG n0;   /* least significant word of Ni */
	int flags;
	} OPENAT_BN_MONT_CTX;

/* Used for reciprocal division/mod functions
 * It cannot be shared between threads
 */
typedef struct OPENAT_bn_recp_ctx_st
	{
	OPENAT_BIGNUM N;	/* the divisor */
	OPENAT_BIGNUM Nr;	/* the reciprocal */
	int num_bits;
	int shift;
	int flags;
	} OPENAT_BN_RECP_CTX;


OPENAT_BIGNUM* OPENAT_SSL_bn_new(void);

OPENAT_BN_CTX* OPENAT_SSL_bn_CTX_new(void);

OPENAT_BIGNUM* OPENAT_SSL_bn_bin2bn(const unsigned char *s,
                                        int len,
                                        OPENAT_BIGNUM *ret
                                        );

int OPENAT_SSL_bn_bn2bin(const OPENAT_BIGNUM *a, 
                                   unsigned char *to);

int OPENAT_SSL_bn_mod_exp_mont(OPENAT_BIGNUM *rr,
                                            const OPENAT_BIGNUM *a, 
                                            const OPENAT_BIGNUM *p,
                                            const OPENAT_BIGNUM *m, 
                                            OPENAT_BN_CTX *ctx, 
                                            OPENAT_BN_MONT_CTX *in_mont
                                            );

int OPENAT_SSL_bn_mod_exp(OPENAT_BIGNUM *r,
                                        const OPENAT_BIGNUM *a, 
                                        const OPENAT_BIGNUM *p, 
                                        const OPENAT_BIGNUM *m,
                                        OPENAT_BN_CTX *ctx
                                        );

void OPENAT_SSL_bn_free(OPENAT_BIGNUM *a);

void OPENAT_SSL_bn_CTX_free(OPENAT_BN_CTX *ctx);

int OPENAT_SSL_bn_hex2bn(OPENAT_BIGNUM **bn, 
                                     const char *a
                                     );

#endif /* OPENAT_SSLRSA_H */

