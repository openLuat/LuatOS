#ifndef LUAT_NETWORK_POSIX_H
#define LUAT_NETWORK_POSIX_H

#include "luat_base.h"
#include "luat_network_adapter.h"

typedef struct posix_socket
{
    int socket_id;
    uint64_t tag;
    uint16_t local_port;
    luat_ip_addr_t remote_ip;
    uint16_t remote_port;
    void *user_data;
}posix_socket_t;

int network_posix_client_thread_start(posix_socket_t* ps);
void posix_network_client_thread_entry(posix_socket_t* args);

#endif
