// ============================================================
// Public interface:
// ============================================================

#ifndef TJE_HEADER_GUARD
#define TJE_HEADER_GUARD
#include "bsp_common.h"
#define TJEI_BUFFER_SIZE 1024

#ifdef _WIN32

#include <windows.h>
#ifndef snprintf
#define snprintf sprintf_s
#endif
// Not quite the same but it works for us. If I am not mistaken, it differs
// only in the return value.

#endif

#if 0

#define tje_log DBG

#else  // NDEBUG
#define tje_log(...)
#endif  // NDEBUG





#ifdef __cplusplus
extern "C"
{
#endif

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"  // We use {0}, which will zero-out the struct.
#pragma GCC diagnostic ignored "-Wmissing-braces"
#pragma GCC diagnostic ignored "-Wpadded"
#endif

// - tje_encode_with_func -
//
// Usage
//  Same as tje_encode_to_file_at_quality, but it takes a callback that knows
//  how to handle (or ignore) `context`. The callback receives an array `data`
//  of `size` bytes, which can be written directly to a file. There is no need
//  to free the data.

typedef void tje_write_func(void* context, void* data, int size);
void *jpeg_encode_init(tje_write_func* func, void* context, uint8_t quality, uint32_t width, uint32_t height, uint8_t src_num_components);
void jpeg_encode_run(void *ctx, uint8_t *src_data);
void jpeg_encode_end(void *ctx);
// ============================================================
//
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif


#ifdef __cplusplus
}  // extern C
#endif
#endif
