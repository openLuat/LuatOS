
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

extern uint8_t cmux_state;

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
    postfix[0] = cmux_frame_check(prefix+1, prefix_length - 1);
    if (len > 0)luat_shell_write(buff, len);
    luat_shell_write(postfix, 2);
}
void luat_cmux_read(unsigned char* buff,size_t len){
    // if (buff[0]==CMUX_HEAD_FLAG_BASIC && buff[len-1]==CMUX_HEAD_FLAG_BASIC && cmux_frame_check(buff+1,len-3)==buff[len-2]){
    if (buff[0]==CMUX_HEAD_FLAG_BASIC && buff[len-1]==CMUX_HEAD_FLAG_BASIC){
        if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_MAIN){
            if (CMUX_CONTROL_ISSABM(buff)){
                luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UA & ~ CMUX_CONTROL_PF,NULL, 0);
            }else if(CMUX_CONTROL_ISDISC(buff)){
                luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UA | CMUX_CONTROL_PF,NULL, 0);
                cmux_state = 0;
            }else if(CMUX_CONTROL_ISUIH(buff)){
                char send_buff[128] = {0};
                unsigned char *data = (unsigned char *)luat_heap_malloc(buff[3]>>1);
                memcpy(data, buff+4, buff[3]>>1);
                if (strncmp("AT\r", data,3) == 0){
                    luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r", 3);
                }else if (strncmp("ATI", data,3) == 0){
                    #ifdef LUAT_BSP_VERSION
                        sprintf(send_buff, "LuatOS-SoC_%s_%s\r\n", luat_os_bsp(), LUAT_BSP_VERSION);
                    #else
                        sprintf(send_buff, "LuatOS-SoC_%s_%s\r\n", luat_os_bsp(), luat_version_str());
                    #endif
                    luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
                    luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r", 3);
                }else if (strncmp("AT+LUAFLASHSIZE?", data,16) == 0){
                    #ifdef FLASH_FS_REGION_SIZE
                        sprintf(send_buff, "+LUAFLASHSIZE: 0X%x\r",FLASH_FS_REGION_SIZE);
                        luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,send_buff, strlen(send_buff));
                        luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r", 3);
                    #endif
                }else if (strncmp("AT+LUACHECKSUM=", data,15) == 0){
                    luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"+LUAFLASHSIZE: 0\r", 17);
                    luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r", 3);
                }else if (strncmp("AT+RESET", data,8) == 0){
                    luat_cmux_write(LUAT_CMUX_CH_MAIN,  CMUX_FRAME_UIH & ~ CMUX_CONTROL_PF,"OK\r", 3);
                    luat_os_reboot(0);
                }
                luat_heap_free(data);
            }
        }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_LOG){
            if (CMUX_CONTROL_ISSABM(buff)){
                luat_cmux_write(LUAT_CMUX_CH_LOG,  CMUX_FRAME_UA & ~ CMUX_CONTROL_PF,NULL, 0);
            }
        }else if (CMUX_ADDRESS_DLC(buff)==LUAT_CMUX_CH_DBG){
            if (CMUX_CONTROL_ISSABM(buff)){
                luat_cmux_write(LUAT_CMUX_CH_DBG,  CMUX_FRAME_UA & ~ CMUX_CONTROL_PF,NULL, 0);
            }else if(CMUX_CONTROL_ISUIH(buff)){
                char send_buff[128] = {0};
                unsigned char *data = (unsigned char *)luat_heap_malloc(buff[3]>>1);
                memcpy(data, buff+4, buff[3]>>1);
                if (strcmp("dbg",strtok(data, " ")) == 0){
                    char *command = strtok(NULL, " ");
                    if (strcmp("start",command) == 0){
                        luat_dbg_set_hook_state(2);
                    }else if(strcmp("continue",command) == 0){
                        luat_dbg_set_hook_state(2);
                    }else if(strcmp("next",command) == 0 || strcmp("step",command) == 0){
                        luat_dbg_set_hook_state(4);
                    }else if(strcmp("stepIn",command) == 0 || strcmp("stepin",command) == 0){
                        luat_dbg_set_hook_state(5);
                    }else if(strcmp("stepOut",command) == 0 || strcmp("stepout",command) == 0){
                        luat_dbg_set_hook_state(6);
                    }else if(strcmp("bt",command) == 0){
                        char *params = strtok(NULL, " ");
                        if (params != NULL){
                            luat_dbg_set_runcb(luat_dbg_backtrace, (void*)atoi(params));
                        }else{
                            luat_dbg_set_runcb(luat_dbg_backtrace, (void*)-1);
                        }
                    }else if(strcmp("vars",command) == 0){
                        char *params = strtok(NULL, " ");
                        if (params != NULL){
                            luat_dbg_set_runcb(luat_dbg_vars, (void*)atoi(params));
                        }else{
                            luat_dbg_set_runcb(luat_dbg_vars, (void*)0);
                        }
                    }else if(strcmp("gvars",command) == 0){
                        luat_dbg_gvars((void*)0);
                    }else if(strcmp("jvars",command) == 0){
                        luat_dbg_jvars(strtok(NULL, " "));
                    }else if(strcmp("break",command) == 0){
                        char *sub_command = strtok(NULL, " ");
                        if (strcmp("clr",sub_command) == 0){
                            luat_dbg_breakpoint_clear(strtok(NULL, " "));
                        }else if (strcmp("add",sub_command) == 0){
                            luat_dbg_breakpoint_add(strtok(NULL, " "),atoi(strtok(NULL, " ")));
                        }else if (strcmp("del",sub_command) == 0){
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
        }
    }
    else if (buff[0]==CMUX_HEAD_FLAG_ADV && buff[len-1]==CMUX_HEAD_FLAG_ADV && cmux_frame_check(buff+1,len-3)==buff[len-2]){
    }
    else{
    }
}