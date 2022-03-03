#ifndef LUAT_LIBTCPIP_MQTT_H
#define LUAT_LIBTCPIP_MQTT_H

#include "libemqtt.h"

#define MQTT_READ_TIMEOUT        (-1000)

#define MQTT_READ_TIME_SEC         15
#define MQTT_READ_TIME_US          0

typedef struct app_mqtt_conf
{
    char client_id[192];
    char password[192];
    char username[192];
    char host[192];
    int  port;
    char pub_topic[192];
    char sub_topic[192];
}app_mqtt_conf_t;

#endif

