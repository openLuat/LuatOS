
#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#include "luat_libtcpip.h"
#include "luat_libtcpip_mqtt.h"

#include "luat_mcu.h"

#include "libemqtt.h"
#include <sys/socket.h>
#include <sys/socket.h>
#include <netinet/in.h>
// #include <netinet/ip.h> /* superset of previous */

#define PUB_MSG_MAGIC (0x1314)

#define LUAT_LOG_TAG "mqtt"
#include "luat_log.h"

#define MQTT_CMD_START             0x1
#define MQTT_CMD_HEART             0x2
#define MQTT_CMD_LOOP              0x3

#define MQTT_KEEPALIVE            240

static const mqtt_queue_msg_t MQTT_QUEUE_MSG_LOOP =  {MQTT_CMD_LOOP};
// static const mqtt_queue_msg_t MQTT_QUEUE_MSG_HEART = {MQTT_CMD_HEART};


LUAT_RET app_mqtt_ready(app_mqtt_ctx_t* ctx) {
    return ctx->conack_ready;
}

static int app_mqtt_close_socket(app_mqtt_ctx_t* ctx)
{
    ctx->conack_ready = LUAT_FALSE;
    ctx->tcp_opts->_close(ctx->socket_ctx);
    ctx->socket_ctx = NULL;
    return 0;
}

static int app_mqtt_send_packet(void* userdata, const void *buf, unsigned int count)
{
    app_mqtt_ctx_t* ctx = (app_mqtt_ctx_t*)userdata;
    LLOGD("ctx %p", ctx);
    LLOGD("send fd %d len %d", ctx->socket_ctx, count);
    return ctx->tcp_opts->_send(ctx->socket_ctx, buf, count, 0);
}

static int app_mqtt_read_packet(app_mqtt_ctx_t* ctx)
{
    // int ret = 0;
    int total_bytes = 0, bytes_rcvd, packet_length;
    // int socket_fd = ctx->socket_fd;
    uint8_t* packet_buff = ctx->packet_buffer;
    luat_libtcpip_opts_t* tcp_opts = ctx->tcp_opts;

    memset(packet_buff, 0, sizeof(MQTT_RECV_BUF_LEN_MAX));
    // XXX 替换原有posix的API调用
    // if((bytes_rcvd = recv(app_mqtt_socket_id, (app_mqtt_packet_buffer + total_bytes), MQTT_RECV_BUF_LEN_MAX, 0)) <= 0)
    if((bytes_rcvd = ctx->tcp_opts->_recv_timeout(ctx->socket_ctx, (packet_buff + total_bytes), 2, 0, 5)) <= 0)
    {
        // printf("%d, %d", bytes_rcvd, app_mqtt_socket_id);
        return MQTT_READ_TIMEOUT;
    }
    // printf("recv [len=%d] : %s", bytes_rcvd, app_mqtt_packet_buffer);
    total_bytes += bytes_rcvd; // Keep tally of total bytes
    if (total_bytes < 2) {
        // 少于2字节,那就肯定1个字节, 那我们再等15000ms
        if((bytes_rcvd = tcp_opts->_recv_timeout(ctx->socket_ctx, (packet_buff + total_bytes), 1, 0, 15000)) <= 0) {
            LLOGD("read package header timeout, close socket");
            app_mqtt_close_socket(ctx);
            return -1;
        }
        total_bytes += bytes_rcvd;
    }
    // if (app_mqtt_packet_buffer[1] & 0x80) {
        for (size_t i = 1; i < 5; i++)
        {
            if (packet_buff[i] & 0x80) {
                if((bytes_rcvd = tcp_opts->_recv_timeout(ctx->socket_ctx, (packet_buff + total_bytes), 1, 0, 15000)) <= 0) {
                    LLOGD("read package header timeout, close socket");
                    app_mqtt_close_socket(ctx);
                    return -1;
                }
                total_bytes += bytes_rcvd;
            }
            else {
                break;
            }
        }
    // }

    // now we have the full fixed header in app_mqtt_packet_buffer
    // parse it for remaining length and number of bytes
    uint16_t rem_len = mqtt_parse_rem_len(packet_buff);
    uint8_t rem_len_bytes = mqtt_num_rem_len_bytes(packet_buff);

    //packet_length = app_mqtt_packet_buffer[1] + 2; // Remaining length + fixed header length
    // total packet length = remaining length + byte 1 of fixed header + remaning length part of fixed header
    packet_length = rem_len + rem_len_bytes + 1;
    // LLOGD("packet_length %d total_bytes %d", packet_length, total_bytes);
    while(total_bytes < packet_length) // Reading the packet
    {
        // LLOGD("packet_length %d total_bytes %d", packet_length, total_bytes);
        // LLOGD("more data %d", packet_length - total_bytes);
        if((bytes_rcvd = tcp_opts->_recv_timeout(ctx->socket_ctx, (packet_buff + total_bytes), packet_length - total_bytes, 0, 2000)) <= 0)
            return -1;
        total_bytes += bytes_rcvd; // Keep tally of total bytes
    }
    // LLOGD("packet_length %d", packet_length);
    return packet_length;
}

static int app_mqtt_init_socket(app_mqtt_ctx_t* ctx)
{
    int flag = 1;
    // struct hostent *hp;

    // Create the socket
    if((ctx->socket_ctx = ctx->tcp_opts->_socket(PF_INET, SOCK_STREAM, 0)) < 0) {
        LLOGE("socket create error %p", ctx->socket_ctx);
        return -1;
    }
    // Disable Nagle Algorithm
    if (ctx->tcp_opts->_setsockopt(ctx->socket_ctx, IPPROTO_TCP, 0x01, (char *)&flag, sizeof(flag)) < 0){
        LLOGE("socket setsockopt error");
        app_mqtt_close_socket(ctx);
        return -2;
    }
    // Connect the socket
    // XXX 替换原有posix的API调用
    // if((connect(app_mqtt_socket_id, (struct sockaddr *)&socket_address, sizeof(socket_address))) < 0)
    // if((tcp_opts->_connect(app_mqtt_socket_id, (struct sockaddr *)&socket_address, sizeof(socket_address))) < 0)
    if(ctx->tcp_opts->_connect(ctx->socket_ctx, ctx->host, ctx->port) < 0){
        LLOGE("socket connect error");
        app_mqtt_close_socket(ctx);
        return -3;
    }
    // MQTT stuffs
    mqtt_set_alive(&ctx->broker, ctx->keepalive > 0 ? ctx->keepalive : 240);
    ctx->broker.userdata = ctx;
    ctx->broker.mqttsend = app_mqtt_send_packet;
    //LLOGD("socket id = %d", app_mqtt_socket_id);
    return 0;
}

static int app_mqtt_init_inner(app_mqtt_ctx_t* ctx)
{
    int ret = 0;

    // 将SUBACK的状态设置为未收到
    ctx->connect_ready = LUAT_FALSE;
    ctx->conack_ready = LUAT_FALSE;

#if 1
    LLOGD("step1: init mqtt lib.");
    LLOGD("mqtt client_id:%s", ctx->client_id);
    LLOGD("mqtt username: %s", ctx->username);
    LLOGD("mqtt password: %s", ctx->password);
    LLOGD("mqtt host:     %s", ctx->host);
    LLOGD("mqtt port:     %d", ctx->port);
#endif
    mqtt_init(&ctx->broker, ctx->client_id);
    mqtt_init_auth(&ctx->broker, ctx->username, ctx->password);
    LLOGD("step2: establishing TCP connection.");
    ret = app_mqtt_init_socket(ctx);
    if(ret){
        LLOGD("init_socket ret=%d", ret);
        return -4;
    }
    LLOGD("step3: establishing mqtt connection.");
    ret = mqtt_connect(&ctx->broker);
    if(ret){
        LLOGD("mqtt_connect ret=%d", ret);
        return -5;
    }
    ctx->connect_ready = LUAT_TRUE;

    return 0;
}

static int app_mqtt_msg_cb(app_mqtt_ctx_t* ctx) {
    const uint8_t *topic;
    const uint8_t *payload;

    uint16_t topic_len;
    uint16_t payload_len;
    uint8_t msg_tp = MQTTParseMessageType(ctx->packet_buffer);
    LLOGD("mqtt msg %02X", msg_tp);
    switch (msg_tp) {
        case MQTT_MSG_PUBLISH : {
            //ctx->keepalive_mark = 0;
            // uint8_t topic[128], *msg;
            topic_len = mqtt_parse_pub_topic_ptr(ctx->packet_buffer, &topic);
            LLOGD("recvd: topic len %d", topic_len);
            payload_len = mqtt_parse_pub_msg_ptr(ctx->packet_buffer, &payload);
            LLOGD("recvd: msg len %d", payload_len);

            // TODO 输出到回调函数, 例如uart
            LLOGD("topic %.*s", topic_len, topic);
            LLOGD("payload %.*s", payload_len, payload);
            // printf("%.*s",payload);
            //app_uart_write(payload, payload_len);

            #ifdef USE_OTA_MQTT
            if (0 != app_mqtt_ota_on_publish(topic, topic_len, payload, payload_len))
                break;
            #endif

            ctx->publish_cb(ctx, (char*)topic, topic_len, (char*)payload, payload_len);
            break;
        }
        case MQTT_MSG_CONNACK: {
            LLOGD("CONNACK %02X%02X%02X%02X",ctx->packet_buffer[0],ctx->packet_buffer[1],ctx->packet_buffer[2],ctx->packet_buffer[3]);
            if(ctx->packet_buffer[3] != 0x00)
            {
                LLOGD("CONNACK failed!");
                app_mqtt_close_socket(ctx);
                return -2;
            }
            ctx->conack_ready = LUAT_TRUE;
            LLOGD("step4: subscribe %s", ctx->sub_topic);
            int subscribe_state = mqtt_subscribe(&ctx->broker, ctx->sub_topic, NULL);
            if (subscribe_state<0)
            {
                LLOGD("Error(%d) on subscribe mqtt!", subscribe_state);
                app_mqtt_close_socket(ctx);
                return -1;
            }

            #ifdef USE_OTA_MQTT
            app_mqtt_ota_init(&ctx->broker);
            #endif
            break;
        }
        case MQTT_MSG_PINGRESP : {
            break;
        }
        case MQTT_MSG_SUBACK : {
            // 订阅应该成功吧
            LLOGD("SUBACK %02X%02X%02X%02X%02X",
                    ctx->packet_buffer[0],ctx->packet_buffer[1],
                    ctx->packet_buffer[2],ctx->packet_buffer[3],
                    ctx->packet_buffer[4]);
            break;
        }
        case MQTT_MSG_UNSUBACK : {
            break;
        }
        default : {
            break;
        }
    }
    return 0;
}

int app_mqtt_disconnect(app_mqtt_ctx_t *ctx) {
    return app_mqtt_close_socket(ctx);
}

static int app_mqtt_loop(app_mqtt_ctx_t *ctx)
{
    int ret = 0;
    int packet_length = 0;
    int counter = 0;

    counter++;
    packet_length = app_mqtt_read_packet(ctx);
    if(packet_length > 0)
    {
        //LLOGD("recvd Packet Header: 0x%x...", app_mqtt_packet_buffer[0]);
        ret = app_mqtt_msg_cb(ctx);
        if (ret != 0) {
            app_mqtt_close_socket(ctx);
            return -1;
        }
    }
    else if (packet_length == MQTT_READ_TIMEOUT)
    {
        // nop
    }
    else if(packet_length == -1)
    {
        LLOGD("mqtt error:(%d), stop mqtt!", packet_length);
        app_mqtt_close_socket(ctx);
        return -1;
    }
    return 0;
}

extern int app_mqtt_authentication_get(app_mqtt_ctx_t* ctx);

app_mqtt_ctx_t* app_mqtt_configure_create(void) {
    app_mqtt_ctx_t* ctx = luat_heap_malloc(sizeof(app_mqtt_ctx_t));
    if (ctx == NULL) {
        LLOGE("out of memory when mallo app_mqtt_ctx_t");
        return NULL;
    }
    memset(ctx, 0, sizeof(app_mqtt_ctx_t));

    ctx->keepalive = 240;
    ctx->port = 1883;
    ctx->keep_run = 1;

    luat_queue_create(&ctx->msg_queue, 128, 4);

    return ctx;
}

void app_mqtt_task(void *p)
{
    int ret = 0;
    mqtt_queue_msg_t *msg;
	app_mqtt_pub_data_t* pmsg;
    // uint32_t retry_time = 2;
    app_mqtt_ctx_t* ctx = (app_mqtt_ctx_t*)p;

    msg = &MQTT_QUEUE_MSG_LOOP;

    // 计算ping的时机
    // uint64_t last_pkg_ticks = 0;
    size_t hz = luat_mcu_hz();
    uint64_t tick_used;

    while (ctx->keep_run)
    {
        if (ctx->connect_ready == LUAT_FALSE)
        {
            ret = app_mqtt_init_inner(ctx);
            if (ret) {
                LLOGD("mqtt init fail %d", ret);
                if (ctx->keep_run) {
                    luat_timer_mdelay(ctx->reconnet_delay);
                    continue; // 开始下一轮重连循环
                }
                else {
                    LLOGD("mqtt exit");
                    break;
                }
            }
            ctx->last_pkg_tick = luat_mcu_ticks();
        }

        ret = luat_queue_recv(&ctx->msg_queue, &msg, sizeof(mqtt_queue_msg_t), 1);
        if (!ret)
        {
            switch((uint32_t)msg->type)
            {
            case MQTT_CMD_LOOP:
                // LLOGD("MQTT_CMD_LOOP");
                app_mqtt_loop(ctx);
                break;
            case PUB_MSG_MAGIC:
                // ctx->keepalive_mark = 0;
                ctx->last_pkg_tick = luat_mcu_ticks();
                pmsg = msg;
                ret = mqtt_publish_with_qos(&ctx->broker, pmsg->topic, pmsg->data, pmsg->data_len, pmsg->retain, pmsg->qos, NULL);
                LLOGD("app_mqtt_pub_data_t free %p", msg);
                luat_heap_free(msg);
                break;
            default :
                LLOGD("unknow mqtt queue msg %08X", msg->type);
                break;
            }
        }
        else {
            app_mqtt_loop(ctx);
        }
        
        tick_used = luat_mcu_ticks() - ctx->last_pkg_tick;
        if (tick_used > (ctx->keepalive * hz  / 3)) {
            mqtt_ping(&ctx->broker);
            ctx->last_pkg_tick = luat_mcu_ticks();
        }
    }
}

// 发送数据到mqtt
int app_mqtt_publish(app_mqtt_ctx_t* ctx, const char* topic, char* data, size_t len, int qos, int retain) {
    // 未连接, 就不准发数据
    if (ctx->conack_ready != LUAT_TRUE) {
        LLOGD("mqtt not ready yet");
        return -1;
    }

    app_mqtt_pub_data_t* msg = luat_heap_malloc(sizeof(app_mqtt_pub_data_t) + len - 4);
    LLOGD("app_mqtt_pub_data_t malloc %p", msg);
    if (msg == NULL) {
        LLOGD("out of memory app_mqtt_publish!!!");
        return -1;
    }
    msg->magic = PUB_MSG_MAGIC;
    msg->qos = 1;
    msg->retain = retain;
    msg->data_len = len;
    memcpy(msg->data, data, len);
    if (topic)
        memcpy(msg->topic, topic, strlen(topic) + 1);
    else
        memcpy(msg->topic, ctx->pub_topic, strlen(ctx->pub_topic) + 1);
    luat_queue_send(&ctx->msg_queue, msg, sizeof(app_mqtt_pub_data_t), 1);
    return 0;
}
