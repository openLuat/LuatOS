//
// Created by  lzj on 2017/8/15.
//

#include <sm2/sm2.h>
#include <mbedtls/hmac_drbg.h>
#include <mbedtls/ecp.h>
#include <sm3/sm3.h>
#include <mbedtls/bignum.h>

#include <string.h>
#include <time.h>
#include <stdint.h>

#define HEX_CODE 16
#define SM3_LEN 32

#if defined(MBEDTLS_PLATFORM_C)
#include <mbedtls/platform.h>
#else
#include <stdlib.h>
#define mbedtls_calloc calloc
#define mbedtls_free free
#endif

#if defined(MBEDTLS_SELF_TEST)

#ifdef ANDROID_LOG

#include <android/log.h>
#include <string.h>
#include <malloc.h>
#include <stdlib.h>
#include <time.h>

#define mbedtls_printf(...) __android_log_print(ANDROID_LOG_DEBUG, "SECURITY_LIBRARY", __VA_ARGS__)

#else
#define mbedtls_printf printf
#endif // android log

#endif // test end

/**
 * init context and
 * set default group
 * @param ctx
 */
int sm2_init(sm2_context *ctx)
{
	memset(ctx, 0, sizeof(sm2_context));
	mbedtls_ecp_point_init(&ctx->Pb);
	mbedtls_mpi_init(&ctx->d);
	return mbedtls_ecp_group_load(&(ctx->grp), ECP_DP_SM2_256V1);
}

/**
 *  free  context
 * @param ctx
 */
void sm2_free(sm2_context *ctx)
{
	if (ctx == NULL)
	{
		return;
	}

	mbedtls_ecp_group_free(&ctx->grp);
	mbedtls_ecp_point_free(&ctx->Pb);
	mbedtls_mpi_free(&ctx->d);
}

/**
 * set private key by hex buf
 * @param ctx
 * @param buf
 * @return
 */
int sm2_read_string_private(sm2_context *ctx, const char *buf)
{
	return mbedtls_mpi_read_string(&(ctx->d), HEX_CODE, buf);
}

/**
 *   set public key
 * @param ctx
 * @param x
 * @param y
 * @return
 */
int sm2_read_string_public(sm2_context *ctx, const char *x, const char *y)
{
	return mbedtls_ecp_point_read_string(&(ctx->Pb), HEX_CODE, x, y);
}

/**
 *   generate key
 * @param ctx
 * @param f_rng
 * @param p_rng
 * @return
 */
int sm2_gen_keypair(sm2_context *ctx,
					int (*f_rng)(void *, unsigned char *, size_t), void *p_rng)
{
	return mbedtls_ecp_gen_keypair(&(ctx->grp), &(ctx->d), &(ctx->Pb), f_rng,
								   p_rng);
}

/**
 *  check private key int the group
 * @param ctx
 * @return
 */
int sm2_check_private(sm2_context *ctx)
{
	return mbedtls_ecp_check_privkey(&(ctx->grp), &(ctx->d));
}

/**
 * check public key int group
 * @param ctx
 * @return
 */
int sm2_check_public(sm2_context *ctx)
{
	return mbedtls_ecp_check_pubkey(&(ctx->grp), &(ctx->Pb));
}

/**
 *set sm2 group by hex string param
 */
int sm2_read_group_string(sm2_context *ctx, const char *p, const char *a,
						  const char *b, const char *gx, const char *gy, const char *n)
{
	int ret;
	static mbedtls_mpi_uint one[] = {1};
	mbedtls_ecp_group_free(&ctx->grp);
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_string(&(ctx->grp.P), HEX_CODE, p));
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_string(&(ctx->grp.A), HEX_CODE, a));
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_string(&(ctx->grp.B), HEX_CODE, b));
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_string(&(ctx->grp.G.X), HEX_CODE, gx));
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_string(&(ctx->grp.G.Y), HEX_CODE, gy));
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_string(&(ctx->grp.N), HEX_CODE, n));

	ctx->grp.G.Z.s = 1;
	ctx->grp.G.Z.n = 1;
	ctx->grp.G.Z.p = one;
	ctx->grp.pbits = mbedtls_mpi_bitlen(&(ctx->grp.P));
	ctx->grp.nbits = mbedtls_mpi_bitlen(&(ctx->grp.N));
	ctx->grp.h = 1;
cleanup:
	return ret;
}

/**
 *  sm2 contest copy
 */
int sm2_copy(sm2_context *dst, const sm2_context *src)
{

	int ret;
	MBEDTLS_MPI_CHK(mbedtls_ecp_group_copy(&dst->grp, &src->grp));
	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&dst->d, &src->d));
	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&dst->Pb.X, &src->Pb.X));
	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&dst->Pb.Y, &src->Pb.Y));
	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&dst->Pb.Z, &src->Pb.Z));
cleanup:

	return (ret);
}

#define int_to_byte_4(b, i, u)      \
	b[i] = (unsigned char)(u >> 8); \
	b[i + 1] = (unsigned char)(u)

#define int_to_byte_8(b, i, u)           \
	b[i] = (unsigned char)(u >> 24);     \
	b[i + 1] = (unsigned char)(u >> 16); \
	b[i + 2] = (unsigned char)(u >> 8);  \
	b[i + 3] = (unsigned char)(u)

static int kdf(unsigned char *out, const unsigned char *buf, size_t buf_len,
			   size_t klen)
{
	const int CT_LEN = sizeof(size_t);
	const size_t counts = klen / SM3_LEN;
	const size_t mod = klen % SM3_LEN;

	size_t tmp_len = buf_len + CT_LEN;
	size_t ct;
	//buf len  + ct len ()
	unsigned char *buf_z_ct = mbedtls_calloc(tmp_len, sizeof(unsigned char));
	unsigned char *temp_out = mbedtls_calloc(SM3_LEN, sizeof(unsigned char));

	if (buf_z_ct == NULL || temp_out == NULL)
	{
		return MBEDTLS_ERR_SM2_ALLOC_FAILED;
	}
	for (ct = 1; ct <= counts + 1; ct++)
	{
		memset(buf_z_ct, 0, tmp_len);
		memcpy(buf_z_ct, buf, buf_len);
		int_to_byte_8(buf_z_ct, buf_len, ct);
		if (ct <= counts)
		{
			sm3(buf_z_ct, tmp_len, out + (ct - 1) * SM3_LEN);
		}
		else
		{
			memset(temp_out, 0, SM3_LEN);
			sm3(buf_z_ct, tmp_len, temp_out);
			memcpy(out + (ct - 1) * SM3_LEN, temp_out, mod);
		}
	}
	mbedtls_free(buf_z_ct);
	mbedtls_free(temp_out);
	return 0;
}

/*byte =  x2 || y2*/
static int x_y2byte(mbedtls_mpi *x, mbedtls_mpi *y, mbedtls_ecp_group *group,
					unsigned char *byte, size_t *blen)
{
	int ret;
	size_t tmp_len;
	/*byte =  x2 || y2*/
	memset(byte, 0, *blen);
	tmp_len = mbedtls_mpi_size(&group->P);
	// temp += x2
	MBEDTLS_MPI_CHK(mbedtls_mpi_write_binary(x, byte, tmp_len));
	// temp += y2
	MBEDTLS_MPI_CHK(mbedtls_mpi_write_binary(y, byte + tmp_len, tmp_len));

cleanup:
	*blen = tmp_len * 2;

	return (ret);
}

/*byte =  x2 || y2*/
static int point2byte(mbedtls_ecp_point *point, mbedtls_ecp_group *group,
					  unsigned char *byte, size_t *blen)
{
	return x_y2byte(&point->X, &point->Y, group, byte, blen);
}

/*byte = x2 || m || y2*/
static int byte_cat(mbedtls_ecp_point *point, const unsigned char *m,
					size_t mlen, mbedtls_ecp_group *group, unsigned char *byte,
					size_t *blen)
{
	int ret;
	size_t p_len;
	/*byte = x2 || m || y2*/
	memset(byte, 0, *blen);
	p_len = mbedtls_mpi_size(&(group->P));
	// byte += x2
	MBEDTLS_MPI_CHK(mbedtls_mpi_write_binary(&point->X, byte, p_len));
	//byte += m
	memcpy(byte + p_len, m, mlen);
	// byte += y2
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&point->Y, byte + p_len + mlen, p_len));

cleanup:
	*blen = p_len * 2 + mlen;

	return (ret);
}

/**
 * sm2 encrypt
 *
 */
int sm2_do_encrypt(sm2_context *ctx, const unsigned char *buffer,
				   size_t plen, unsigned char *out, size_t max_out_len, size_t *olen,
				   int (*f_rng)(void *, unsigned char *, size_t), void *p_rng)
{
	int ret;
	size_t max_len, c1_len, c2_len, c3_len, temp_len;
	unsigned char *c1_buf, *c2_buf, *c3_buf, *temp;
	int i;
	mbedtls_mpi k;
	mbedtls_ecp_point KG;
	mbedtls_ecp_point KPb;

	if (ctx == NULL || buffer == NULL)
	{
		return MBEDTLS_ERR_SM2_BAD_INPUT_DATA;
	}

	max_len = plen + 64 * 2 + 1;

	c1_len = 100;
	c1_buf = mbedtls_calloc(c1_len, sizeof(unsigned char));

	c2_len = plen + 1;
	c2_buf = mbedtls_calloc(c2_len, sizeof(unsigned char));

	c3_len = SM3_LEN;
	c3_buf = mbedtls_calloc(c3_len, sizeof(unsigned char));

	temp_len = max_len;
	temp = mbedtls_calloc(temp_len, sizeof(unsigned char));

	if (c1_buf == NULL || c2_buf == NULL || c3_buf == NULL || temp == NULL)
	{
		return MBEDTLS_ERR_MPI_ALLOC_FAILED;
	}

	mbedtls_mpi_init(&k);
	mbedtls_ecp_point_init(&KG);
	mbedtls_ecp_point_init(&KPb);

	do
	{
		size_t n_size, tmp_len;
		int iter;
		/* generate rand k  from range n */
		/* rand k in [1, n-1] */
		n_size = (ctx->grp.nbits + 7) / 8;
		MBEDTLS_MPI_CHK(mbedtls_mpi_fill_random(&k, n_size, f_rng, p_rng));
		MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&k, &k, &ctx->grp.N));
		// MBEDTLS_MPI_CHK(rand(&k, &(ctx->grp.N)));

		/* compute ephem_point [k]G = (x1, y1)   to KG */
		MBEDTLS_MPI_CHK(
			mbedtls_ecp_mul(&(ctx->grp), &KG, &k, &(ctx->grp.G), NULL, NULL));
		tmp_len = 0;
		memset(c1_buf, 0, c1_len);
		MBEDTLS_MPI_CHK(
			mbedtls_ecp_point_write_binary(&(ctx->grp), &KG, MBEDTLS_ECP_PF_UNCOMPRESSED, &tmp_len, c1_buf, c1_len));
		c1_len = tmp_len;
		tmp_len = 0;

		/* compute [k]PukeyB = [k](XB,YB) = (x2,y2)*/
		MBEDTLS_MPI_CHK(
			mbedtls_ecp_mul(&(ctx->grp), &KPb, &k, &(ctx->Pb), NULL, NULL));

		/*temp =  x2 || y2*/
		MBEDTLS_MPI_CHK(point2byte(&KPb, &(ctx->grp), temp, &temp_len));

		/* compute t = KDF(x2 || y2, klen) */
		MBEDTLS_MPI_CHK(kdf(c2_buf, temp, temp_len, plen));
		temp_len = max_len;

		// check :if(t == 0) -> return to 1st step

		for (iter = 0; iter < (int)plen; iter++)
		{
			if (c2_buf[iter] != 0)
				break;
		}
		if ((int)plen != iter)
			break;

	} while (1);

	/* cipher_text = t xor M */

	for (i = 0; i < (int)plen; i++)
	{
		c2_buf[i] ^= buffer[i];
	}
	c2_len = plen;

	/*compute C3 = HASH(x2|| M || y2)*/
	/*temp buf = x2 || m || y2*/
	MBEDTLS_MPI_CHK(byte_cat(&KPb, buffer, plen, &(ctx->grp), temp, &temp_len));

	//sm3 temp
	sm3(temp, temp_len, c3_buf);

	if (max_out_len < c1_len + c2_len + c3_len || NULL == out)
	{
		ret = MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE;
		goto cleanup;
	}

	memset(out, 0, max_out_len);
	memcpy(out, c1_buf, c1_len);
	memcpy(out + c1_len, c2_buf, c2_len);
	memcpy(out + c1_len + c2_len, c3_buf, c3_len);

cleanup:
	*olen = c1_len + c2_len + c3_len;

	mbedtls_mpi_free(&k);
	mbedtls_ecp_point_free(&KG);
	mbedtls_ecp_point_free(&KPb);
	mbedtls_free(temp);
	mbedtls_free(c1_buf);
	mbedtls_free(c2_buf);
	mbedtls_free(c3_buf);

	return (ret);
}

/**
 * sm2 decrypt
 *
 */
int sm2_do_decrypt(sm2_context *ctx, const unsigned char *cipher, size_t clen,
				   unsigned char *out, size_t max_out_len, size_t *olen)
{
	int ret;
	size_t i;
	size_t temp_len, c1_len, c3_len, c2_len;
	unsigned char *temp, *c1_buf, *c3_buf, *c2_buf;
	mbedtls_ecp_point P_1;
	mbedtls_ecp_point P_2;

	//presume the input data : [C1(65 Byte)][C2(unknown length)][C3(32 Byte)]
	if (NULL == cipher || 98 > clen)
	{
		return -MBEDTLS_ERR_SM2_BAD_INPUT_DATA;
	}

	temp_len = clen;
	temp = mbedtls_calloc(temp_len, sizeof(unsigned char));
	c1_len = 65;
	c1_buf = mbedtls_calloc(c1_len, sizeof(unsigned char));
	c3_len = SM3_LEN;
	c3_buf = mbedtls_calloc(c3_len, sizeof(unsigned char));
	c2_len = clen - c1_len - c3_len;
	c2_buf = mbedtls_calloc(c2_len, sizeof(unsigned char));

	if (temp == NULL || c1_buf == NULL || c3_buf == NULL || c2_buf == NULL)
	{
		return MBEDTLS_ERR_SM2_ALLOC_FAILED;
	}

	mbedtls_ecp_point_init(&P_2);
	mbedtls_ecp_point_init(&P_1);

	memcpy(c1_buf, cipher, c1_len);

	/*get c1 point x1,y1  to P_1*/
	MBEDTLS_MPI_CHK(
		mbedtls_ecp_point_read_binary(&(ctx->grp), &P_1, c1_buf, c1_len));

	/* check c1 */
	MBEDTLS_MPI_CHK(mbedtls_ecp_check_pubkey(&(ctx->grp), &P_1));

	/* P_2 = dA*C1 = (x2,y2) */
	MBEDTLS_MPI_CHK(
		mbedtls_ecp_mul(&(ctx->grp), &P_2, &(ctx->d), &P_1, NULL, NULL));

	/* t= KDF(x2||y2, klen)*/
	/*temp =  x2 || y2 */
	MBEDTLS_MPI_CHK(point2byte(&P_2, &(ctx->grp), temp, &temp_len));

	/* compute t = KDF(x2 || y2, klen) */
	MBEDTLS_MPI_CHK(kdf(c2_buf, temp, temp_len, c2_len));

	/*check  t !=0;*/

	for (i = 0; i < c2_len; i++)
	{
		if (c2_buf[i] != 0)
			break;
	}
	if (c2_len == i)
	{
		ret = MBEDTLS_ERR_SM2_BAD_INPUT_DATA;
		goto cleanup;
	}

	/* m` = t xor c2 */
	for (i = 0; i < c2_len; i++)
	{
		c2_buf[i] ^= cipher[c1_len + i];
	}

	/*compute u = HASH(x2|| M` || y2)*/
	/*temp buf = x2 || m` || y2*/
	MBEDTLS_MPI_CHK(
		byte_cat(&P_2, c2_buf, c2_len, &(ctx->grp), temp, &temp_len));

	sm3(temp, temp_len, c3_buf);

	for (i = 0; i < c3_len; i++)
	{
		if (c3_buf[i] != (cipher + c1_len + c2_len)[i])
		{
			ret = MBEDTLS_ERR_SM2_PRIVATE_FAILED;
			goto cleanup;
		}
	}

	if (max_out_len < c2_len || NULL == out)
	{
		ret = MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE;
		goto cleanup;
	}

	memset(out, 0, max_out_len);
	memcpy(out, c2_buf, c2_len);

cleanup:
	*olen = c2_len;

	mbedtls_ecp_point_free(&P_1);
	mbedtls_ecp_point_free(&P_2);
	mbedtls_free(c1_buf);
	mbedtls_free(c2_buf);
	mbedtls_free(c3_buf);

	return (ret);
}

/**
 *
 * sm2 sign byte e
 */
int sm2_do_sign(sm2_context *ctx, const unsigned char *dgst, size_t dgstlen,
				unsigned char *out, size_t max_out_len, size_t *olen,
				int (*f_rng)(void *, unsigned char *, size_t), void *p_rng)
{
	int ret;
	mbedtls_mpi e;
	mbedtls_mpi k;
	mbedtls_mpi r;
	mbedtls_mpi s;
	mbedtls_mpi tmp;
	mbedtls_mpi tmp_2;

	mbedtls_ecp_point KG;

	mbedtls_mpi_init(&e);
	mbedtls_mpi_init(&k);
	mbedtls_mpi_init(&r);
	mbedtls_mpi_init(&s);
	mbedtls_mpi_init(&tmp);
	mbedtls_mpi_init(&tmp_2);

	mbedtls_ecp_point_init(&KG);

	/* convert dgst to e  : e = h(m)  */
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_binary(&e, dgst, dgstlen));

	do
	{
		/* generate rand k  from range n*/
		size_t n_size = (ctx->grp.nbits + 7) / 8;
		MBEDTLS_MPI_CHK(mbedtls_mpi_fill_random(&k, n_size, f_rng, p_rng));
		MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&k, &k, &ctx->grp.N));

		/*KG = [K]G = (x1,y1)*/
		MBEDTLS_MPI_CHK(
			mbedtls_ecp_mul(&(ctx->grp), &KG, &k, &(ctx->grp.G), NULL, NULL));

		/*r = (e + x1) mod n*/
		/* tmp = e + x1 */
		MBEDTLS_MPI_CHK(mbedtls_mpi_add_mpi(&tmp, &e, &KG.X));
		MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&r, &tmp, &(ctx->grp.N)));

		/* r !=0 and r + k != n*/
		if (mbedtls_mpi_cmp_int(&r, 0) == 0)
		{
			continue;
		}
		else
		{
			mbedtls_mpi_free(&tmp);
			MBEDTLS_MPI_CHK(mbedtls_mpi_add_mpi(&tmp, &r, &k));
			if (mbedtls_mpi_cmp_mpi(&tmp, &(ctx->grp.N)) == 0)
			{
				continue;
			}
		}

		/* s = ((1 + d)^-1 * (k - rd)) mod n
		 * s = (((1 + d)^-1 mod n) *  ((k - rd) mod n) ) mod n
		 */

		/*((1 + d)^-1 mod n)*/
		mbedtls_mpi_free(&tmp);
		MBEDTLS_MPI_CHK(mbedtls_mpi_add_int(&tmp, &ctx->d, 1));
		MBEDTLS_MPI_CHK(mbedtls_mpi_inv_mod(&s, &tmp, &(ctx->grp.N)));

		/* ((k - rd) mod n) */
		/* tmp = rd */
		mbedtls_mpi_init(&tmp);
		MBEDTLS_MPI_CHK(mbedtls_mpi_mul_mpi(&tmp, &r, (&ctx->d)));
		/* tmp_2 = k - rd */
		MBEDTLS_MPI_CHK(mbedtls_mpi_sub_mpi(&tmp_2, &k, &tmp));
		/* tmp_2 mod n*/
		mbedtls_mpi_free(&tmp);
		MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&tmp, &tmp_2, &(ctx->grp.N)));

		/* tmp_2 = ((1 + d)^-1 mod n) *  ((k - rd) mod n) */
		mbedtls_mpi_free(&tmp_2);
		MBEDTLS_MPI_CHK(mbedtls_mpi_mul_mpi(&tmp_2, &s, &tmp));
		/* s = tmp_2 mod n*/
		mbedtls_mpi_free(&s);
		MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&s, &tmp_2, &(ctx->grp.N)));

		if (mbedtls_mpi_cmp_int(&s, 0) == 0)
		{
			continue;
		}
		else
		{
			break;
		}

	} while (1);

	if (max_out_len < SM3_LEN * 2)
	{
		ret = MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE;
		goto cleanup;
	}
	*olen = max_out_len;
	MBEDTLS_MPI_CHK(x_y2byte(&r, &s, &(ctx->grp), out, olen));

cleanup:
	mbedtls_mpi_free(&e);
	mbedtls_mpi_free(&k);
	mbedtls_mpi_free(&r);
	mbedtls_mpi_free(&s);
	mbedtls_mpi_free(&tmp);
	mbedtls_mpi_free(&tmp_2);
	mbedtls_ecp_point_free(&KG);
	return (ret);
}

/**
 * sm2 sign verify byte e
 *
 */
int sm2_do_verify(sm2_context *ctx, const unsigned char *message, size_t msglen,
				  const unsigned char *dgst, size_t dgstlen)
{
	int ret;
	mbedtls_mpi r;
	mbedtls_mpi s;
	mbedtls_mpi t;
	mbedtls_mpi tmp;

	mbedtls_ecp_point pointG;
	if (dgstlen < SM3_LEN * 2)
	{
		return MBEDTLS_ERR_SM2_BAD_INPUT_DATA;
	}

	mbedtls_mpi_init(&r);
	mbedtls_mpi_init(&s);
	mbedtls_mpi_init(&t);
	mbedtls_mpi_init(&tmp);

	mbedtls_ecp_point_init(&pointG);

	/*init r and s from byte*/
	mbedtls_mpi_read_binary(&r, dgst, SM3_LEN);
	mbedtls_mpi_read_binary(&s, dgst + SM3_LEN, SM3_LEN);

	/* check r, s in [1, n-1]*/
	if (mbedtls_mpi_cmp_int(&r, 1) == -1 || mbedtls_mpi_cmp_int(&s, 1) == -1 || mbedtls_mpi_cmp_mpi(&r, &(ctx->grp.N)) == 1 || mbedtls_mpi_cmp_mpi(&s, &(ctx->grp.N)) == 1)
	{
		ret = MBEDTLS_ERR_SM2_BAD_INPUT_DATA;
		goto cleanup;
	}

	/*  t = (r + s) mod n  */
	/* tmp = r + s*/
	MBEDTLS_MPI_CHK(mbedtls_mpi_add_mpi(&tmp, &r, &s));
	MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&t, &tmp, &(ctx->grp.N)));

	/* check t  != 0 */
	if (mbedtls_mpi_cmp_int(&t, 0) == 0)
	{
		ret = MBEDTLS_ERR_SM2_BAD_INPUT_DATA;
		goto cleanup;
	}

	/* compute pointG= (x, y) = sG + tP, P is pub_key */
	MBEDTLS_MPI_CHK(
		mbedtls_ecp_muladd(&(ctx->grp), &pointG, &s, &(ctx->grp.G), &t,
						   &(ctx->Pb)));

	/* tmp <- R = (e + x1) mod n  ;x1 in pointG */
	/* t <- e */
	mbedtls_mpi_free(&t);
	MBEDTLS_MPI_CHK(mbedtls_mpi_read_binary(&t, message, msglen));
	/* s <- e + x1 */
	mbedtls_mpi_free(&s);
	MBEDTLS_MPI_CHK(mbedtls_mpi_add_mpi(&s, &t, &(pointG.X)));
	/*tmp <- R = s mod n*/
	mbedtls_mpi_free(&tmp);
	MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&tmp, &s, &(ctx->grp.N)));

	/*tmp (R) = r ?*/
	if (mbedtls_mpi_cmp_mpi(&tmp, &r) != 0)
	{
		ret = MBEDTLS_ERR_SM2_VERIFY_FAILED;
	}

cleanup:

	mbedtls_mpi_free(&r);
	mbedtls_mpi_free(&s);
	mbedtls_mpi_free(&t);
	mbedtls_mpi_free(&tmp);

	mbedtls_ecp_point_free(&pointG);
	return (ret);
}

/**
 *  generate the e   e = H(m)
 */
int sm2_z_generate(sm2_context *ctx, const char *id, size_t idlen,
				   const char *message, size_t msglen, unsigned char *out)
{

	int ret;
	size_t hasg_len = SM3_LEN + msglen;
	unsigned char *hash = mbedtls_calloc(hasg_len, sizeof(unsigned char));

	size_t len_idlen = 2;
	size_t p_len = mbedtls_mpi_size(&(ctx->grp.P));
	size_t z_len = len_idlen + idlen + p_len * 6;
	unsigned char *z_buf = mbedtls_calloc(z_len, sizeof(unsigned char));

	if (hash == NULL || z_buf == NULL)
	{
		return MBEDTLS_ERR_SM2_ALLOC_FAILED;
	}

	/* z += ENTLa */
	int_to_byte_4(z_buf, 0, idlen * 8);
	/* z += id*/
	memcpy(z_buf + len_idlen, id, idlen);
	/* z += a*/
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&(ctx->grp.A), z_buf + len_idlen + idlen,
								 p_len));
	/* z += b*/
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&(ctx->grp.B),
								 z_buf + len_idlen + idlen + p_len, p_len));
	/* z += gx*/
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&(ctx->grp.G.X),
								 z_buf + len_idlen + idlen + p_len * 2, p_len));
	/* z +=gy*/
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&(ctx->grp.G.Y),
								 z_buf + len_idlen + idlen + p_len * 3, p_len));
	/* z += pk.x*/
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&(ctx->Pb.X),
								 z_buf + len_idlen + idlen + p_len * 4, p_len));
	/* z += pk.y*/
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_write_binary(&(ctx->Pb.Y),
								 z_buf + len_idlen + idlen + p_len * 5, p_len));
	/*sm3 z*/
	sm3(z_buf, z_len, hash);

	memcpy(hash + SM3_LEN, message, msglen);

	/*h(m)*/
	sm3(hash, hasg_len, out);

cleanup:
	mbedtls_free(hash);
	mbedtls_free(z_buf);

	return (ret);
}

/**
 *  sm2 sign
 */
int sm2_do_id_sign(sm2_context *ctx, const char *id, size_t idlen,
				   const char *message, size_t msglen, unsigned char *out,
				   size_t max_out_len, size_t *olen, int (*f_rng)(void *, unsigned char *, size_t), void *p_rng)
{

	int ret;
	unsigned char *hash = mbedtls_calloc(SM3_LEN, sizeof(unsigned char));
	if (hash == NULL)
	{
		return MBEDTLS_ERR_SM2_ALLOC_FAILED;
	}
	MBEDTLS_MPI_CHK(sm2_z_generate(ctx, id, idlen, message, msglen, hash));
	MBEDTLS_MPI_CHK(
		sm2_do_sign(ctx, hash, SM3_LEN, out, max_out_len, olen, f_rng, p_rng));

cleanup:
	mbedtls_free(hash);
	return (ret);
}

/**
 *   sm2 sign verify
 */
int sm2_do_id_verify(sm2_context *ctx, const char *id, size_t idlen,
					 const char *message, size_t msglen, const unsigned char *dgst,
					 size_t dgstlen)
{
	int ret;
	unsigned char *hash = mbedtls_calloc(SM3_LEN, sizeof(unsigned char));
	if (hash == NULL)
	{
		return MBEDTLS_ERR_SM2_ALLOC_FAILED;
	}
	MBEDTLS_MPI_CHK(sm2_z_generate(ctx, id, idlen, message, msglen, hash));
	MBEDTLS_MPI_CHK(sm2_do_verify(ctx, hash, SM3_LEN, dgst, dgstlen));

cleanup:
	mbedtls_free(hash);
	return (ret);
}

/**
 * test
 */

#if defined(MBEDTLS_SM2_SELF_TEST)

#define STR_LEN 300
#define PARAM_LEN 64

#define PP "8542D69E4C044F18E8B92435BF6FF7DE457283915C45517D722EDB8B08F1DFC3"
#define PA "787968B4FA32C3FD2417842E73BBFEFF2F3C848B6831D7E0EC65228B3937E498"
#define PB "63E4C6D3B23B0C849CF84241484BFE48F61D59A5B16BA06E6E12D1DA27C5249A"
#define PGX "421DEBD61B62EAB6746434EBC3CC315E32220B3BADD50BDC4C4E6C147FEDD43D"
#define PGY "0680512BCBB42C07D47349D2153B70C4E5D7FDFCBFA36EA1A85841B9E46E09A2"
#define PN "8542D69E4C044F18E8B92435BF6FF7DD297720630485628D5AE74EE7C32E79B7"

static int myrand(void *ctx, unsigned char *msg, size_t size)
{
	mbedtls_mpi k;
	mbedtls_mpi_init(&k);
	mbedtls_mpi_read_string(&k, HEX_CODE,
							"4C62EEFD6ECFC2B95B92FD6C3D9575148AFA17425546D49018E5388D49DD7B4F");
	mbedtls_mpi_write_binary(&k, msg, size);
	mbedtls_mpi_free(&k);
	return 0;
}

static int signrand(void *ctx, unsigned char *msg, size_t size)
{
	mbedtls_mpi k;
	if (ctx != NULL)
	{
		mbedtls_mpi_init(&k);
		mbedtls_mpi_read_string(&k, HEX_CODE,
								"6CB28D99385C175C94F94E934817663FC176D925DD72B727260DBAAE1FB2F96F");
		mbedtls_mpi_write_binary(&k, msg, size);
		mbedtls_mpi_free(&k);
	}

	return 0;
}

const char d1[] =
	"1649AB77A00637BD5E2EFE283FBF353534AA7F7CB89463F208DDBC2920BB0DA0";
const char d2[] =
	"128B2FA8BD433C6C068C8D803DFF79792A519A55171B1B650C23661D15897263";

const char pk1x[] =
	"435B39CCA8F3B508C1488AFC67BE491A0F7BA07E581A0E4849A5CF70628A7E0A";
const char pk1y[] =
	"75DDBA78F15FEECB4C7895E2C1CDF5FE01DEBB2CDBADF45399CCF77BBA076A42";
const char pk2x[] =
	"0AE4C7798AA0F119471BEE11825BE46202BB79E2A5844495E97C04FF4DF2548A";
const char pk2y[] =
	"7C0240F88F1CD4E16352A73C17B7F16F07353E53A176D684A9FE0C6BB798E857";

int mbedtls_sm2_self_test(int verbose)
{

	unsigned char *out = mbedtls_calloc(STR_LEN, sizeof(unsigned char));
	unsigned char *out2 = mbedtls_calloc(STR_LEN, sizeof(unsigned char));

	int ret = 0;
	size_t olen = 0, olen2 = 0;
	sm2_context sm2;
	sm2_init(&sm2);

	/**
	 *   not advice to set the group
	 *   but in here we just to test ,so set the test group param.
	 *   commonly we do not set the group;
	 *   because use the default group
	 *   \see sm2_init(sm2_context * context)
	 */
	ret = sm2_read_group_string(&sm2, PP, PA, PB, PGX, PGY, PN);
	if (ret != 0)
	{
		if (verbose > 0)
		{
			mbedtls_printf("sm2 init group failed:");
		}
		goto cleanup;
	}

	/**
	 *  encrypt and decrypt
	 */
	if (verbose == 1)
	{
		const char *str = "encryption standard";
		mbedtls_printf("sm2 encrypt start:");

		//set key
		sm2_read_string_private(&sm2, d1);
		sm2_read_string_public(&sm2, pk1x, pk1y);

		/**
		 * here use the test rand k so use myrand
		 */
		ret = sm2_do_encrypt(&sm2, (const unsigned char *)str, strlen(str), out, STR_LEN, &olen,
							 myrand, NULL);

		if (ret == 0)
		{
			mbedtls_printf("sm2 encrypt passed.");
		}
		else
		{
			mbedtls_printf("sm2 encrypt failed.");
			goto cleanup;
		}

		mbedtls_printf("sm2 decrypt start:");

		ret = sm2_do_decrypt(&sm2, out, olen, out2, STR_LEN, &olen2);

		if (ret == 0 && strcmp(str, (const char *)out2) == 0)
		{

			mbedtls_printf("sm2 decrypt passed.");
		}
		else
		{

			mbedtls_printf("sm2 decrypt failed.");
			goto cleanup;
		}
	}
	else if (verbose == 2)
	{
		//sign or verify
		const char *str = "message digest";
		const char *id = "ALICE123@YAHOO.COM";

		mbedtls_printf("sm2 sign start:");
		//set key
		sm2_read_string_private(&sm2, d2);
		sm2_read_string_public(&sm2, pk2x, pk2y);

		/**
		 * here use the test rand k so use signrand
		 */
		ret = sm2_do_id_sign(&sm2, id, strlen(id), str, strlen(str), out,
							 STR_LEN, &olen, signrand, NULL);

		if (ret == 0)
		{
			mbedtls_printf("sm2 sign passed.");
		}
		else
		{
			mbedtls_printf("sm2 sign failed.");
			goto cleanup;
		}

		mbedtls_printf("sm2 sign verify start:");

		ret = sm2_do_id_verify(&sm2, id, strlen(id), str, strlen(str), out,
							   olen);
		if (ret == 0)
		{
			mbedtls_printf("sm2 verify passed.");
		}
		else
		{
			mbedtls_printf("sm2 verify failed.");
			goto cleanup;
		}
	}
	else if (verbose == 3)
	{

		//        other test
		mbedtls_printf("sm2  key generate start:\n");

		sm2_free(&sm2);
		sm2_init(&sm2);

		// generate key test
		ssl_random_context random_ctx;

		ssl_random_init(&random_ctx);
		ssl_random_seed(&random_ctx, NULL, 0);
		ret = sm2_gen_keypair(&sm2, ssl_random_rand, &random_ctx);
		ssl_random_free(&random_ctx);

		if (ret == 0 && mbedtls_mpi_size(&sm2.d) > 0)
		{
			mbedtls_printf("sm2 key generate passed.\n");
			memset(out, 0, STR_LEN);
			mbedtls_mpi_write_binary(&sm2.d, out, 32);

			mbedtls_printf("private key is : \n");
			int i = 0;
			for (i = 0; i < 32; i++)
				mbedtls_printf("%02x", out[i]);
			mbedtls_printf("\n");

			mbedtls_printf("public key is \n");

			memset(out, 0, STR_LEN);
			mbedtls_mpi_write_binary(&sm2.Pb.X, out, 32);
			for (i = 0; i < 32; i++)
				mbedtls_printf("%02x", out[i]);
			mbedtls_printf("\n");
			memset(out, 0, STR_LEN);
			mbedtls_mpi_write_binary(&sm2.Pb.Y, out, 32);
			for (i = 0; i < 32; i++)
				mbedtls_printf("%02x", out[i]);
			mbedtls_printf("\n");
			memset(out, 0, STR_LEN);
			mbedtls_mpi_write_binary(&sm2.Pb.Z, out, 32);
			for (i = 0; i < 32; i++)
				mbedtls_printf("%02x", out[i]);
			mbedtls_printf("\n");
		}
		else
		{
			mbedtls_printf("sm2 generate failed. %d", ret);
			goto cleanup;
		}
	}

cleanup:
	sm2_free(&sm2);
	mbedtls_free(out);
	mbedtls_free(out2);

	return ret;
}

#endif // test
