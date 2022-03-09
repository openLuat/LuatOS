#ifndef LUAT_LIBTCPIP_MQTT_H
#define LUAT_LIBTCPIP_MQTT_H

#include "luat_libtcpip.h"
#include "libemqtt.h"

#define MQTT_READ_TIMEOUT        (-1000)

#define MQTT_READ_TIME_SEC         15
#define MQTT_READ_TIME_US          0

#define MQTT_RECV_BUF_LEN_MAX      4096

typedef int (*mqtt_publish_cb)(void* userdata, const char* topic, size_t topic_len, const char* payload, size_t payload_len);

// 异步发送mqtt publish数据对应的结构体
typedef struct app_mqtt_pub_data
{
    uint32_t magic; // 与 mqtt_queue_msg_t 相同的结构
    int qos;
    int retain;
    //size_t topic_len;
    size_t data_len;
    char topic[192];
    char data[4];
}app_mqtt_pub_data_t;

typedef struct app_mqtt_ctx
{
    char client_id[192];
    char password[192];
    char username[192];
    char host[192];
    int  port;
    char pub_topic[192];
    char sub_topic[192];
    size_t keepalive;
    mqtt_broker_handle_t broker;
    luat_libtcpip_opts_t* tcp_opts;
    uint8_t packet_buffer[MQTT_RECV_BUF_LEN_MAX];
    int conack_ready; // 判断是否收到CONACK
    int connect_ready; // 判断连接是否已经就绪
    int socket_fd;
    int keepalive_mark;
    mqtt_publish_cb publish_cb;
}app_mqtt_ctx_t;


typedef struct mqtt_queue_msg {
    uint32_t type;
}mqtt_queue_msg_t;

#endif

