#ifndef LUAT_AIRLINK_RESULT_H
#define LUAT_AIRLINK_RESULT_H

#include "luat_airlink.h"

// =====================================================================
// 异步结果回调机制 (result_reg)
// =====================================================================

struct luat_airlink_result_reg;
typedef void (*airlink_result_exec)(struct luat_airlink_result_reg *reg, luat_airlink_cmd_t* cmd);

typedef struct luat_airlink_result_reg
{
    uint64_t tm;
    uint64_t id;
    void* userdata;
    void* userdata2;
    airlink_result_exec exec;
    airlink_result_exec cleanup;
} luat_airlink_result_reg_t;

// 注册等待某个 pkgid 的结果回调
int luat_airlink_result_reg(luat_airlink_result_reg_t* reg);

// 注销 result slot (用于超时清理)
// 返回 0: 成功清理; -1: slot 已被回调消费
int luat_airlink_result_unreg(uint64_t id);

#endif /* LUAT_AIRLINK_RESULT_H */
