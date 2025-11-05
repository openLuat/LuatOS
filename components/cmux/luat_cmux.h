
#ifndef LUAT_CMUX_H
#define LUAT_CMUX_H
#include "luat_base.h"
#include "luat_dbg.h"


typedef struct luat_cmux
{
    uint8_t state;
    uint8_t main_state;
    uint8_t shell_state;
    uint8_t log_state;
    uint8_t dbg_state;
    uint8_t download_state;
}luat_cmux_t;

#define LUAT_CMUX_CH_MAIN 0
#define LUAT_CMUX_CH_SHELL 1
#define LUAT_CMUX_CH_LOG  2
#define LUAT_CMUX_CH_DBG  3
#define LUAT_CMUX_CH_DOWNLOAD  4

#define CMUX_HEAD_FLAG_BASIC (unsigned char)0xF9
#define CMUX_HEAD_FLAG_ADV (unsigned char)0x7E

#define CMUX_CONTROL_PF 16
#define CMUX_ADDRESS_CR 2
#define CMUX_ADDRESS_EA 1

#define CMUX_FRAME_SABM 47
#define CMUX_FRAME_UA 99
#define CMUX_FRAME_DM 15
#define CMUX_FRAME_DISC 67
#define CMUX_FRAME_UIH 239
#define CMUX_FRAME_UI 3

#define CMUX_DHCL_MASK       63         /* DLCI number is port number, 63 is the mask of DLCI; C/R bit is 1 when we send data */
#define CMUX_DATA_MASK       127        /* when data length is out of 127( 0111 1111 ), we must use two bytes to describe data length in the cmux frame */
#define CMUX_HIGH_DATA_MASK  32640      /* 32640 (‭ 0111 1111 1000 0000 ‬), the mask of high data bits */

#define CMUX_ADDRESS(buff) (buff[1])
#define CMUX_ADDRESS_DLC(buff) (buff[1]>>2)
#define CMUX_CONTROL(buff) (buff[2])

#define CMUX_CONTROL_ISSABM(buff) (buff[2]==(CMUX_FRAME_SABM | CMUX_CONTROL_PF))
#define CMUX_CONTROL_ISUA(buff) (buff[2]==(CMUX_FRAME_UA & ~CMUX_CONTROL_PF))
#define CMUX_CONTROL_ISDM(buff) (buff[2]==(CMUX_FRAME_DM & ~CMUX_CONTROL_PF))
#define CMUX_CONTROL_ISDISC(buff) (buff[2]==(CMUX_FRAME_DISC | CMUX_CONTROL_PF))
#define CMUX_CONTROL_ISUIH(buff) (buff[2]==(CMUX_FRAME_UIH & ~CMUX_CONTROL_PF))
#define CMUX_CONTROL_ISUI(buff) (buff[2]==(CMUX_FRAME_UI & ~CMUX_CONTROL_PF))

#define CMUX_BUFFER_SIZE   1024

extern uint8_t echo_enable;
extern uint8_t cmux_state;
extern uint8_t cmux_main_state;
extern uint8_t cmux_shell_state;
extern uint8_t cmux_log_state;
extern uint8_t cmux_dbg_state;
extern uint8_t cmux_download_state;

void luat_cmux_write(int port, uint8_t control,char* buff, size_t len);
void luat_cmux_read(unsigned char* buff,size_t len);

#endif

