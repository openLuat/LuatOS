//
// Created by lzj on 2017/9/11.
//

#include <rsa/rsa_cloud.h>
#include <mbedtls/hmac_drbg.h>
#include <mbedtls/sha256.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <internal/ssl_random.h>

void rsa_cloud_init(rsa_cloud_context *ctx)
{
	memset(ctx, 0, sizeof(rsa_cloud_context));
}

void rsa_cloud_free(rsa_cloud_context *ctx)
{
	mbedtls_mpi_free(&ctx->Q);
	mbedtls_mpi_free(&ctx->P);
	mbedtls_mpi_free(&ctx->PK.E);
	mbedtls_mpi_free(&ctx->SK.D);
	mbedtls_mpi_free(&ctx->PK.N);
	mbedtls_mpi_free(&ctx->SK.N);
}

void rsa_cloud_hsk_init(rsa_cloud_hsk_context *ctx)
{
	memset(ctx, 0, sizeof(rsa_cloud_hsk_context));
}

void rsa_cloud_hsk_free(rsa_cloud_hsk_context *ctx)
{
	mbedtls_mpi_free(&ctx->hd_A);
	mbedtls_mpi_free(&ctx->hd_SA);
	mbedtls_mpi_free(&ctx->n_A);
}

void rsa_cloud_mds_init(rsa_cloud_mds_context *ctx)
{
	memset(ctx, 0, sizeof(rsa_cloud_hsk_context));
}

void rsa_cloud_mds_free(rsa_cloud_mds_context *ctx)
{
	mbedtls_mpi_free(&ctx->hd_SA);
	mbedtls_mpi_free(&ctx->q_);
}

static int rsa_cloud_gen_keypair(rsa_cloud_context *ctx,
								 int (*f_rng)(void *, unsigned char *, size_t), void *p_rng,
								 unsigned int nbits, int exponent, const mbedtls_mpi *judge)
{
	int ret;
	mbedtls_mpi P1, Q1, H, G;

	if (f_rng == NULL || nbits < 128 || exponent < 3)
		return (MBEDTLS_ERR_RSA_CLOUD_BAD_INPUT_DATA);

	if (nbits % 2)
		return (MBEDTLS_ERR_RSA_CLOUD_BAD_INPUT_DATA);

	mbedtls_mpi_init(&P1);
	mbedtls_mpi_init(&Q1);
	mbedtls_mpi_init(&H);
	mbedtls_mpi_init(&G);

	/*
	 * find primes P and Q with Q < P so that:
	 * GCD( E, (P-1)*(Q-1) ) == 1
	 */
	MBEDTLS_MPI_CHK(mbedtls_mpi_lset(&ctx->PK.E, exponent));

	do
	{
		MBEDTLS_MPI_CHK(
			mbedtls_mpi_gen_prime(&ctx->P, nbits >> 1, 0, f_rng, p_rng));

		MBEDTLS_MPI_CHK(
			mbedtls_mpi_gen_prime(&ctx->Q, nbits >> 1, 0, f_rng, p_rng));

		if (mbedtls_mpi_cmp_mpi(&ctx->P, &ctx->Q) == 0)
			continue;

		MBEDTLS_MPI_CHK(mbedtls_mpi_mul_mpi(&ctx->PK.N, &ctx->P, &ctx->Q));

		if (judge != NULL && mbedtls_mpi_cmp_mpi(&ctx->PK.N, judge) >= 0)
		{
			continue;
		}

		if (mbedtls_mpi_bitlen(&ctx->PK.N) != nbits)
			continue;

		if (mbedtls_mpi_cmp_mpi(&ctx->P, &ctx->Q) < 0)
			mbedtls_mpi_swap(&ctx->P, &ctx->Q);

		MBEDTLS_MPI_CHK(mbedtls_mpi_sub_int(&P1, &ctx->P, 1));
		MBEDTLS_MPI_CHK(mbedtls_mpi_sub_int(&Q1, &ctx->Q, 1));
		MBEDTLS_MPI_CHK(mbedtls_mpi_mul_mpi(&H, &P1, &Q1));
		MBEDTLS_MPI_CHK(mbedtls_mpi_gcd(&G, &ctx->PK.E, &H));
	} while (mbedtls_mpi_cmp_int(&G, 1) != 0);

	/*
	 * D  = E^-1 mod ((P-1)*(Q-1))
	 */
	MBEDTLS_MPI_CHK(mbedtls_mpi_inv_mod(&ctx->SK.D, &ctx->PK.E, &H));
	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&ctx->SK.N, &ctx->PK.N));

	ctx->len = (mbedtls_mpi_bitlen(&ctx->PK.N) + 7) >> 3;

cleanup:

	mbedtls_mpi_free(&P1);
	mbedtls_mpi_free(&Q1);
	mbedtls_mpi_free(&H);
	mbedtls_mpi_free(&G);

	if (ret != 0)
	{
		rsa_cloud_free(ctx);
		return (MBEDTLS_ERR_CLOUD_RSA_KEY_GEN_FAILED + ret);
	}

	return (0);
}

int rsa_cloud_gen_server_keypair(rsa_cloud_context *ctx, f_rand f_rng,
								 void *p_rng, unsigned int nbits, int exponent)
{
	return rsa_cloud_gen_keypair(ctx, f_rng, p_rng, nbits, exponent, NULL);
}

int rsa_cloud_gen_client_keypair(rsa_cloud_context *ctx,
								 const rsa_cloud_pk *pk_server, f_rand f_rng, void *p_rng,
								 unsigned int nbits, int exponent)
{
	if (pk_server == NULL)
	{
		return MBEDTLS_ERR_RSA_CLOUD_SERVER_N_S_NULL;
	}

	return rsa_cloud_gen_keypair(ctx, f_rng, p_rng, nbits, exponent,
								 &pk_server->N);
}

/**
 *  generate big number k from 1 to range-1
 */

int rsa_cloud_rand(mbedtls_mpi *k, const mbedtls_mpi *range)
{
	int ret;
	size_t size;
	ssl_random_context ctx;
	mbedtls_mpi tmp;
	unsigned char *out;
	mbedtls_mpi_init(&tmp);

	ssl_random_init(&ctx);
	ssl_random_seed(&ctx, NULL, 0);

	size = mbedtls_mpi_size(range);
	MBEDTLS_MPI_CHK(mbedtls_mpi_sub_int(&tmp, range, 1));

	out = calloc(size, sizeof(unsigned char));
	do
	{
		ssl_random_rand(&ctx, out, size);
		MBEDTLS_MPI_CHK(mbedtls_mpi_read_binary(k, out, size));

	} while (mbedtls_mpi_cmp_mpi(k, &tmp) > -1 || mbedtls_mpi_cmp_int(k, 1) < 1);

cleanup:
	ssl_random_free(&ctx);
	mbedtls_mpi_free(&tmp);
	free(out);
	return (ret);
}

int rsa_cloud_key_hide(const rsa_cloud_sk *client,
					   const rsa_cloud_pk *pk_server, rsa_cloud_hsk_context *hsk)
{

	int ret;
	mbedtls_mpi d_SA;

	mbedtls_mpi_init(&d_SA);

	// hda = da - dsa
	do
	{
		MBEDTLS_MPI_CHK(rsa_cloud_rand(&d_SA, &client->N));
		MBEDTLS_MPI_CHK(mbedtls_mpi_sub_mpi(&hsk->hd_A, &client->D, &d_SA));

	} while (mbedtls_mpi_cmp_int(&hsk->hd_A, 0) < 1);

	// encrypt hda
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_exp_mod(&hsk->hd_SA, &d_SA, &pk_server->E, &pk_server->N, NULL));

	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&hsk->n_A, &client->N));

cleanup:
	mbedtls_mpi_free(&d_SA);
	return ret;
}

int rsa_cloud_md_sign(const rsa_cloud_hsk_context *hsk, const char *message,
					  size_t msglen, rsa_cloud_mds_context *mds)
{
	int ret;

	unsigned char h[32];
	mbedtls_mpi t;

	memset(h, 0, sizeof(h));
	mbedtls_mpi_init(&t);

	//h = H(m)
	mbedtls_sha256((unsigned char *)message, msglen, h, 1);

	mbedtls_mpi_read_binary(&t, h, sizeof(h));

	if (mbedtls_mpi_cmp_mpi(&t, &hsk->n_A) >= 0)
	{
		ret = MBEDTLS_ERR_MPI_BAD_INPUT_DATA;
		goto cleanup;
	}

	// encrypt hda
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_exp_mod(&mds->q_, &t, &hsk->hd_A, &hsk->n_A, NULL));

	MBEDTLS_MPI_CHK(mbedtls_mpi_copy(&mds->hd_SA, &hsk->hd_SA));

cleanup:
	mbedtls_mpi_free(&t);
	return ret;
}

int rsa_cloud_transformation(const rsa_cloud_pk *client,
							 const rsa_cloud_sk *server, const rsa_cloud_mds_context *mds,
							 const char *message, size_t msglen, unsigned char *out, size_t outlen,
							 size_t *olen)
{
	int ret;
	unsigned char hash[32];
	mbedtls_mpi d_SA, q, h, tmp;

	memset(hash, 0, sizeof(hash));
	mbedtls_mpi_init(&d_SA);
	mbedtls_mpi_init(&q);
	mbedtls_mpi_init(&h);
	mbedtls_mpi_init(&tmp);

	//h = H(m)
	mbedtls_sha256((unsigned char *)message, msglen, hash, 1);
	mbedtls_mpi_read_binary(&h, hash, sizeof(hash));

	if (mbedtls_mpi_cmp_mpi(&h, &client->N) >= 0)
	{
		ret = MBEDTLS_ERR_MPI_BAD_INPUT_DATA;
		goto cleanup;
	}

	if (mbedtls_mpi_cmp_mpi(&mds->hd_SA, &server->N) >= 0)
	{
		ret = MBEDTLS_ERR_MPI_BAD_INPUT_DATA;
		goto cleanup;
	}

	// decrypt hda
	// d_sa = (hd_sa)^d_s mod n_s
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_exp_mod(&d_SA, &mds->hd_SA, &server->D, &server->N, NULL));

	//q = q_ * h^d_sa mod n_a
	// q = (q_ mod n_a ) * (h^d_sa mod n_a) mod n_a
	//q = (q_ mod n_a )
	MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&q, &mds->q_, &client->N));
	//tmp = (h^d_sa mod n_a)
	MBEDTLS_MPI_CHK(mbedtls_mpi_exp_mod(&tmp, &h, &d_SA, &client->N, NULL));
	//q = q* tmp
	MBEDTLS_MPI_CHK(mbedtls_mpi_mul_mpi(&q, &q, &tmp));
	//q =q mod n_a
	MBEDTLS_MPI_CHK(mbedtls_mpi_mod_mpi(&q, &q, &client->N));

	//tmp = q ^e_A mod n_a
	mbedtls_mpi_free(&tmp);
	MBEDTLS_MPI_CHK(
		mbedtls_mpi_exp_mod(&tmp, &q, &client->E, &client->N, NULL));

	if (mbedtls_mpi_cmp_mpi(&h, &tmp) != 0)
	{
		ret = MBEDTLS_ERR_CLOUD_RSA_KEY_SERVER_TRANSFORMATION_FAILED;
	}

	*olen = mbedtls_mpi_size(&q);
	if (outlen < *olen)
	{
		ret = MBEDTLS_ERR_CLOUD_RSA_KEY_SERVER_TRANSFORMATION_BAD_OUT;
	}
	else
	{
		mbedtls_mpi_write_binary(&q, out, *olen);
	}

cleanup:
	mbedtls_mpi_free(&d_SA);
	mbedtls_mpi_free(&q);
	mbedtls_mpi_free(&h);
	mbedtls_mpi_free(&tmp);
	return ret;
}

#ifdef RSA_CLOUD_TEST
int rsa_cloud_sefl_test_all()
{
	int ret;
	size_t olen;
	int i;
	unsigned char out[64];
	const char *str = "hello world";
	rsa_cloud_context server, client;
	rsa_cloud_hsk_context hsk;
	rsa_cloud_mds_context mds;
	mbedtls_hmac_drbg_context drbg;

	mbedtls_hmac_drbg_init(&drbg);
	rsa_cloud_init(&server);
	rsa_cloud_init(&client);
	rsa_cloud_hsk_init(&hsk);
	rsa_cloud_mds_init(&mds);

	ret = rsa_cloud_gen_server_keypair(&server, mbedtls_hmac_drbg_random, &drbg,
									   256, 3);

	printf("server pk e: ");
	mbedtls_mpi_write_binary(&server.PK.E, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("server pk n: ");
	mbedtls_mpi_write_binary(&server.PK.N, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("server sk d: ");
	mbedtls_mpi_write_binary(&server.SK.D, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("server sk n: ");
	mbedtls_mpi_write_binary(&server.SK.N, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("server p: ");
	mbedtls_mpi_write_binary(&server.P, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("server q: ");
	mbedtls_mpi_write_binary(&server.Q, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");

	ret = rsa_cloud_gen_client_keypair(&client, &server.PK,
									   mbedtls_hmac_drbg_random, &drbg, 256, 3);

	printf("client pk e: ");
	mbedtls_mpi_write_binary(&client.PK.E, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("client pk n: ");
	mbedtls_mpi_write_binary(&client.PK.N, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("client sk d: ");
	mbedtls_mpi_write_binary(&client.SK.D, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("client sk n: ");
	mbedtls_mpi_write_binary(&client.SK.N, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("client p: ");
	mbedtls_mpi_write_binary(&client.P, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("client q: ");
	mbedtls_mpi_write_binary(&client.Q, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");

	ret = rsa_cloud_key_hide(&client.SK, &server.PK, &hsk);

	printf("hsk hd_a: ");
	mbedtls_mpi_write_binary(&hsk.hd_A, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("hsk hd_sa: ");
	mbedtls_mpi_write_binary(&hsk.hd_SA, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("hsk n_a: ");
	mbedtls_mpi_write_binary(&hsk.n_A, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");

	ret = rsa_cloud_md_sign(&hsk, str, strlen(str), &mds);

	printf("mds q_: ");
	mbedtls_mpi_write_binary(&mds.q_, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");
	printf("mds hd_sa: ");
	mbedtls_mpi_write_binary(&mds.hd_SA, out, 32);
	for (i = 0; i < 32; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");

	ret = rsa_cloud_transformation(&client.PK, &server.SK, &mds, str,
								   strlen(str), out, 64, &olen);

	printf("signature : \n");

	for (i = 0; i < (int)olen; ++i)
	{
		printf("%02x", out[i]);
	}
	printf("\n");

	rsa_cloud_free(&server);
	rsa_cloud_free(&client);
	rsa_cloud_hsk_free(&hsk);
	rsa_cloud_mds_free(&mds);
	mbedtls_hmac_drbg_free(&drbg);
	return ret;
}
#endif