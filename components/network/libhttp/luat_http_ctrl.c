
#include "luat_base.h"

#include "luat_rtos.h"
#include "luat_debug.h"

#include "luat_mem.h"

#include "luat_str.h"
#ifdef __LUATOS__
#include "luat_msgbus.h"
#endif

#include "luat_network_adapter.h"
#include "luat_http.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

extern void DBG_Printf(const char* format, ...);
extern void luat_http_client_onevent(luat_http_ctrl_t *http_ctrl, int error_code, int arg);
#undef LLOGD
#ifdef __LUATOS__
#define LLOGD(format, ...) do {if (http_ctrl->debug_onoff) {luat_log_log(LUAT_LOG_DEBUG, LUAT_LOG_TAG, format, ##__VA_ARGS__);}} while(0)
#else
#undef LLOGE
#undef LLOGI
#undef LLOGW
#define LLOGI(format, ...)
#define LLOGW(format, ...)
#ifdef LUAT_LOG_NO_NEWLINE
#define LLOGD(x,...)	do {if (http_ctrl->debug_onoff) {DBG_Printf("%s %d:"x, __FUNCTION__,__LINE__,##__VA_ARGS__);}} while(0)
#define LLOGE(x,...) DBG_Printf("%s %d:"x, __FUNCTION__,__LINE__,##__VA_ARGS__)
#else
#define LLOGD(x,...)	do {if (http_ctrl->debug_onoff) {DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##__VA_ARGS__);}} while(0)
#define LLOGE(x,...) DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##__VA_ARGS__)
#endif

#endif

#include "luat_rtos.h"

typedef struct luat_http_idg_entry {
    uint32_t idg;
    luat_http_ctrl_t *http_ctrl;
    struct luat_http_idg_entry *next;
} luat_http_idg_entry_t;

static luat_rtos_mutex_t idg_mutex;
static uint32_t idg_counter = 1;
static luat_http_idg_entry_t *idg_head = NULL;

uint32_t luat_http_idg_register(luat_http_ctrl_t *http_ctrl) {
    if (http_ctrl == NULL) {
        return 0;
    }
    if (idg_mutex == NULL) {
        luat_rtos_mutex_create(&idg_mutex);
    }
    // 分配一个idg
    luat_rtos_mutex_lock(idg_mutex, 0);
    uint32_t idg = idg_counter++;
    // idg不能为0，0表示无效, 不能与未释放的idg重复
    while (1) {
        if (idg == 0) {
            idg = idg_counter++;
            continue;
        }
        int found = 0;
        luat_http_idg_entry_t *entry = idg_head;
        while (entry) {
            if (entry->idg == idg) {
                found = 1;
                break;
            }
            entry = entry->next;
        }
        if (!found) {
            break;
        }
        idg = idg_counter++;
    }
    http_ctrl->idg = idg;
    // 记录idg和http_ctrl的映射关系
    luat_http_idg_entry_t *new_entry = (luat_http_idg_entry_t *)luat_heap_malloc(sizeof(luat_http_idg_entry_t));
    if (new_entry != NULL) {
        new_entry->idg = idg;
        new_entry->http_ctrl = http_ctrl;
        new_entry->next = idg_head;
        idg_head = new_entry;
    }
    LLOGD("register idg %d for http_ctrl %p", idg, http_ctrl);
    luat_rtos_mutex_unlock(idg_mutex);
    return idg;
}

luat_http_ctrl_t* luat_http_idg_get(uint32_t idg) {
    // LLOGD("get http_ctrl for idg %d", idg);
    if (idg == 0) {
        return NULL;
    }
    luat_rtos_mutex_lock(idg_mutex, 0);
    // 查找idg对应的http_ctrl
    luat_http_idg_entry_t *entry = idg_head;
    while (entry) {
        if (entry->idg == idg) {
            luat_rtos_mutex_unlock(idg_mutex);
            return entry->http_ctrl;
        }
        entry = entry->next;
    }
    luat_rtos_mutex_unlock(idg_mutex);
    return NULL;
}

int luat_http_idg_unreg(uint32_t idg) {
    if (idg == 0) {
        return -1;
    }
    // LLOGD("unreg idg %d", idg);
    luat_rtos_mutex_lock(idg_mutex, 0);
    // 查找idg对应的http_ctrl
    luat_http_idg_entry_t *entry = idg_head;
    luat_http_idg_entry_t *prev = NULL;
    while (entry) {
        if (entry->idg == idg) {
            if (prev) {
                prev->next = entry->next;
            } else {
                idg_head = entry->next;
            }
            luat_heap_free(entry);
            luat_rtos_mutex_unlock(idg_mutex);
            return 0;
        }
        prev = entry;
        entry = entry->next;
    }
    luat_rtos_mutex_unlock(idg_mutex);
    return -1;
}
