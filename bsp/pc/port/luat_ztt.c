
#include "uv.h"
#include "luat_base.h"
#include "luat_ztt.h"
#include "luat_malloc.h"
#include "printf.h"


#define LUAT_LOG_TAG "ztt"
#include "luat_log.h"

luat_ztt_t* ztt_create(const char* type) {
    return ztt_add(NULL, "type", type, strlen(type));
}

luat_ztt_t* ztt_addf(luat_ztt_t* ztt_head, const char* key, const char* _fmt, ...) {
    char* buff = luat_heap_malloc(4096);
    if (buff == NULL)
        return NULL;
    memset(buff, 0, 4096);
    va_list args;
    va_start(args, _fmt);
    int len = vsnprintf_(buff, 4096 - 1, _fmt, args);
    va_end(args);
    if (len <= 0) {
        luat_heap_free(buff);
        return NULL;
    }
    luat_ztt_t* ret = ztt_add(ztt_head, key, buff, len);
    luat_heap_free(buff);
    return ret;
}

luat_ztt_t* ztt_add(luat_ztt_t* ztt_head, const char* key, const char* value, size_t value_len) {
    luat_ztt_t* ztt = luat_heap_malloc(sizeof(luat_ztt_t));
    if (ztt == NULL) {
        return ztt_head;
    }
    memset(ztt, 0, sizeof(luat_ztt_t));
    ztt->key = luat_heap_malloc(strlen(key) + 1);
    ztt->value = luat_heap_malloc(value_len);
    if (ztt->value == NULL || ztt->key == NULL) {
        if (ztt->value)
            luat_heap_free(ztt->value);
        if (ztt->key)
            luat_heap_free(ztt->key);
        luat_heap_free(ztt);
        return ztt_head;
    }
    memcpy(ztt->key, key, strlen(key) + 1);
    memcpy(ztt->value, value, value_len);
    ztt->value_len = value_len;
    if (ztt_head == NULL) {
        return ztt;
    }
    luat_ztt_t* head = ztt_head;
    while (1) {
        if (head->next) {
            head = head->next;
            continue;
        }
        head->next = ztt;
        break;
    }
    return ztt_head;

}


int ztt_commit(luat_ztt_t* ztt) {
    if (ztt == NULL)
        return -1;
    luat_ztt_t* head = ztt;
    size_t len = 0;
    char* buff = luat_heap_malloc(4);
    if (buff == NULL) {
        // TODO clear ztt;
        return -2;
    }
    while (head != NULL) {
        buff = luat_heap_realloc(buff, len + head->value_len + 2);
        if (buff == NULL) {
            // TODO clear ztt;
            return -3;
        }
        memcpy(buff + len, head->value, head->value_len);
        len += head->value_len;
        buff[len] = ',';
        len ++;
        luat_ztt_t* tmp = head;
        head = head->next;
        luat_heap_free(tmp->key);
        luat_heap_free(tmp->value);
        luat_heap_free(tmp);
    }
    buff[len] = '0';

    // TODO 发送UDP/接收UDP
    return 0;
}

