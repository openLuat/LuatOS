#ifndef LUAT_WEBC_CODEC_H
#define LUAT_WEBC_CODEC_H

#include "luat_base.h"

int luat_webc_decode_payload(const char* encoding, const char* payload, uint8_t** out_data, size_t* out_len, const char** out_errmsg);
char* luat_webc_encode_hex_escape(const uint8_t* data, size_t len);
char* luat_webc_encode_utf8_display(const uint8_t* data, size_t len);

#endif
