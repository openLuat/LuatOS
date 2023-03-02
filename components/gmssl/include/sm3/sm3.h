/**
 *
 *
 * \file        sm3.h
 *
 * \brief       this file is header file for sm3(chinese business Digital Digest).
 *              and  compatible md framework.
 *
 * \anchor      lzj
 *
 * \date        2017/8/14
 *
 *
 */


#ifndef LIBCRYPTO_SM3_H
#define LIBCRYPTO_SM3_H



#include <stddef.h>
#include <stdint.h>


#ifdef __cplusplus
extern "C" {
#endif

/**
 * \brief          SM3 context structure
 */
typedef struct {
    uint32_t total[2];          /*!< number of bytes processed  */
    uint32_t state[8];          /*!< intermediate digest state  */
    unsigned char buffer[64];   /*!< data block being processed */
} sm3_context;


/**
 * \brief          Initialize SM3 context
 *
 * \param ctx      SM3 context to be initialized
 */
void sm3_init(sm3_context *ctx);

/**
 * \brief          Clear SM3 context
 *
 * \param ctx      SM3 context to be cleared
 */
void sm3_free(sm3_context *ctx);

/**
 * \brief          Clone (the state of) a SM3 context
 *
 * \param dst      The destination context
 * \param src      The context to be cloned
 */
void sm3_clone(sm3_context *dst, const sm3_context *src);


/**
 * \brief          SM3 context setup
 *
 * \param ctx      context to be initialized
 */
void sm3_starts( sm3_context *ctx );


/**
 * \brief          SM3 process buffer
 *
 * \param ctx      SM3 context
 * \param input    buffer holding the  data
 * \param ilen     length of the input data
 */
void sm3_update(sm3_context *ctx, const unsigned char *input,
                size_t ilen);

/**
 * \brief          SM3 final digest
 *
 * \param ctx      SM3 context
 * \param output   SM3 checksum result
 */
void sm3_finish(sm3_context *ctx, unsigned char output[32]);

/* Internal use */
void sm3_process(sm3_context *ctx, const unsigned char block[64]);

/**
 * \brief          Output = SM3( input buffer )
 *
 * \param input    buffer holding the  data
 * \param ilen     length of the input data
 * \param output   SM3 checksum result
 */
void sm3(const unsigned char *input, size_t ilen,
         unsigned char output[32]);

/**
 * \brief          Checkup routine
 *
 * \return         0 if successful, or 1 if the test failed
 */
int sm3_self_test(int verbose);


#ifdef __cplusplus
}
#endif


#endif //LIBCRYPTO_SM3_H
