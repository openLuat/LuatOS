//
// Created by  lzj on 2017/8/15.
//

#ifndef LIBCRYPTO_SM2_H
#define LIBCRYPTO_SM2_H

#include <internal/ssl_random.h>
#include <mbedtls/ecp.h>
#include <stddef.h>


/*
 * sm2 Error codes
 */
#define MBEDTLS_ERR_SM2_BAD_INPUT_DATA                    -0x7080  /**< Bad input parameters to function. */
#define MBEDTLS_ERR_SM2_KEY_GEN_FAILED                    -0x7180  /**< Something failed during generation of a key. */
#define MBEDTLS_ERR_SM2_KEY_CHECK_FAILED                  -0x7200  /**< Key failed to pass the library's validity check. */
#define MBEDTLS_ERR_SM2_PUBLIC_FAILED                     -0x7280  /**< The public key operation failed. */
#define MBEDTLS_ERR_SM2_PRIVATE_FAILED                    -0x7300  /**< The private key operation failed. */
#define MBEDTLS_ERR_SM2_VERIFY_FAILED                     -0x7380  /**< The standard verification failed. */
#define MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE                  -0x7400  /**< The output buffer for decryption is not large enough. */
#define MBEDTLS_ERR_SM2_RNG_FAILED                        -0x7480  /**< The random generator failed to generate non-zeros. */
#define MBEDTLS_ERR_SM2_ALLOC_FAILED                      -0x7500  /**< Failed to allocate memory. */


#ifdef __cplusplus
extern "C" {
#endif

/**
 *
 */
typedef int (*get_rand_from_range)(mbedtls_mpi *k, mbedtls_mpi *range);

/**
 * \brief           sm2 context structure
 */
typedef struct {
    mbedtls_ecp_group grp;      /*!<  elliptic curve used  group                 */
    mbedtls_mpi d;              /*!<   secret value (private key)                */
    mbedtls_ecp_point Pb;        /*!<   public value (public key)                 */
} sm2_context;


/**
 * \brief           Initialize context set default group
 *
 * \param ctx       Context to initialize
 *
 * \return          0 if successful,
 *                  MBEDTLS_ERR_MPI_XXX if initialization failed
 *                  MBEDTLS_ERR_ECP_FEATURE_UNAVAILABLE for unkownn groups
 */
int sm2_init(sm2_context *ctx);

/**
 * \brief           Free context
 *
 * \param ctx       Context to free
 */
void sm2_free(sm2_context *ctx);

/**
 * \brief           set private key by hex buf
 *
 * \param ctx       m2 context
 *
 * \param buf       private key hex buf
 *
 * \return          0 if successful,
 *                  or a MBEDTLS_ERR_MPI_XXX error code.
 */
int sm2_read_string_private(sm2_context *ctx, const char *buf);

/**
 * \brief           set public key by hex buf of point
 *
 * \param ctx       m2 context
 *
 * \param x         point x hex buf
 *
 * \param y         point y hex buf
 *
 * \return          0 if successful,
 *                  or a MBEDTLS_ERR_MPI_XXX error code.
 */
int sm2_read_string_public(sm2_context *ctx, const char *x, const char *y);

/**
 * \brief           Generate a  keypair.
 *                  Raw function that only does the core computation.
 *
 * \param ctx       sm2 context (no-null)
 *
 * \param f_rng     RNG function  (generate the private key suggest the sm3 drbg)
 *
 * \param p_rng     RNG parameter
 *
 * \return          0 if successful,
 *                  or a MBEDTLS_ERR_ECP_XXX or MBEDTLS_MPI_XXX error code
 */
int sm2_gen_keypair(sm2_context *ctx, int (*f_rng)(void *, unsigned char *, size_t),
                    void *p_rng);

/**
 *
 * \brief           set sm2 group by hex string param
 *
 * \param ctx       sm2 context
 *
 * \param p         p hex string buffer 64 word
 *
 * \param a         a hex string buffer 64 word
 *
 * \param b         b hex string buffer 64 word
 *
 * \param gx        gx hex string buffer 64 word
 *
 * \param gy        gy hex string buffer 64 word
 *
 * \param n         n hex string buffer 64 word
 *
 * \return          0 if successful, or a MBEDTLS_ERR_MPI_XXX error code
 */
int sm2_read_group_string(sm2_context *ctx, const char *p, const char *a, const char *b,
                          const char *gx, const char *gy, const char *n);

/**
 * \brief           Check that an mbedtls_mpi is a valid private key for this curve
 *
 * \param ctx       sm2 context
 *
 * \return          0 if point is a valid private key,
 *                  MBEDTLS_ERR_ECP_INVALID_KEY otherwise.
 */
int sm2_check_private(sm2_context *ctx);


/**
 * \brief           Check that an mbedtls_mpi_point is a valid public key for this curve
 *
 * \param ctx       sm2 context
 *
 * \return          0 if point is a valid private key,
 *                  MBEDTLS_ERR_ECP_INVALID_KEY otherwise.
 */
int sm2_check_public(sm2_context *ctx);

/**
 * \brief           generate the message H(m`), with sm3;
 *                  m` = Z || M
 *
 * \param ctx       sm2 context
 *
 * \param id        user id string
 *
 * \param idlen     id string length
 *
 * \param message   need digest message string
 *
 * \param msglen    message length
 *
 * \param out       result
 *
 * \return          0 if successful,otherwise
 *                  MBEDTLS_ERR_SM2_ALLOC_FAILED,MBEDTLS_ERR_MPI_ALLOC_FAILED
 *
 */
int sm2_z_generate(sm2_context *ctx, const char *id, size_t idlen, const char *message,
                   size_t msglen, unsigned char *out);

/**
 * \brief           sm2 encrypt
 *
 * \param ctx       sm2 context
 *
 * \param buffer    bytes need to encrypt
 *
 * \param plen      string length
 *
 * \param out       cipher text in byte array (not hex string)
 *
 * \param max_out_len   out max length ,
 *                  if the len smaller than olen the encrypt option will failed
 *
 * \param olen      the cipher length
 *
 * \param f_rng     RNG function
 * \param p_rng     RNG parameter
 *
 * \return          0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */
int sm2_do_encrypt(sm2_context *ctx, const unsigned char *buffer, size_t plen,
                   unsigned char *out, size_t max_out_len, size_t *olen,
                   int (*f_rng)(void *, unsigned char *, size_t), void *p_rng);

/**
 * \brief           sm2 decrypt
 *
 * \param ctx       sm2 context
 *
 * \param cipher    cipher text need to decrypt ;
 *                  onte: the cipher are byte array ,them are not string
 *                  if you input the string ,should transform the string to byte
 *                  such as "120DEDF" is hex string, should make it to byte using the function you did
 *                  hexString2byte.
 *
 * \param clen      the cipher byte length
 *
 * \param out       the message in byte (not hex string)
 *
 * \param max_out_len out max length ,
 *                  if the len smaller than olen the decrypt option will failed
 *
 * \param olen      the out byte length
 *
 * \return          0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */
int sm2_do_decrypt(sm2_context *ctx, const unsigned char *cipher, size_t clen,
                   unsigned char *out, size_t max_out_len, size_t *olen);


/**
 * \brief           sm2 sign byte (e)
 *
 * \param ctx       sm2 context
 *
 * \param dgst      the e in byte  (e = H(m))
 *
 * \param dgstlen   e length ,commonly is 32, that meaning 256 bits
 *
 * \param out       the (r,s) byte array ,which format is r||s. 64 word
 *
 * \param max_out_len out max length ,
 *                  if the len smaller than olen the sign option will failed
 *
 * \param olen      the out byte array length commonly is 64 word
 *
 * \param f_rng     RNG function
 * \param p_rng     RNG parameter
 *
 * \return          0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */
int sm2_do_sign(sm2_context *ctx, const unsigned char *dgst, size_t dgstlen,
                unsigned char *out, size_t max_out_len, size_t *olen,
                int (*f_rng)(void *, unsigned char *, size_t), void *p_rng);

/**
 * \brief           sm2 sign
 *
 * \param ctx       sm2 context
 *
 * \param id        user id such as user mail string
 *
 * \param idlen     id string length
 *
 * \param message   need sign message string
 *
 * \param msglen    message length
 *
 * \param out       the (r,s) byte array ,which format is r||s. 64 word
 *
 * \param max_out_len out max length ,
 *                  if the len smaller than olen the sign option will failed
 *
 * \param olen      the out byte array length commonly is 64 word
 *
 * \param f_rng     RNG function
 * \param p_rng     RNG parameter
 *
 * \return          0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */
int sm2_do_id_sign(sm2_context *ctx, const char *id, size_t idlen, const char *message,
                   size_t msglen, unsigned char *out, size_t max_out_len, size_t *olen,
                   int (*f_rng)(void *, unsigned char *, size_t), void *p_rng);

/**
 *
 * \brief           sm2 sign verify byte (e)
 *
 * \param ctx       sm2 context
 *
 * \param message   the e in byte  (e = H(m))
 *
 * \param msglen    e length ,commonly is 32 that meaning 256 bite
 *
 * \param dgst      need to verify byte array (not hex string)
 *                  onte: the buff are byte array ,them are not string
 *                  if you input the string ,should transform the string to byte
 *                  such as "120DEDF" is hex string, should make it to byte using the function you did
 *                  hexString2byte.
 *
 * \param dgstlen   dgst byte array length
 *
 * \return          0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */
int sm2_do_verify(sm2_context *ctx, const unsigned char *message, size_t msglen,
                  const unsigned char *dgst, size_t dgstlen);

/**
 *
 * \brief           sm2 sign verify
 *
 * \param ctx       sm2 context
 *
 * \param id        user id such as user mail string
 *
 * \param idlen     id string length
 *
 * \param message   received message string
 *
 * \param msglen    messgae string length
 *
 * \param dgst      need to verify byte array (not hex string)
 *                  onte: the buff are byte array ,them are not string
 *                  if you input the string ,should transform the string to byte
 *                  such as "120DEDF" is hex string, should make it to byte using the function you did
 *                  hexString2byte.
 *
 * \param dgstlen   dgst byte array length
 *
 * \return          0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */

int sm2_do_id_verify(sm2_context *ctx, const char *id, size_t idlen, const char *message,
                     size_t msglen, const unsigned char *dgst, size_t dgstlen);

/**
 * \brief           sm2 context copy
 *
 * \param dst       dst sm2 context
 *
 * \param src       const src sm2 context
 *
 * \return         0 if successful
 *                  otherwise MBEDTLS_ERR_SM2_OUTPUT_TOO_LARGE,
 *                  MBEDTLS_ERR_SM2_BAD_INPUT_DATA,MBEDTLS_ERR_SM2_ALLOC_FAILED
 *                  ,MBEDTLS_ERR_ECP_XXX or MBEDTLS_ERR_MPI_XXX
 */
int sm2_copy(sm2_context *dst, const sm2_context *src);

/**
 * \brief           sm2 test
 *
 * \param verbose   0 is nothing ;
 *                  1 is test encrypt and decrypt;
 *                  2 is test sign and verify
 *
 * @return          0 if successful
 */
int mbedtls_sm2_self_test(int verbose);

#ifdef __cplusplus
}
#endif

#endif //LIBCRYPTO_SM2_H
