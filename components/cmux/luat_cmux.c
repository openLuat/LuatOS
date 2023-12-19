/**
LuatOS cmux
*/
#include "lua.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "stdlib.h"

#define LUAT_LOG_TAG "cmux"
#include "luat_log.h"

#ifdef LUAT_USE_MCU
#include "luat_mcu.h"
#endif

#include "luat_shell.h"
#include "luat_str.h"
#include "luat_cmux.h"

luat_cmux_t cmux_ctx;
extern luat_shell_t shell_ctx;

static const uint8_t cmux_crctable[256] = {
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

static uint8_t cmux_frame_check(const uint8_t *input, int length){
    uint8_t fcs = 0xFF;
    int i;
    for (i = 0; i < length; i++){
        fcs = cmux_crctable[fcs ^ input[i]];
    }
    return (0xFF - fcs);
}

static void uih_main_manage(unsigned char*buff,size_t len){
    
}

static void uih_shell_manage(unsigned char*buff,size_t len){
    char send_buff[128] = {0};
    char *data = (char *)luat_heap_malloc(buff[3]>>1);
    memcpy(data, buff+4, buff[3]>>1);
    if (shell_ctx.echo_enable)
    {
        sprintf_(send_buff, "%s\r\n", data);
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
        memset(send_buff, 0, 128);
    }
    if (memcmp("AT\r", data, 3) == 0){
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }else if (memcmp("ATI", data, 3) == 0){
        #ifdef LUAT_BSP_VERSION
            sprintf_(send_buff, "LuatOS-SoC_%s_%s\r\n", LUAT_BSP_VERSION, luat_os_bsp());
        #else
            sprintf_(send_buff, "LuatOS-SoC_%s_%s\r\n", luat_version_str(), luat_os_bsp());
        #endif
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }else if (memcmp("AT+LUAFLASHSIZE?", data, 16) == 0){
        #ifdef FLASH_FS_REGION_SIZE
            sprintf_(send_buff, "+LUAFLASHSIZE: 0X%x\r\n",FLASH_FS_REGION_SIZE);
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
        shell_ctx.echo_enable = 0;
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }
    // 回显开启
    else if (memcmp("ATE1\r", data, 5) == 0 || memcmp("ate1\r", data, 5) == 0) {
        shell_ctx.echo_enable = 1;
        luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r\n", 4);
    }
    luat_heap_free(data);
}

static void uih_dbg_manage(unsigned char*buff,size_t len){
    // char *data = (char *)luat_heap_malloc(len-3);
    // memset(data, 0, len-3); // 确保填充为0
    // memcpy(data, buff+4, len-4);
    char data[128] = {0};
    if(cmux_ctx.dbg_state == 1)
        memcpy(data, buff+4, len-4); 
    else
        memcpy(data, buff, len); 
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
    // luat_heap_free(data);
}
#ifdef LUAT_USE_YMODEM
#include "luat_ymodem.h"
static int ymodem_state = 0;
static void* ymodem_handler = NULL;
#endif
static void uih_download_manage(unsigned char*buff,size_t len){
#ifdef LUAT_USE_YMODEM
    uint8_t ack, flag, file_ok, all_done;
    if (ymodem_handler == NULL) {
        ymodem_handler = luat_ymodem_create_handler("/", NULL);
    }
    luat_ymodem_receive(ymodem_handler, buff, len, &ack, &flag, &file_ok, &all_done);
    if (all_done) {
        //luat_ymodem_release
    }
#endif
}

LUAT_WEAK void luat_cmux_log_set(uint8_t state) {
}

static void cmux_frame_manage(unsigned char*buff,size_t len){
    // for (size_t i = 0; i < 10; i++){
    //     LLOGD("buff[%d]:%02X",i,buff[i]);
    // }
    if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_MAIN){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_ctx.main_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_ctx.state = 0;
            cmux_ctx.main_state = 0;
            cmux_ctx.log_state = 0;
            cmux_ctx.dbg_state = 0;
            cmux_ctx.download_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_ctx.main_state == 1){
            uih_main_manage(buff,len);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_SHELL){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_ctx.shell_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_ctx.shell_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_SHELL,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_ctx.shell_state == 1){
            uih_shell_manage(buff,len);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_LOG){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_ctx.log_state = 1;
            luat_cmux_log_set(cmux_ctx.log_state);
            luat_cmux_write(LUAT_CMUX_CH_LOG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_ctx.log_state = 0;
            luat_cmux_log_set(cmux_ctx.log_state);
            luat_cmux_write(LUAT_CMUX_CH_LOG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_DBG){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_ctx.dbg_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_DBG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_ctx.dbg_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_DBG,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_ctx.dbg_state == 1){
            uih_dbg_manage(buff,len);
        }
    }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_DOWNLOAD){
        if (CMUX_CONTROL_ISSABM(buff)){
            cmux_ctx.download_state = 1;
            luat_cmux_write(LUAT_CMUX_CH_DOWNLOAD,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISDISC(buff)){
            cmux_ctx.download_state = 0;
            luat_cmux_write(LUAT_CMUX_CH_DOWNLOAD,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
        }else if(CMUX_CONTROL_ISUIH(buff) && cmux_ctx.download_state == 1){
            uih_download_manage(buff,len);
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

//0 成功解析 1 解析头 -1 解析错误丢弃
static int luat_cmux_parse(unsigned char* cmux_buff, int* start, int* end, int cmux_buff_offset){
    // LLOGD("luat_cmux_parse start %d",*start);
    int length_needed = 5; /* channel, type, length, fcs, flag */
    if (cmux_buff[*start]==CMUX_HEAD_FLAG_BASIC&&cmux_buff[*start+1]==CMUX_HEAD_FLAG_BASIC){
        if (cmux_buff[*start+2]>>2!=LUAT_CMUX_CH_MAIN && cmux_buff[*start+2]>>2!=LUAT_CMUX_CH_SHELL && cmux_buff[*start+2]>>2!=LUAT_CMUX_CH_LOG && cmux_buff[*start+2]>>2!=LUAT_CMUX_CH_DBG && cmux_buff[*start+2]>>2!=LUAT_CMUX_CH_DOWNLOAD ){
            (*start)++;
        }
    }
    if(cmux_buff[*start]==CMUX_HEAD_FLAG_BASIC ){
        uint8_t len = (cmux_buff[*start+3]& 254) >> 1;
        // if ((cmux_buff[*start+3] & 1) == 0){
        //     INC_BUF_POINTER(buffer,data);
        //     frame->data_length += (*data*128);
        //     fcs = cmux_crctable[fcs^*data];
        //     length_needed++;
        //     LOG_D("len_need: %d, frame_data_len: %d.", length_needed, frame->data_length);
        // }
        len += length_needed;
        // for (size_t i = 0; i < 15; i++){
        //     LLOGD("buff[%d]:%02X",i,cmux_buff[i]);
        // }
        // LLOGD("luat_cmux_parse start %d",*start);
        // LLOGD("cmux_buff[*start+len] %02X",cmux_buff[*start+len]);
        if(*start+len<cmux_buff_offset){
            if(cmux_buff[*start+len]==CMUX_HEAD_FLAG_BASIC && cmux_frame_check(cmux_buff+*start+1,3) == cmux_buff[*start+len-1]){
                *end = *start+len;
                // LLOGD("luat_cmux_parse OK");
                return 0;
            }else{
                return -1;
            }
        }
        // LLOGD("luat_cmux_parse start %d",*start);
        return 1;
    }
    return -1;
}

static unsigned char *cmux_buff;
static int cmux_buff_offset = 0;

void luat_cmux_read(unsigned char* buff,size_t len){
    // for (size_t i = 0; i < len; i++){
    //     LLOGD("uart_buff[%d]:0x%02X",i,buff[i]);
    // }
    if (cmux_buff == NULL) {
        cmux_buff = luat_heap_malloc(CMUX_BUFFER_SIZE);
        if (cmux_buff == NULL) {
            luat_shell_write("cmux buff malloc FAIL!!", 23);
            return;
        }
    }

    int start,end;
    if (cmux_buff_offset + len >= CMUX_BUFFER_SIZE) {
        luat_shell_write("cmux overflow!!!",16);
        cmux_buff_offset = 0;
        return;
    }
    memcpy(cmux_buff + cmux_buff_offset, buff, len);
    cmux_buff_offset = cmux_buff_offset + len;
    cmux_buff[cmux_buff_offset] = 0x00;
    // int offset = 0;
next_parse:
    start = 0;
    end = 0;
    // LLOGD("cmux_buff_offset %d",cmux_buff_offset);
    while (start < cmux_buff_offset) {
        // 解析
        int ret = luat_cmux_parse(cmux_buff, &start, &end, cmux_buff_offset);
        // int ret = 0; // 因为没有luat_cmux_parse
        // end = cmux_buff_offset;// 
        if (ret == 0) {
            // 读取ok, 是完整的一帧, 让luat_cmux_exec按帧格式进行执行
            // 把luat_cmux_read2 当exec用
            // luat_cmux_read2(cmux_buff + start, end+1 - start);
            // unsigned char* sendcmux_frame_buf = (unsigned char*)luat_heap_malloc(end+1-start-2);
            // memmove(sendcmux_frame_buf, cmux_buff + start, end+1-start-2);
            // cmux_frame_manage(sendcmux_frame_buf,end+1-start-2);
            // luat_heap_free(sendcmux_frame_buf);
            cmux_frame_manage(cmux_buff + start,end+1-start-2);
            // LLOGD("end %d cmux_buff_offset %d",end,cmux_buff_offset);
            if (end+1<cmux_buff_offset){
                char* transfer_buff = (char*)luat_heap_malloc(cmux_buff_offset-end);
                memmove(transfer_buff, cmux_buff + end+1, cmux_buff_offset-end);
                memset(cmux_buff,0,CMUX_BUFFER_SIZE);
                memmove(cmux_buff, transfer_buff, cmux_buff_offset-end);
                cmux_buff_offset = cmux_buff_offset-end;
                luat_heap_free(transfer_buff);
                // for (size_t i = 0; i < cmux_buff_offset; i++){
                //     LLOGD("uart_buff[%d]:0x%02X",i,cmux_buff[i]);
                // }
                goto next_parse;
                // return;
            }
            break;
        }
        else if (ret == 1) {
            // LLOGD("luat_cmux_parse start %d cmux_buff_offset %d",start,cmux_buff_offset);
            // // 缺数据
            // if (start!=0){
            //     char* transfer_buff;
            //     memmove(transfer_buff, cmux_buff + start, cmux_buff_offset-start+1);
            //     memset(cmux_buff,0,CMUX_BUFFER_SIZE);
            //     memmove(cmux_buff, transfer_buff, cmux_buff_offset-start+1);
            //     LLOGD("cmux_buff %02X %02X",cmux_buff[0],cmux_buff[1]);
            //     cmux_buff_offset = cmux_buff_offset-start+1;
            // }
            return;
        }
        else {
            //解析错误丢弃
            start++;
        }
        // LLOGD("luat_cmux_read start %d",start);
        // 等luat_cmux_read2改完再按情况跳出
        // break;
    }
    memset(cmux_buff,0,CMUX_BUFFER_SIZE);
    cmux_buff_offset =  0;
}
