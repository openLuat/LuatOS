#ifndef LUAT_ZTT_H
#define LUAT_ZTT_H

#include "stdint.h"
#include "inttypes.h"

typedef struct luat_ztt
{
    char *key;
    size_t value_len;
    char *value;
    void* next;
}luat_ztt_t;

luat_ztt_t* ztt_create(const char* type);
luat_ztt_t* ztt_addf(luat_ztt_t* ztt_head, const char* key, const char* fmt, ...);
luat_ztt_t* ztt_add(luat_ztt_t* ztt, const char* key, const char* value, size_t value_len);
int ztt_commit(luat_ztt_t* ztt);

#endif
