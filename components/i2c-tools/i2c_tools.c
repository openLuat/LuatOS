#include "luat_base.h"
#include "i2c_utils.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "i2c tools"
#include "luat_log.h"

void i2c_tools(const char * data,size_t len){
    char *i2c_tools_data = (char *)luat_heap_malloc(len-8);
    memset(i2c_tools_data, 0, len-8); // 确保填充为0
    memcpy(i2c_tools_data, data+9, len-9); 
    char *command = strtok(i2c_tools_data, " ");
    if (memcmp("send", command, 4) == 0){
        int i2c_id = atoi(strtok(NULL, " "));
        i2c_init(i2c_id,0);
        uint8_t address = strtonum(strtok(NULL, " "));
        uint8_t send_buff[16];
        uint8_t len = 0;
        while (1){
            char* buff = strtok(NULL, " ");
            if (buff == NULL)
                break;
            send_buff[len] = strtonum(buff);
            len++;
        }
        if(i2c_write(address, send_buff, len)!=1){
            LLOGI("[i2c] write to 0x%02X failed", address);
        }
    }else if(memcmp("recv",command,4) == 0){
        int i2c_id = atoi(strtok(NULL, " "));
        i2c_init(i2c_id,0);
        uint8_t address = strtonum(strtok(NULL, " "));
        uint8_t reg = strtonum(strtok(NULL, " "));
        uint8_t len = atoi(strtok(NULL, " "));
        if (len == 0)len = 1;
        uint8_t *buffer = (uint8_t *)luat_heap_malloc(len);
        memset(buffer, 0, len); // 确保填充为0
        if( i2c_read(address, reg,buffer,len)!=1){
            char buff[64] = {0};
            sprintf_(buff, "[ ");
            for(uint8_t i = 0; i < len; i++){
                sprintf_(buff + 2 + i *4, "0x%02X", buffer[i]);
                if(i != (len-1)){
                    printf(", ");
                }
            }
            sprintf_(buff + 2 + 4*len, " ]");
            LLOGD("%s", buff);
        }
        luat_heap_free(buffer);
    }else if(memcmp("scan",command,4) == 0){
        int i2c_id = atoi(strtok(NULL, " "));
        i2c_init(i2c_id,0);
        i2c_scan();
    }else{
        i2c_help();
    }
    luat_heap_free(i2c_tools_data);
}
