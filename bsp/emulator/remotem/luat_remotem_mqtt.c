/*
通信层,基于MQTT
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "MQTTAsync.h"
// #include "MQTTClient.h"
#include "luat_remotem.h"

#if !defined(_WIN32)
#include <unistd.h>
#else
#include <windows.h>
#endif

#if defined(_WRS_KERNEL)
#include <OsWrapper.h>
#endif

// #define ADDRESS     "tcp://broker-cn.emqx.io:1883"
// #define CLIENTID    "123TTTZZVVV"
// #define SUB_TOPIC       "/sys/luatos/em/test/down"
// #define PUB_TOPIC       "/sys/luatos/em/test/up"
// #define PAYLOAD     "Hello World!"
// #define QOS         1
#define TIMEOUT     10000L

// int finished = 0;

static MQTTAsync client;
static boolean mqtt_client_ready;
static boolean mqtt_client_suback_ready;
static MQTTAsync_connectOptions conn_opts = MQTTAsync_connectOptions_initializer;
static boolean mqtt_client_isconneting;

void luat_remotem_putbuff(char* buff, size_t len);

extern luat_remotem_ctx_t rctx;

static void mqtt_uplink_cb(char* buff, size_t len) {
	MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;
	MQTTAsync_message pubmsg = MQTTAsync_message_initializer;
	pubmsg.payload = buff;
    pubmsg.payloadlen = len;
    pubmsg.qos = 1;
    pubmsg.retained = 0;
    int rc = 0;
    if ((rc = MQTTAsync_sendMessage(client, rctx.mqtt.topic_uplink, &pubmsg, NULL)) != MQTTASYNC_SUCCESS)
    {
    	printf("Failed to publish message, return code %d\n", rc);
    	rc = EXIT_FAILURE;
    }
}

void connlost(void *context, char *cause)
{
	MQTTAsync client = (MQTTAsync)context;
	MQTTAsync_connectOptions conn_opts = MQTTAsync_connectOptions_initializer;
	int rc;

	printf("\nConnection lost\n");
	printf("     cause: %s\n", cause);

	Sleep(2000);

	printf("Reconnecting\n");
	conn_opts.keepAliveInterval = 20;
	conn_opts.cleansession = 1;
	if ((rc = MQTTAsync_connect(client, &conn_opts)) != MQTTASYNC_SUCCESS)
	{
		printf("Failed to start connect, return code %d\n", rc);
 		// finished = 1;
	}
}

void onDisconnectFailure(void* context, MQTTAsync_failureData* response)
{
	printf("Disconnect failed\n");
	// finished = 1;
}

void onDisconnect(void* context, MQTTAsync_successData* response)
{
	printf("Successful disconnection\n");
	// finished = 1;
}

void onSendFailure(void* context, MQTTAsync_failureData* response)
{
	MQTTAsync client = (MQTTAsync)context;
	MQTTAsync_disconnectOptions opts = MQTTAsync_disconnectOptions_initializer;
	int rc;

	printf("Message send failed token %d error code %d\n", response->token, response->code);
	opts.onSuccess = onDisconnect;
	opts.onFailure = onDisconnectFailure;
	opts.context = client;
	if ((rc = MQTTAsync_disconnect(client, &opts)) != MQTTASYNC_SUCCESS)
	{
		printf("Failed to start disconnect, return code %d\n", rc);
		exit(EXIT_FAILURE);
	}
}

void onSend(void* context, MQTTAsync_successData* response)
{
	
}


void onConnectFailure(void* context, MQTTAsync_failureData* response)
{
	printf("Connect failed, rc %d\n", response ? response->code : 0);
	// finished = 1;
}

void onSubscribe(void* context, MQTTAsync_successData* response)
{
	// printf("Subscribe succeeded\n");
	// subscribed = 1;
	mqtt_client_suback_ready = TRUE;
}

void onSubscribeFailure(void* context, MQTTAsync_failureData* response)
{
	printf("Subscribe failed, rc %d\n", response->code);
	// finished = 1;
}

void onConnect(void* context, MQTTAsync_successData* response)
{
	MQTTAsync client = (MQTTAsync)context;
	MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;
	int rc;

	printf("mqtt connect ok\n");
	opts.onSuccess = onSubscribe;
	opts.onFailure = onSubscribeFailure;
	opts.context = client;
	rc = MQTTAsync_subscribe(client, rctx.mqtt.topic_downlink, 1, &opts);
}

int messageArrived(void* context, char* topicName, int topicLen, MQTTAsync_message* m)
{
	luat_remotem_putbuff((char*)m->payload, m->payloadlen);
	return 1;
}

int mqtt_main(void)
{
	mqtt_client_ready = FALSE;
	int rc;
	char mqtturl[512];
	sprintf(mqtturl, "%s://%s:%d", rctx.mqtt.protocol, rctx.mqtt.host, rctx.mqtt.port);

	if ((rc = MQTTAsync_create(&client, mqtturl, rctx.self_id, MQTTCLIENT_PERSISTENCE_NONE, NULL)) != MQTTASYNC_SUCCESS)
	{
		printf("Failed to create client object, return code %d\n", rc);
		exit(EXIT_FAILURE);
	}

	if ((rc = MQTTAsync_setCallbacks(client, NULL, connlost, messageArrived, NULL)) != MQTTASYNC_SUCCESS)
	{
		printf("Failed to set callback, return code %d\n", rc);
		exit(EXIT_FAILURE);
	}

	conn_opts.keepAliveInterval = 20;
	conn_opts.cleansession = 1;
	conn_opts.onSuccess = onConnect;
	conn_opts.onFailure = onConnectFailure;
	conn_opts.context = client;

	mqtt_client_ready = TRUE;
	mqtt_client_suback_ready = FALSE;

	if ((rc = MQTTAsync_connect(client, &conn_opts)) != MQTTASYNC_SUCCESS)
	{
		printf("Failed to start connect, return code %d\n", rc);
		exit(EXIT_FAILURE);
	}

	size_t wait_time = 15;
	size_t wait_ms = 10;
	for (size_t i = 0; i < wait_time * (1000 / wait_ms); i++)
	{
		if (mqtt_client_ready && MQTTAsync_isConnected(client) && mqtt_client_suback_ready) {
			printf("mqtt link ready\n");
			// 发送初始化命令
			luat_remotem_set_uplink(mqtt_uplink_cb);
			break;
		}
		Sleep(wait_ms);
	}

    return rc;
}

