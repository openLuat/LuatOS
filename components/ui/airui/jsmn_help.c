#include "luat_base.h"

#include "luat_airui.h"
#include <stdlib.h>

int jsmn_skip_object(jsmntok_t *tok, size_t *cur) {
    size_t objlen = tok[*cur].size;

    *cur = *cur + 1;

    for (size_t i = 0; i < objlen; i++)
    {
        // 首先跳过key
        *cur = *cur + 1;
        jsmn_skip_entry(tok, cur);
    }

    return 0;
}

int jsmn_skip_array(jsmntok_t *tok, size_t *cur) {
    size_t objlen = tok[*cur].size;

    *cur = *cur + 1;
    
    for (size_t i = 0; i < objlen; i++)
    {
        jsmn_skip_entry(tok, cur);
    }
    return 0;
}

int jsmn_skip_entry(jsmntok_t *tok, size_t *cur) {
    if (tok[*cur].type == JSMN_STRING || tok[*cur].type == JSMN_PRIMITIVE) {
        *cur = *cur + 1;
        return 0;
    }
    if (tok[*cur].type == JSMN_OBJECT) {
        jsmn_skip_object(tok, cur);
    }
    if (tok[*cur].type == JSMN_ARRAY) {
        jsmn_skip_array(tok, cur);
    }
    return 0;
}

int jsmn_find_by_key(const char* data, const char* key, jsmntok_t *tok, size_t pos) {
    if (tok[pos].type != JSMN_OBJECT) {
        return -1;
    }
    size_t objlen = tok[pos].size;
    if (objlen == 0) {
        return -1;
    }
    pos ++;
    size_t keylen = strlen(key);
    for (size_t i = 0; i < objlen; i++)
    {
        if (tok[pos].end - tok[pos].start == keylen) {
            if (!memcmp(&data[tok[pos].start], key, keylen)) {
                return pos;
            }
        }
        pos ++;
        jsmn_skip_entry(tok, &pos);
    }
    return -1;
}

int jsmn_toint(const char* data, jsmntok_t *tok) {
    if (tok->type != JSMN_PRIMITIVE) {
        return 0;
    }
    int start = tok->start;
    int end = tok->end;
    if (end - start > 15) {
        return 0;
    }
    char buff[16] = {0};
    memcpy(buff, &data[start], end - start);
    return atoi(buff);
}

void jsmn_get_string(const char* data, jsmntok_t *tok, int pos, c_str_t *str) {
    str->len = tok[pos].end - tok[pos].start;
    str->ptr = &data[tok[pos].start];
}


void jsmn_kv_get(const char* data, jsmntok_t *tok, int pos, const char* key, c_str_t *str) {
    int pos2 = jsmn_find_by_key(data, key, tok, pos);
    if (pos2 < 1) {
        str->len = 0;
        return;
    }
    if (tok[pos2].type == JSMN_ARRAY || tok[pos2].type == JSMN_ARRAY) {
        str->len = 0;
        return;
    }

    str->len = tok[pos2].end - tok[pos2].start;
    str->ptr = &data[tok[pos2].start];
}
