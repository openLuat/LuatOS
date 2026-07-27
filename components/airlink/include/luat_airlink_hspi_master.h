/*
 * AirLink XT804 HSPI Master API
 *
 * 主机 MCU 使用此 API 与 XT804 从机（Air103/Air601）通信。
 * 由 LUAT_USE_AIRLINK_HSPI_MASTER 宏控制，仅在 XT804 作为从机时主机侧编译。
 *
 * 平台适配: MCU 需要提供两个回调函数:
 *   int  xt804_hspi_spi_xfer(const uint8_t *tx, uint8_t *rx, uint16_t len);
 *   uint32_t xt804_hspi_get_tick_ms(void);
 */
#ifndef LUAT_AIRLINK_HSPI_MASTER_H
#define LUAT_AIRLINK_HSPI_MASTER_H

#include <stdint.h>

// 检查从机状态
int xt804_hspi_check_status(int *data_rdy, int *cmd_rdy);

// 使能主机侧 INT 中断接收（SPI 初始化后调用一次）
int xt804_hspi_enable_host_int(void);

// 从机是否在线（连续 rd02=0 超过阈值判离线，发送成功自动恢复）
int xt804_hspi_peer_online(void);

// 发送命令 + 等待响应
// resp_len: [in]buffer大小 [out]实际长度
int xt804_hspi_send_cmd(uint16_t cmd_id, const uint8_t *payload, uint16_t payload_len,
                         uint8_t *resp, uint16_t *resp_len, uint32_t timeout_ms);

// 仅读取响应 (用于异步通知如 0x0311/0x0410)
int xt804_hspi_read_response(uint8_t *resp, uint16_t *resp_len,
                              uint16_t *cmd_id, uint32_t timeout_ms);

// 中断驱动读取 (按手册 10.4.3.3: 读 STTS → 读 LEN → 读数据 → 清 STTS)
// 无超时参数 — 调用前需确保 INT 已触发 (由 ISR 通知触发)
// 返回 0=成功, -1=无数据, -2=校验失败
int xt804_hspi_read_data_intr(uint8_t *resp, uint16_t *resp_len, uint16_t *cmd_id);

#endif
