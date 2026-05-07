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

// 按 id 查找 result slot 并触发 exec 回调 (供 pong 等命令的 handler 调用)
// 返回 0: 找到并触发; -1: 未找到
int luat_airlink_result_dispatch(uint64_t id, luat_airlink_cmd_t* cmd);

#endif /* LUAT_AIRLINK_RESULT_H */
