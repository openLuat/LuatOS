/* config.h - LuatOS platform configuration for libspeex
 * Replaces the autoconf-generated config.h
 */
#ifndef SPEEX_LIB_CONFIG_H
#define SPEEX_LIB_CONFIG_H

/* Use fixed-point arithmetic */
#ifndef FIXED_POINT
#define FIXED_POINT 1
#endif

/* Disable float API */
#define DISABLE_FLOAT_API 1

/* We have stdint.h */
#define HAVE_STDINT_H 1

/* We have stdlib.h */
#define HAVE_STDLIB_H 1

/* We have string.h */
#define HAVE_STRING_H 1

/* We have memory.h */
#define HAVE_MEMORY_H 1

/* We have alloca (via malloc instead) */
/* #undef HAVE_ALLOCA_H */

/* Use KISS FFT for smallft */
#define USE_KISS_FFT 1

/* Speex version - let arch.h define individual version macros */
/* Do NOT define SPEEX_VERSION here, arch.h will define all version macros */

#endif /* SPEEX_LIB_CONFIG_H */
