/*
 *  Copyright 2014-2022 The GmSSL Project. All Rights Reserved.
 *
 *  Licensed under the Apache License, Version 2.0 (the License); you may
 *  not use this file except in compliance with the License.
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 */


#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <gmssl/rand.h>
#include <gmssl/error.h>

extern int luat_crypto_trng(char* buff, size_t len);

int rand_bytes(uint8_t *buf, size_t len)
{
	luat_crypto_trng((char*)buf, len);
	return 1;
}
