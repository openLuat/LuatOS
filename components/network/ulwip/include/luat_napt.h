#ifndef LUAT_NAPT_H
#define LUAT_NAPT_H


#ifdef __cplusplus
#if __cplusplus
extern "C"{
#endif
#endif /* __cplusplus */

/* ============================== configure ===================== */
/* napt age time (second) */
#define NAPT_TABLE_TIMEOUT           60

/* napt port range: 15000~25000 */
#define NAPT_LOCAL_PORT_RANGE_START  0x3A98
#define NAPT_LOCAL_PORT_RANGE_END    0x61A8

/* napt icmp id range: 3000-65535 */
#define NAPT_ICMP_ID_RANGE_START     0xBB8
#define NAPT_ICMP_ID_RANGE_END       0xFFFF


/* napt table size */
// #define NAPT_TABLE_LIMIT
#ifdef  NAPT_TABLE_LIMIT
#define NAPT_TABLE_SIZE_MAX          3000
#endif
/* ============================================================ */


#define NAPT_TMR_INTERVAL            ((NAPT_TABLE_TIMEOUT / 2) * 1000UL)

#ifndef u16
#define u16  unsigned short
#endif

#ifndef u8
#define u8   unsigned char
#endif

#ifndef u32
#define u32  unsigned int
#endif

extern u8 luat_napt_port_is_used(u16 port);

extern int luat_napt_init(void);

extern int luat_napt_input(u8 is_inet, u8 *pkt_body, u32 pkt_len, ip_addr_t* gw_ip);

void luat_napt_table_check(void *arg);

#ifdef __cplusplus
#if __cplusplus
}
#endif
#endif /* __cplusplus */

#endif /* __ALG_H__ */

