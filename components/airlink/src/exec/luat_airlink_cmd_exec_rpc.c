/*
 * AirLink RPC 服务端命令处理器
 *
 * 处理来自对端的 cmd 0x30 (AIRLINK_CMD_RPC):
 *   线格式: [pkgid:8][rpc_id:2][msg_type:1][payload:N]
 *
 * REQUEST (msg_type=0): 解码 → handler → 编码 → cmd 0x08 发回结果
 *   响应 buff: [req_pkgid:8][result_code:2][resp payload]
 *   (luat_airlink_result_send 会在前面加 8 字节 new_pkgid)
 *
 * NOTIFY (msg_type=1): 传给 notify_handler，不发任何响应
 */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_mem.h"

#ifdef LUAT_USE_AIRLINK_RPC

#define LUAT_LOG_TAG "airlink.rpc"
#include "luat_log.h"

// 声明 dispatch 函数 (在 luat_airlink_rpc.c 中实现)
extern int luat_airlink_rpc_dispatch(uint16_t rpc_id,
                                      const uint8_t* req, uint16_t req_len,
                                      uint8_t* resp, uint16_t resp_size, uint16_t* resp_len);

extern int luat_airlink_rpc_nb_dispatch(uint16_t rpc_id, uint8_t msg_type,
                                         const uint8_t* req_bytes, uint16_t req_len,
                                         uint8_t* resp_bytes, uint16_t resp_size, uint16_t* resp_len);

#define RPC_RESP_BUF_SIZE  512  // 默认响应缓冲区大小
// 最小线格式长度: pkgid(8) + rpc_id(2) + msg_type(1) = 11
#define RPC_WIRE_HDR_LEN  11

int luat_airlink_cmd_exec_rpc(luat_airlink_cmd_t* cmd, void* userdata) {
    if (cmd->len < RPC_WIRE_HDR_LEN) {
        LLOGE("rpc exec: cmd 太短 %d (至少需要 pkgid(8)+rpc_id(2)+msg_type(1))", cmd->len);
        return -1;
    }

    uint64_t req_pkgid = 0;
    uint16_t rpc_id    = 0;
    uint8_t  msg_type  = 0;
    memcpy(&req_pkgid, cmd->data,      8);
    memcpy(&rpc_id,    cmd->data + 8,  2);
    msg_type = cmd->data[10];

    const uint8_t* req_payload = cmd->data + RPC_WIRE_HDR_LEN;
    uint16_t req_len = (cmd->len > RPC_WIRE_HDR_LEN)
                       ? (uint16_t)(cmd->len - RPC_WIRE_HDR_LEN) : 0;

    // NOTIFY: 传给 notify_handler，不发任何响应
    if (msg_type == AIRLINK_RPC_MSG_TYPE_NOTIFY) {
        uint16_t dummy_len = 0;
        // 先尝试 nanopb typed 表
        int rc = luat_airlink_rpc_nb_dispatch(rpc_id, msg_type,
                                               req_payload, req_len,
                                               NULL, 0, &dummy_len);
        if (rc == -404) {
            // 再尝试 raw 表 (notify 无 response，raw handler 返回值忽略)
            luat_airlink_rpc_dispatch(rpc_id, req_payload, req_len,
                                      NULL, 0, &dummy_len);
        }
        return 0;
    }

    // REQUEST: 分配响应缓冲区 [req_pkgid:8][result_code:2][resp payload]
    uint8_t* resp_buf = (uint8_t*)luat_heap_malloc(8 + 2 + RPC_RESP_BUF_SIZE);
    if (resp_buf == NULL) {
        LLOGE("rpc exec: malloc resp_buf failed");
        uint8_t err_buf[10];
        memcpy(err_buf, &req_pkgid, 8);
        int16_t ec = -500;
        memcpy(err_buf + 8, &ec, 2);
        luat_airlink_result_send(err_buf, 10);
        return -1;
    }

    uint16_t resp_len    = 0;
    uint8_t* resp_payload = resp_buf + 10;
    int rc = -404;

    // 先尝试 nanopb typed 表
    rc = luat_airlink_rpc_nb_dispatch(rpc_id, msg_type,
                                       req_payload, req_len,
                                       resp_payload, RPC_RESP_BUF_SIZE, &resp_len);
    if (rc == -404) {
        // 再尝试原始字节表
        resp_len = 0;
        rc = luat_airlink_rpc_dispatch(rpc_id, req_payload, req_len,
                                        resp_payload, RPC_RESP_BUF_SIZE, &resp_len);
    }

    memcpy(resp_buf, &req_pkgid, 8);
    int16_t result_code = (int16_t)rc;
    memcpy(resp_buf + 8, &result_code, 2);

    if (rc != 0) {
        resp_len = 0;
        if (rc == -404) {
            LLOGW("rpc exec: 未找到 rpc_id=0x%04X 的 handler", rpc_id);
        }
    }

    luat_airlink_result_send(resp_buf, (size_t)(10 + resp_len));
    luat_heap_free(resp_buf);
    return 0;
}

#endif /* LUAT_USE_AIRLINK_RPC */
