
#include "luat_base.h"
#include "luat_crypto.h"
#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"
#include <stdlib.h>

int luat_crypto_trng(char* buff, size_t len) {
    for (size_t i = 0; i < len; i++)
    {
        buff[i] = (char) rand();
    }
    return 0;
}
