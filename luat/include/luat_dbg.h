
#ifndef LUAT_DBG
#define LUAT_DBG
#include "luat_base.h"


#define BP_LINE_COUNT (32)
#define BP_SOURCE_LEN (16)

typedef struct line_bp
{
    uint16_t id;
    uint16_t linenumber;
    char source[BP_SOURCE_LEN];
}line_bp_t;

typedef void (*luat_dbg_cb) (void* params);

void luat_dbg_set_hook_state(int state);
int luat_dbg_get_hook_state(void);

void luat_dbg_breakpoint_add(const char* source, int linenumber);
void luat_dbg_breakpoint_del(size_t index);
void luat_dbg_breakpoint_clear(const char* source);

void luat_dbg_set_runcb(luat_dbg_cb cb, void* params);

void luat_dbg_backtrace(void* params);
void luat_dbg_vars(void* params);

#endif
