#ifndef HEADER_SSL_RANDOM_H
#define HEADER_SSL_RANDOM_H

/*
Random Module

Sample:
ssl_random_context ctx;
ssl_random_init(&ctx);
ssl_random_seed(&ctx, NULL, 0);
// ctx->drbg_ctx CAN BE USED TO hmac_drbg
ssl_random_rand_int_array(&ctx, arr, 30);
ssl_random_free(&ctx);

*/

#ifdef _WIN32
#define _CRT_RAND_S
#endif
#include <stdlib.h>

#include <time.h>
#include <string.h>
#include <openssl/modes.h>
#include <mbedtls/md.h>
#include <mbedtls/hmac_drbg.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef ANDROID_VER
#include <sys/system_properties.h>
#include <android/sensor.h>
#include <android/looper.h>
#endif

// Control HMAC-DRBG Hash Algorithm
// Attention! Use #define to set it
#ifndef RANDOM_HASH_ALGORITHM
#define RANDOM_HASH_ALGORITHM MD_SM3
#endif

// SET ANDROID SENSOR
// NOTE: https://developer.android.com/ndk/reference/group/sensor
//#define ENABLE_SEED_ANDROID_SENSOR
#define SEED_DEFAULT_SENSOR ASENSOR_TYPE_MAGNETIC_FIELD

// SET iOS SENSOR
// TODO: some bugs need be fixed (Issue #4)
#define ENABLE_SEED_IOS_SENSOR

// For Android test
//#define _DEBUG_

// static unsigned int SSLRandomContextCount = 0;

// HMAC-DRBG Random Class
typedef struct {
    short isInitial;
    short isSeeded;

    unsigned char hashLen;
    unsigned char *hash;

    const mbedtls_md_info_t *md_info;     /*!<  Hash Type Info    */
    mbedtls_md_context_t *md_ctx;         /*!<  MD Context        */
    mbedtls_hmac_drbg_context *drbg_ctx;  /*!<  HMAC DRBG Context */
} ssl_random_context;

// Init Random Context
int ssl_random_init(ssl_random_context *ctx);

// Set or reset a seed
int ssl_random_seed(void* rand_ctx, unsigned char *seed_buf, size_t buf_size);
int ssl_random_seed_with_option(void *rand_ctx, unsigned char *seed_buf, size_t buf_size, int options);

// Rand a list of Number
int ssl_random_rand(void *rand_ctx, unsigned char *output, size_t size);

// Rand a list of int32
int ssl_random_rand_int_array(ssl_random_context *ctx, int *output, int count);

// Rand a list of Uint32
int ssl_random_rand_uint_array(ssl_random_context *ctx, unsigned int *output, int count);

// Release random context
void ssl_random_free(ssl_random_context *ctx);

// Shuffle unsigned char array
int ssl_random_shuffle_u8(u8 *list, int len);

// Rand a list of int32 (if ctx==NULL, then init a global ctx)
int ssl_random_list(ssl_random_context* ctx, int *list, int len);

// ERROR define
#define SSL_RANDOM_ERROR_HASH_ALGO_NOT_FOUND -0xF101
#define SSL_RANDOM_ERROR_NOT_INITIAL -0xF102
#define SSL_RANDOM_ERROR_NOT_SEEDED -0xF103
#define SSL_RANDOM_ERROR_OUT_SIZE_TO_LARGE -0xF104
#define SSL_RANDOM_ERROR_INVLIAD_SIZE -0xF105

// OPTION define
#define SSL_RANDOM_DISABLE_TIME 0x1
#define SSL_RANDOM_DISABLE_URANDOM 0x2
#define SSL_RANDOM_DISABLE_CPU_CYCLE 0x4
#define SSL_RANDOM_DISABLE_RAND_S 0x8
#define SSL_RANDOM_DISABLE_ANDROID_INFO 0x10
#define SSL_RANDOM_DISABLE_ANDROID_SENSOR 0x20

// OTHER define
#define SSL_RANDOM_MAX_BYTES_COUNT 1024
#define SSL_RANDOM_MAX_INT_COUNT (1024/4)

// ------ UTIL ------



#ifdef __cplusplus
}
#endif

#endif
