
/**
LuatOS cmux
*/
#include "lua.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "luat.cmux"
#include "luat_log.h"

#ifdef LUAT_USE_MCU
#include "luat_mcu.h"
#endif

#include "luat_shell.h"
#include "luat_str.h"
#include "luat_cmux.h"

#include "luat_dbg.h"

extern uint8_t echo_enable;
extern uint8_t cmux_state;
uint8_t cmux_main_state = 0;
uint8_t cmux_shell_state = 0;
uint8_t cmux_log_state = 0;
uint8_t cmux_dbg_state = 0;

typedef struct   
{
    uint8_t Fcs;
    uint8_t Len;
    unsigned char data[128];
}cmux_data;

static cmux_data cmux_read_data;

const uint8_t cmux_crctable[256] = {
    0x00, 0x91, 0xE3, 0x72, 0x07, 0x96, 0xE4, 0x75,
    0x0E, 0x9F, 0xED, 0x7C, 0x09, 0x98, 0xEA, 0x7B,
    0x1C, 0x8D, 0xFF, 0x6E, 0x1B, 0x8A, 0xF8, 0x69,
    0x12, 0x83, 0xF1, 0x60, 0x15, 0x84, 0xF6, 0x67,
    0x38, 0xA9, 0xDB, 0x4A, 0x3F, 0xAE, 0xDC, 0x4D,
    0x36, 0xA7, 0xD5, 0x44, 0x31, 0xA0, 0xD2, 0x43,
    0x24, 0xB5, 0xC7, 0x56, 0x23, 0xB2, 0xC0, 0x51,
    0x2A, 0xBB, 0xC9, 0x58, 0x2D, 0xBC, 0xCE, 0x5F,
    0x70, 0xE1, 0x93, 0x02, 0x77, 0xE6, 0x94, 0x05,
    0x7E, 0xEF, 0x9D, 0x0C, 0x79, 0xE8, 0x9A, 0x0B,
    0x6C, 0xFD, 0x8F, 0x1E, 0x6B, 0xFA, 0x88, 0x19,
    0x62, 0xF3, 0x81, 0x10, 0x65, 0xF4, 0x86, 0x17,
    0x48, 0xD9, 0xAB, 0x3A, 0x4F, 0xDE, 0xAC, 0x3D,
    0x46, 0xD7, 0xA5, 0x34, 0x41, 0xD0, 0xA2, 0x33,
    0x54, 0xC5, 0xB7, 0x26, 0x53, 0xC2, 0xB0, 0x21,
    0x5A, 0xCB, 0xB9, 0x28, 0x5D, 0xCC, 0xBE, 0x2F,
    0xE0, 0x71, 0x03, 0x92, 0xE7, 0x76, 0x04, 0x95,
    0xEE, 0x7F, 0x0D, 0x9C, 0xE9, 0x78, 0x0A, 0x9B,
    0xFC, 0x6D, 0x1F, 0x8E, 0xFB, 0x6A, 0x18, 0x89,
    0xF2, 0x63, 0x11, 0x80, 0xF5, 0x64, 0x16, 0x87,
    0xD8, 0x49, 0x3B, 0xAA, 0xDF, 0x4E, 0x3C, 0xAD,
    0xD6, 0x47, 0x35, 0xA4, 0xD1, 0x40, 0x32, 0xA3,
    0xC4, 0x55, 0x27, 0xB6, 0xC3, 0x52, 0x20, 0xB1,
    0xCA, 0x5B, 0x29, 0xB8, 0xCD, 0x5C, 0x2E, 0xBF,
    0x90, 0x01, 0x73, 0xE2, 0x97, 0x06, 0x74, 0xE5,
    0x9E, 0x0F, 0x7D, 0xEC, 0x99, 0x08, 0x7A, 0xEB,
    0x8C, 0x1D, 0x6F, 0xFE, 0x8B, 0x1A, 0x68, 0xF9,
    0x82, 0x13, 0x61, 0xF0, 0x85, 0x14, 0x66, 0xF7,
    0xA8, 0x39, 0x4B, 0xDA, 0xAF, 0x3E, 0x4C, 0xDD,
    0xA6, 0x37, 0x45, 0xD4, 0xA1, 0x30, 0x42, 0xD3,
    0xB4, 0x25, 0x57, 0xC6, 0xB3, 0x22, 0x50, 0xC1,
    0xBA, 0x2B, 0x59, 0xC8, 0xBD, 0x2C, 0x5E, 0xCF};

uint8_t cmux_frame_check(const uint8_t *input, int length){
    uint8_t fcs = 0xFF;
    int i;
    for (i = 0; i < length; i++){
        fcs = cmux_crctable[fcs ^ input[i]];
    }
    return (0xFF - fcs);
}

void uih_main_manage(unsigned char*buff){
    
}

void uih_shell_manage(unsigned char*buff){
    char send_buff[128] = {0};
    char *data = (char *)luat_heap_malloc(buff[3]>>1);
    memcpy(data, buff+4, buff[3]>>1);
    if (echo_enable)
    {
        sprintf(send_buff, "%s\r\n", data);
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
        memset(send_buff, 0, 128);
    }
    if (memcmp("AT\r", data, 3) == 0){
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }else if (memcmp("ATI", data, 3) == 0){
        #ifdef LUAT_BSP_VERSION
            sprintf(send_buff, "LuatOS-SoC_%s_%s\r\n", LUAT_BSP_VERSION, luat_os_bsp());
        #else
            sprintf(send_buff, "LuatOS-SoC_%s_%s\r\n", luat_version_str(), luat_os_bsp());
        #endif
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }else if (memcmp("AT+LUAFLASHSIZE?", data, 16) == 0){
        #ifdef FLASH_FS_REGION_SIZE
            sprintf(send_buff, "+LUAFLASHSIZE: 0X%x\r\n",FLASH_FS_REGION_SIZE);
            luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
            luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
        #endif
    }else if (memcmp("AT+LUACHECKSUM=", data, 15) == 0){
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"+LUAFLASHSIZE: 0\r\n", 18);
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }else if (memcmp("AT+RESET", data, 8) == 0){
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
        luat_os_reboot(0);
    }else if (memcmp("ATE0\r", data, 5) == 0 || memcmp("ate1\r", data, 5) == 0) {
        echo_enable = 0;
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }
    // 回显开启
    else if (memcmp("ATE1\r", data, 5) == 0 || memcmp("ate1\r", data, 5) == 0) {
        echo_enable = 1;
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }
    luat_heap_free(data);
}

void uih_dbg_manage(unsigned char*buff){
    char *data = (char *)luat_heap_malloc((buff[3]>>1)+1);
    memcpy(data, buff+4, (buff[3]>>1)+1);
    if (strcmp("dbg",strtok(data, " ")) == 0){
        char *command = strtok(NULL, " ");
        if (memcmp("start", command, 5) == 0){
            luat_dbg_set_hook_state(2);
        }else if(memcmp("continue",command,8) == 0){
            luat_dbg_set_hook_state(2);
        }else if(memcmp("next",command,4) == 0 || memcmp("step",command,4) == 0){
            luat_dbg_set_hook_state(4);
        }else if(memcmp("stepIn",command,6) == 0 || memcmp("stepin",command,6) == 0){
            luat_dbg_set_hook_state(5);
        }else if(memcmp("stepOut",command,7) == 0 || memcmp("stepout",command,7) == 0){
            luat_dbg_set_hook_state(6);
        }else if(memcmp("bt",command,2) == 0){
            char *params = strtok(NULL, " ");
            if (params != NULL){
                luat_dbg_set_runcb(luat_dbg_backtrace, (void*)atoi(params));
            }else{
                luat_dbg_set_runcb(luat_dbg_backtrace, (void*)-1);
            }
        }else if(memcmp("vars",command,4) == 0){
            char *params = strtok(NULL, " ");
            if (params != NULL){
                luat_dbg_set_runcb(luat_dbg_vars, (void*)atoi(params));
            }else{
                luat_dbg_set_runcb(luat_dbg_vars, (void*)0);
            }
        }else if(memcmp("gvars",command,5) == 0){
            luat_dbg_gvars((void*)0);
        }else if(memcmp("jvars",command,5) == 0){
            luat_dbg_jvars(strtok(NULL, " "));
        }else if(memcmp("break",command,5) == 0){
            char *sub_command = strtok(NULL, " ");
            if (memcmp("clr",sub_command,3) == 0){
                luat_dbg_breakpoint_clear(strtok(NULL, " "));
            }else if (memcmp("add",sub_command,3) == 0){
                luat_dbg_breakpoint_add(strtok(NULL, " "),atoi(strtok(NULL, " ")));
            }else if (memcmp("del",sub_command,3) == 0){
                char *params = strtok(NULL, " ");
                if (params != NULL){
                    luat_dbg_breakpoint_clear(params);
                }else{
                    luat_dbg_breakpoint_clear(NULL);
                }
            }
        }else {
        }
    }
    luat_heap_free(data);
}

void cmux_frame_manage(unsigned char*buff){
    if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_MAIN){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_main_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_state = 0;
            cmux_main_state = 0;
            cmux_log_state = 0;
            cmux_dbg_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_main_state == 1){
            uih_main_manage(buff);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_SHELL){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_shell_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_shell_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_shell_state == 1){
            uih_shell_manage(buff);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_LOG){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_log_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_LOG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_log_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_LOG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_DBG){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_dbg_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_DBG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_dbg_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_DBG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_dbg_state == 1){
            uih_dbg_manage(buff);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_DOWNLOAD){
        if (CMUX_CONTROL_ISSABM(buff)){
            luat_cmux_write(LUAT_CMUX_CH_DOWNLOAD,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            luat_cmux_write(LUAT_CMUX_CH_DOWNLOAD,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }
    }
}

void luat_cmux_write(int port, uint8_t control,char* buff, size_t len) {
    char prefix[5] = {CMUX_HEAD_FLAG_BASIC, CMUX_ADDRESS_EA | CMUX_ADDRESS_CR, 0, 0, 0};
    char postfix[2] = {0xFF, CMUX_HEAD_FLAG_BASIC};
    int prefix_length = 4;
    prefix[0] = CMUX_HEAD_FLAG_BASIC;
    prefix[1] = prefix[1] | ((CMUX_DHCL_MASK & port) << 2);
    prefix[2] = control;
    if (len > CMUX_DATA_MASK){
        prefix_length = 5;
        prefix[3] = ((CMUX_DATA_MASK & len) << 1);
        prefix[4] = (CMUX_HIGH_DATA_MASK & len) >> 7;
    }else{
        prefix[3] = 1 | (len << 1);
    }
    luat_shell_write(prefix, prefix_length);
    postfix[0] = cmux_frame_check((const uint8_t*)(prefix+1), prefix_length - 1);
    if (len > 0)luat_shell_write(buff, len);
    luat_shell_write(postfix, 2);
}
void luat_cmux_read(unsigned char* buff,size_t len){
    // if (buff[0]==CMUX_HEAD_FLAG_BASIC && buff[len-1]==CMUX_HEAD_FLAG_BASIC && cmux_frame_check(buff+1,len-3)==buff[len-2]){
    // for (size_t i = 0; i < len; i++){
    //     LLOGD("buff[%d]:%02X",i,buff[i]);
    // }
    // if (buff[0]==CMUX_HEAD_FLAG_BASIC && len==4){
    //     memset(cmux_read_data.data, 0, 128);
    //     memmove(cmux_read_data.data,  buff, len);
    //     cmux_read_data.Len = len;
    //     cmux_read_data.Fcs = cmux_frame_check(buff+1,len-1);
    // }else if (buff[0]==cmux_read_data.Fcs && buff[1]==CMUX_HEAD_FLAG_BASIC && len==2){
    //     if (cmux_read_data.Fcs != 0 ){
    //         // luat_os_entry_cri();
    //         luat_os_irq_disable(16);
    //         cmux_frame_manage(cmux_read_data.data);
    //         luat_os_irq_enable(16);
    //         // luat_os_exit_cri();
    //     }
    //     memset(cmux_read_data.data, 0, 128);
    //     cmux_read_data.Fcs = 0;
    // }else 
    if (buff[0]==CMUX_HEAD_FLAG_BASIC && buff[len-1]==CMUX_HEAD_FLAG_BASIC){
        if (cmux_frame_check(buff+1,3) == buff[len-2] ){
            memset(cmux_read_data.data, 0, 128);
            memmove(cmux_read_data.data,  buff, len);
            // luat_os_irq_disable(16);
            // luat_os_entry_cri();
            cmux_frame_manage(cmux_read_data.data);
            // luat_os_exit_cri();
            // luat_os_irq_enable(16);
        }
        memset(cmux_read_data.data, 0, 128);
        cmux_read_data.Fcs = 0;
    }else if (buff[0]==CMUX_HEAD_FLAG_BASIC ){
        memset(cmux_read_data.data, 0, 128);
        memmove(cmux_read_data.data,  buff, len);
        cmux_read_data.Len = len;
        cmux_read_data.Fcs = cmux_frame_check(buff+1,3);
    }else if (buff[len-2]==cmux_read_data.Fcs && buff[len-1]==CMUX_HEAD_FLAG_BASIC){
        if (cmux_read_data.Fcs != 0 ){
            strcat((char*)cmux_read_data.data, (const char*)buff);
            // luat_os_irq_disable(16);
            // luat_os_entry_cri();
            cmux_frame_manage(cmux_read_data.data);
            // luat_os_exit_cri();
            // luat_os_irq_enable(16);
        }
        memset(cmux_read_data.data, 0, 128);
        cmux_read_data.Fcs = 0;
    }else if (cmux_read_data.Fcs && cmux_read_data.Len){
        strcat((char*)cmux_read_data.data, (const char*)buff);
    }else{
        memset(cmux_read_data.data, 0, 128);
        cmux_read_data.Fcs = 0;
    }
}

// #define min(a, b) ((a) <= (b) ? (a) : (b))

// /* increases buffer pointer by one and wraps around if necessary */
// #define INC_BUF_POINTER(buf, p)  \
//     (p)++;                       \
//     if ((p) == (buf)->end_point) \
//         (p) = (buf)->data;

// /* Tells, how many chars are saved into the buffer */
// #define cmux_buffer_length(buff) (((buff)->read_point > (buff)->write_point) ? (CMUX_BUFFER_SIZE - ((buff)->read_point - (buff)->write_point)) : ((buff)->write_point - (buff)->read_point))

// /* Tells, how much free space there is in the buffer */
// #define cmux_buffer_free(buff) (((buff)->read_point > (buff)->write_point) ? ((buff)->read_point - (buff)->write_point) : (CMUX_BUFFER_SIZE - ((buff)->write_point - (buff)->read_point)))


// size_t cmux_buffer_write(struct cmux_buffer *buff, uint8_t *input, size_t count)
// {
//     int c = buff->end_point - buff->write_point;
//     count = min(count, cmux_buffer_free(buff));
//     if (count > c)
//     {
//         memcpy(buff->write_point, input, c);
//         memcpy(buff->data, input + c, count - c);
//         buff->write_point = buff->data + (count - c);
//     }
//     else
//     {
//         memcpy(buff->write_point, input, count);
//         buff->write_point += count;
//         if (buff->write_point == buff->end_point)
//             buff->write_point = buff->data;
//     }
//     return count;
// }

// static struct cmux_frame *cmux_frame_parse(struct cmux_buffer *buffer)
// {
//     int end;
//     int length_needed = 5; /* channel, type, length, fcs, flag */
//     uint8_t *data = NULL;
//     uint8_t fcs = 0xFF;
//     struct cmux_frame *frame = NULL;
//     extern uint8_t cmux_crctable[256];
//     /* Find start flag */
//     while (!buffer->flag_found && cmux_buffer_length(buffer) > 0)
//     {
//         if (*buffer->read_point == CMUX_HEAD_FLAG)
//             buffer->flag_found = 1;
//         INC_BUF_POINTER(buffer, buffer->read_point);
//     }
//     if (!buffer->flag_found) /* no frame started */
//         return NULL;
//     /* skip empty frames (this causes troubles if we're using DLC 62) */
//     while (cmux_buffer_length(buffer) > 0 && (*buffer->read_point == CMUX_HEAD_FLAG))
//     {
//         INC_BUF_POINTER(buffer, buffer->read_point);
//     }
//     if (cmux_buffer_length(buffer) >= length_needed)
//     {
//         data = buffer->read_point;
//         frame = (struct cmux_frame *)rt_malloc(sizeof(struct cmux_frame));
//         frame->data = NULL;
//         frame->channel = ((*data & 252) >> 2);
//         fcs = cmux_crctable[fcs ^ *data];
//         INC_BUF_POINTER(buffer, data);
//         frame->control = *data;
//         fcs = cmux_crctable[fcs ^ *data];
//         INC_BUF_POINTER(buffer, data);
//         frame->data_length = (*data & 254) >> 1;
//         fcs = cmux_crctable[fcs ^ *data];
//         /* frame data length more than 127 bytes */
//         if ((*data & 1) == 0)
//         {
//             INC_BUF_POINTER(buffer,data);
//             frame->data_length += (*data*128);
//             fcs = cmux_crctable[fcs^*data];
//             length_needed++;
//             LOG_D("len_need: %d, frame_data_len: %d.", length_needed, frame->data_length);
//         }
//         length_needed += frame->data_length;
//         if (!(cmux_buffer_length(buffer) >= length_needed))
//         {
//             cmux_frame_destroy(frame);
//             return NULL;
//         }
//         INC_BUF_POINTER(buffer, data);
//         /* extract data */
//         if (frame->data_length > 0)
//         {
//             frame->data = (unsigned char *)rt_malloc(frame->data_length);
//             if (frame->data != NULL)
//             {
//                 end = buffer->end_point - data;
//                 if (frame->data_length > end)
//                 {
//                     rt_memcpy(frame->data, data, end);
//                     rt_memcpy(frame->data + end, buffer->data, frame->data_length - end);
//                     data = buffer->data + (frame->data_length - end);
//                 }
//                 else
//                 {
//                     rt_memcpy(frame->data, data, frame->data_length);
//                     data += frame->data_length;
//                     if (data == buffer->end_point)
//                         data = buffer->data;
//                 }
//                 if (CMUX_FRAME_IS(CMUX_FRAME_UI, frame))
//                 {
//                     for (end = 0; end < frame->data_length; end++)
//                         fcs = cmux_crctable[fcs ^ (frame->data[end])];
//                 }
//             }
//             else
//             {
//                 LOG_E("Out of memory, when allocating space for frame data.");
//                 frame->data_length = 0;
//             }
//         }
//         /* check FCS */
//         if (cmux_crctable[fcs ^ (*data)] != 0xCF)
//         {
//             LOG_W("Dropping frame: FCS doesn't match.");
//             cmux_frame_destroy(frame);
//             buffer->flag_found = 0;
//             buffer->read_point = data;
//             return cmux_frame_parse(buffer);
//         }
//         else
//         {
//             /* check end flag */
//             INC_BUF_POINTER(buffer, data);
//             if (*data != CMUX_HEAD_FLAG)
//             {
//                 LOG_W("Dropping frame: End flag not found. Instead: %d.", *data);
//                 cmux_frame_destroy(frame);
//                 buffer->flag_found = 0;
//                 buffer->read_point = data;
//                 return cmux_frame_parse(buffer);
//             }
//             else
//             {
//             }
//             INC_BUF_POINTER(buffer, data);
//         }
//         buffer->read_point = data;
//     }
//     return frame;
// }

// static void cmux_recv_processdata(struct cmux *cmux, uint8_t *buf, size_t len){
//     size_t count = len;
//     struct cmux_frame *frame = NULL;
//     cmux_buffer_write(cmux->buffer, buf, count);
//     frame = cmux_frame_parse(cmux->buffer);
//     if (frame != NULL){
//         /* distribute different data */
//         if ((CMUX_FRAME_IS(CMUX_FRAME_UI, frame) || CMUX_FRAME_IS(CMUX_FRAME_UIH, frame))){
//             LLOGD("this is UI or UIH frame from channel(%d).", frame->channel);
//             if (frame->channel > 0){
//                 /* receive data from logical channel, distribution them */
//                 cmux_frame_push(cmux, frame->channel, frame);
//                 cmux_vcom_isr(cmux, frame->channel, frame->data_length);
//             }else{
//                 /* control channel command */
//                 LOG_W("control channel command haven't support.");
//                 cmux_frame_destroy(frame);
//             }
//         }else{
//             switch ((frame->control & ~CMUX_CONTROL_PF)){
//             case CMUX_FRAME_UA:
//                 LLOGD("This is UA frame for channel(%d).", frame->channel);
//                 break;
//             case CMUX_FRAME_DM:
//                 LLOGD("This is DM frame for channel(%d).", frame->channel);
//                 break;
//             case CMUX_FRAME_SABM:
//                 LLOGD("This is SABM frame for channel(%d).", frame->channel);
//                 break;
//             case CMUX_FRAME_DISC:
//                 LLOGD("This is DISC frame for channel(%d).", frame->channel);
//                 break;
//             }
//             cmux_frame_destroy(frame);
//         }
//     }
// }

// void luat_cmux_analysis(unsigned char* buff,size_t len){

// }
