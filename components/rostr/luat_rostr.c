#include "luat_base.h"

#include "luat_rostr.h"
#include "lstring.h"
#include "lgc.h"

#define LUAT_LOG_TAG "rostr"
#include "luat_log.h"

extern const luat_rostr_short_t rostr_shr_len0;
extern const luat_rostr_short44_t rostr_shr_datas[];

GCObject* luat_rostr_get_gc(const char *val_str, size_t len) {
    if (len == 0) {
        // LLOGD("返回空字符串的rostr指针");
        return (GCObject*)&rostr_shr_len0;
    }
    const luat_rostr_short44_t* ptr = rostr_shr_datas;
    while (ptr->str.shrlen) {
        if (ptr->str.shrlen == len && strncmp(val_str, ptr->data, len) == 0) {
            // LLOGD("返回rostr指针 %p %s", ptr, ptr->data);
            return (GCObject*)ptr;
        }
        ptr++;
    }
    return NULL;
}
TString* luat_rostr_get(const char *val_str, size_t len) {
    GCObject* gc = luat_rostr_get_gc(val_str, len);
    if (gc == NULL) {
        return NULL;
    }
    return gco2ts(gc);
}
