
#ifndef __ETHERNET_COMMON_DHCP_DEF_H__
#define __ETHERNET_COMMON_DHCP_DEF_H__
#include "luat_base.h"
#ifdef LUAT_USE_DHCP

#ifdef __cplusplus
extern "C" {
#endif

#define DHCP_CLIENT_PORT  68
#define DHCP_SERVER_PORT  67


 /* DHCP message item offsets and length */
#define DHCP_CHADDR_LEN   16U
#define DHCP_SNAME_OFS    44U
#define DHCP_SNAME_LEN    64U
#define DHCP_FILE_OFS     108U
#define DHCP_FILE_LEN     128U
#define DHCP_MSG_LEN      236U
#define DHCP_OPTIONS_OFS  (DHCP_MSG_LEN + 4U) /* 4 byte: cookie */
#define DHCP_MIN_OPTIONS_LEN 68U


typedef struct
{
	uint64_t lease_end_time;
	uint64_t lease_p1_time;
	uint64_t lease_p2_time;
	uint64_t last_tx_time;
	uint32_t server_ip;
	uint32_t temp_ip;	//服务器给的动态IP
	uint32_t submask;
	uint32_t gateway;
	uint32_t ip;	//当前的动态IP
	uint32_t dns_server[2];
	uint32_t xid;
	uint32_t lease_time;
	char name[32];
	uint8_t mac[6];
	uint8_t state;
	uint8_t discover_cnt;
}dhcp_client_info_t;

typedef struct
{
	uint8_t *p;
	uint16_t len;
	uint8_t id;
	uint8_t unuse;
}dhcp_option_t;


/* DHCP client states */
enum {
  DHCP_STATE_NOT_WORK             = 0,
  DHCP_STATE_WAIT_LEASE_P1,
  DHCP_STATE_WAIT_LEASE_P1_ACK,
  DHCP_STATE_WAIT_LEASE_P2,
  DHCP_STATE_WAIT_LEASE_P2_ACK,
  DHCP_STATE_WAIT_LEASE_END,
  DHCP_STATE_DISCOVER,
  DHCP_STATE_WAIT_OFFER,
  DHCP_STATE_SELECT,
  DHCP_STATE_WAIT_SELECT_ACK,
  DHCP_STATE_REQUIRE,
//  DHCP_STATE_WAIT_REQUIRE_ACK,
  DHCP_STATE_DECLINE,
  DHCP_STATE_CHECK,
};

/* DHCP op codes */
#define DHCP_BOOTREQUEST            1
#define DHCP_BOOTREPLY              2

/* DHCP message types */
#define DHCP_DISCOVER               1
#define DHCP_OFFER                  2
#define DHCP_REQUEST                3
#define DHCP_DECLINE                4
#define DHCP_ACK                    5
#define DHCP_NAK                    6
#define DHCP_RELEASE                7
#define DHCP_INFORM                 8

/** DHCP hardware type, currently only ethernet is supported */
#define DHCP_HTYPE_10MB				1
#define DHCP_HTYPE_100MB			2
#define DHCP_HTYPE_ETH              DHCP_HTYPE_10MB

#define DHCP_MAGIC_COOKIE           0x63825363UL

/* This is a list of options for BOOTP and DHCP, see RFC 2132 for descriptions */

/* BootP options */
#define DHCP_OPTION_PAD             0
#define DHCP_OPTION_SUBNET_MASK     1 /* RFC 2132 3.3 */
#define DHCP_OPTION_ROUTER          3
#define DHCP_OPTION_DNS_SERVER      6
#define DHCP_OPTION_HOSTNAME        12
#define DHCP_OPTION_IP_TTL          23
#define DHCP_OPTION_MTU             26
#define DHCP_OPTION_BROADCAST       28
#define DHCP_OPTION_TCP_TTL         37
#define DHCP_OPTION_NTP             42
#define DHCP_OPTION_END             255

/* DHCP options */
#define DHCP_OPTION_REQUESTED_IP    50 /* RFC 2132 9.1, requested IP address */
#define DHCP_OPTION_LEASE_TIME      51 /* RFC 2132 9.2, time in seconds, in 4 bytes */
#define DHCP_OPTION_OVERLOAD        52 /* RFC2132 9.3, use file and/or sname field for options */

#define DHCP_OPTION_MESSAGE_TYPE    53 /* RFC 2132 9.6, important for DHCP */
#define DHCP_OPTION_MESSAGE_TYPE_LEN 1

#define DHCP_OPTION_SERVER_ID       54 /* RFC 2132 9.7, server IP address */
#define DHCP_OPTION_PARAMETER_REQUEST_LIST  55 /* RFC 2132 9.8, requested option types */

#define DHCP_OPTION_MAX_MSG_SIZE    57 /* RFC 2132 9.10, message size accepted >= 576 */
#define DHCP_OPTION_MAX_MSG_SIZE_LEN 2

#define DHCP_OPTION_T1              58 /* T1 renewal time */
#define DHCP_OPTION_T2              59 /* T2 rebinding time */
#define DHCP_OPTION_US              60
#define DHCP_OPTION_CLIENT_ID       61
#define DHCP_OPTION_TFTP_SERVERNAME 66
#define DHCP_OPTION_BOOTFILE        67

/* possible combinations of overloading the file and sname fields with options */
#define DHCP_OVERLOAD_NONE          0
#define DHCP_OVERLOAD_FILE          1
#define DHCP_OVERLOAD_SNAME         2
#define DHCP_OVERLOAD_SNAME_FILE    3


void make_ip4_dhcp_msg_base(dhcp_client_info_t *dhcp, uint16_t flag, Buffer_Struct *out);
void ip4_dhcp_msg_add_bytes_option(uint8_t id, uint8_t *data, uint8_t len, Buffer_Struct *out);
void ip4_dhcp_msg_add_ip_option(uint8_t id, uint32_t ip, Buffer_Struct *out);
void ip4_dhcp_msg_add_integer_option(uint8_t id, uint8_t len, uint32_t value, Buffer_Struct *out);
void make_ip4_dhcp_discover_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out);
void make_ip4_dhcp_select_msg(dhcp_client_info_t *dhcp, uint16_t flag, Buffer_Struct *out);
void make_ip4_dhcp_decline_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out);
int analyze_ip4_dhcp(dhcp_client_info_t *dhcp, Buffer_Struct *in);
int ip4_dhcp_run(dhcp_client_info_t *dhcp, Buffer_Struct *in, Buffer_Struct *out, uint32_t *remote_ip);
#ifdef __cplusplus
}
#endif

#endif
#endif
