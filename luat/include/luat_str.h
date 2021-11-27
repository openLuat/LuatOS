
#ifndef LUAT_STR_H
#define LUAT_STR_H
#include "string.h"

void luat_str_tohex(char* str, size_t len, char* buff);
void luat_str_fromhex(char* str, size_t len, char* buff);

int luat_str_base64_encode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );
int luat_str_base64_decode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );

#endif
