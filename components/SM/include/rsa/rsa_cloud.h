//
// Created by bianq on 2017/9/11.
//

#ifndef AISINOSSL_RSA_CLOUD_H
#define AISINOSSL_RSA_CLOUD_H

#include <mbedtls/bignum.h>

/**
 * padding MBEDTLS_RSA_PKCS_V15
 */

#define MBEDTLS_ERR_RSA_CLOUD_SERVER_N_S_NULL                    -0x8080  /**< Bad input parameters to function  that server context n_S ==null. */
#define MBEDTLS_ERR_RSA_CLOUD_BAD_INPUT_DATA                     -0X8100    /**< Bad input parameters to function. */
#define MBEDTLS_ERR_CLOUD_RSA_KEY_GEN_FAILED                     -0x8180  /**< Something failed during generation of a key. */
#define MBEDTLS_ERR_CLOUD_RSA_KEY_SERVER_TRANSFORMATION_FAILED   -0x8200  /**< Something failed during verify mds. */
#define MBEDTLS_ERR_CLOUD_RSA_KEY_SERVER_TRANSFORMATION_BAD_OUT   -0x8300  /**< out buffer too small. */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * rand generater function
 */
typedef int (*f_rand)(void *, unsigned char *, size_t);

/**
 * public key
 */
typedef struct {
	mbedtls_mpi N; /*!<  public modulus    */
	mbedtls_mpi E; /*!<  public exponent   */
} rsa_cloud_pk;

/**
 * private key
 */
typedef struct {
	mbedtls_mpi N; /*!<  public modulus    */
	mbedtls_mpi D; /*!<  private exponent  */
} rsa_cloud_sk;

/**
 * rsa cloud context
 */
typedef struct {
	int ver; /*!<  always 0          */
	size_t len; /*!<  size(N) in chars  */
	rsa_cloud_pk PK; /*!<  public  key        */
	rsa_cloud_sk SK; /*!<  private  key       */
	mbedtls_mpi P; /*!<  1st prime factor  */
	mbedtls_mpi Q; /*!<  2nd prime factor  */

} rsa_cloud_context;

/**
 * rsa cloud hsk context
 */
typedef struct {
	mbedtls_mpi hd_A;
	mbedtls_mpi hd_SA;
	mbedtls_mpi n_A;

} rsa_cloud_hsk_context;

/**
 * rsa cloud mds context
 */
typedef struct {
	mbedtls_mpi q_;
	mbedtls_mpi hd_SA;
} rsa_cloud_mds_context;

/**
 * @brief               Initialization  the rsa context
 *
 * @param ctx           rsa context
 */
void rsa_cloud_init(rsa_cloud_context *ctx);

/**
 * @brief               free the rsa context
 *
 * @param ctx           rsa context
 */
void rsa_cloud_free(rsa_cloud_context *ctx);

/**
 * @brief               Initialization  the hsk context
 *
 * @param ctx           hsk context
 */
void rsa_cloud_hsk_init(rsa_cloud_hsk_context *ctx);

/**
 * @brief               free the hsk context
 *
 * @param ctx           hsk context
 */
void rsa_cloud_hsk_free(rsa_cloud_hsk_context *ctx);

/**
 * @brief               Initialization  the mds context
 *
 * @param ctx           mds context
 */
void rsa_cloud_mds_init(rsa_cloud_mds_context *ctx);

/**
 * @brief               free the mds context
 *
 * @param ctx           mds context
 */
void rsa_cloud_mds_free(rsa_cloud_mds_context *ctx);

/**
 * @brief               generate the server keypair
 *
 * @param ctx           server rsa context
 *
 * @param f_rng         rand function  (generate the q or p)
 *
 * @param p_rng         rand function param
 *
 * @param nbits         key size (note the size must bigger than 256 or be equal to 256)
 *
 * @param exponent      the e modulus
 *
 * @return              0 if successful
 *                      otherwise a MBEDTLS_ERR_CLOUD_RSA_KEY_GEN_FAILED error code
 */
int
rsa_cloud_gen_server_keypair(rsa_cloud_context *ctx, f_rand f_rng, void *p_rng,
		unsigned int nbits, int exponent);
/**
 * @brief               generate the client keypair
 *
 * @param ctx           client rsa context
 *
 * @param pk_server     server public key
 *
 * @param f_rng         rand function  (generate the q or p)
 *
 * @param p_rng         rand function param
 *
 * @param nbits         key size (note the size must bigger than 256 or be equal to 256)
 *
 * @param exponent      the e modulus
 *
 * @return              0 if successful
 *                      otherwise a MBEDTLS_ERR_CLOUD_RSA_KEY_GEN_FAILED,
 *                      MBEDTLS_ERR_RSA_CLOUD_SERVER_N_S_NULL error code
 */
int rsa_cloud_gen_client_keypair(rsa_cloud_context *ctx,
		const rsa_cloud_pk *pk_server, f_rand f_rng, void *p_rng,
		unsigned int nbits, int exponent);
/**
 * @brief               generate a random number from 1 to range -1
 *
 * @param k             out,the random number
 *
 * @param range         random number range
 *
 *
 * @return              0 if successful
 *                      otherwise a MBEDTLS_ERR_MPI_ALLOC_FAILED error code
 *                      if memory allocation failed
 */
int rsa_cloud_rand(mbedtls_mpi *k, const mbedtls_mpi *range);

/**
 * @brief               hide the key in client
 *
 * @param client        private key of client
 *
 * @param pk_server     public key of server
 *
 * @param hsk           out,hsk context
 *
 * @return              0 if successful
 *                      otherwise a  MBEDTLS_ERR_MPI_XXX error code
 */
int
rsa_cloud_key_hide(const rsa_cloud_sk *client, const rsa_cloud_pk *pk_server,
		rsa_cloud_hsk_context *hsk);

/**
 * @brief               use hsk to encrypt the message and save to mds
 *
 * @param hsk           hsk context from key hide output
 *
 * @param message       the message
 *
 * @param msglen        message length
 *
 * @param mds           out,mds context
 *
 * @return              0 if successful
 *                      otherwise a  MBEDTLS_ERR_MPI_XXX error code
 */
int rsa_cloud_md_sign(const rsa_cloud_hsk_context *hsk,const char *message,
		size_t msglen, rsa_cloud_mds_context *mds);

/**
 * @brief               to verfiy mds in server
 *
 * @param client        public key of client
 *
 * @param server        private key of server
 *
 * @param mds           mds context
 *
 * @param message       the message
 *
 * @param msglen        message length
 *
 * @param out        	rsa signature
 *
 * @param outlen 	    out array length
 *
 * @param olen      	the signature byte length
 *
 * @return              0 if successful
 *                      otherwise a MBEDTLS_ERR_CLOUD_RSA_KEY_SERVER_TRANSFORMATION_FAILED error code
 */
int rsa_cloud_transformation(const rsa_cloud_pk *client,
		const rsa_cloud_sk *server, const rsa_cloud_mds_context *mds,
		const char *message, size_t msglen, unsigned char *out,
		size_t outlen, size_t *olen);
/**
 * @brief               just test and give a sample to show how to use the system
 *
 * @return              0 if successful
 *                      otherwise is error
 */
#ifdef RSA_CLOUD_TEST
int rsa_cloud_sefl_test_all();
#endif
#ifdef __cplusplus
}
#endif

#endif //AISINOSSL_RSA_CLOUD_H
