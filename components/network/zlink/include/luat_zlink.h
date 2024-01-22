#ifndef LUAT_ZLINK_H
#define LUAT_ZLINK_H

typedef void 	(*luat_zlink_output)(void *arg, const void *data, size_t len);

int luat_pcap_init(luat_zlink_output output, void *arg);
int luat_pcap_write(const void *data, size_t len);
int luat_pcap_push(const void *data, size_t len);

typedef struct luat_zlink_pkg
{
    uint8_t magic[4]; // ZINK
    uint8_t pkgid[4];   // 包id, 自增
    uint8_t flags[2];   // 标志位, 预留,当前为0
    uint8_t len[2];    // 仅计算len之后的数据
    uint8_t cmd0;    // 命令分类
    uint8_t cmd1;    // 具体命令
    uint8_t data[0];
}luat_zlink_pkg_t;

enum {
    // 基础指令
    LUAT_ZLINK_CMD_NONE = 0, // 空指令
    LUAT_ZLINK_CMD_VERSION, // 查询协议版本号
    LUAT_ZLINK_CMD_PING,    // 心跳包
    LUAT_ZLINK_CMD_PONG,    // 心跳包应答
    LUAT_ZLINK_CMD_REBOOT,  // 重启模块

    LUAT_ZLINK_CMD_MSG = 64,     // 日志输出, 用于调试

    // WLAN命令
    // WLAN 基础命令
    LUAT_ZLINK_CMD_WLAN_INIT = (1 << 8) + 1,
    LUAT_ZLINK_CMD_WLAN_STATUS,
    // WLAN设置命令
    LUAT_ZLINK_CMD_WLAN_SSID = (1 << 8) + 16,
    LUAT_ZLINK_CMD_WLAN_PASSWORD,
    LUAT_ZLINK_CMD_WLAN_MAC,

    // WLAN控制命令
    LUAT_ZLINK_CMD_WLAN_CONNECT = (1 << 8) + 32,
    LUAT_ZLINK_CMD_WLAN_DISCONNECT,
    LUAT_ZLINK_CMD_WLAN_SCAN,


    // MAC包收发指令, 只有发送和收到(ACK),应该不需要其他的吧
    LUAT_ZLINK_CMD_MACPKG_SEND = (2 << 8) + 1,
    LUAT_ZLINK_CMD_MACPKG_ACK,
};

#endif
