#include "i2c_utils.h"
#define LUAT_LOG_TAG "i2c tools"
#include "luat_log.h"

static char i2c_tools_data[I2C_TOOLS_BUFFER_SIZE] = {0};
void i2c_tools(const char * data,size_t len){
    memcpy(i2c_tools_data, data+9, len-9); 
    char *command = strtok(i2c_tools_data, " ");
    if (memcmp("send", command, 4) == 0){
        int i2c_id = atoi(strtok(NULL, " "));
        i2c_init(i2c_id);
        uint8_t address = strtonum(strtok(NULL, " "));
        uint8_t* send_buff;
        uint8_t len = 0;
        while (1){
            char* buff = strtok(NULL, " ");
            if (buff == NULL)
                break;
            send_buff[len] = strtonum(buff);
            len++;
        }
        if(i2c_write(address, send_buff, len)!=1){
            LLOGI("[i2c] write to %s failed", address);
        }
    }else if(memcmp("recv",command,4) == 0){
        uint8_t buffer[I2C_TOOLS_BUFFER_SIZE] = {0};
        int i2c_id = atoi(strtok(NULL, " "));
        i2c_init(i2c_id);
        uint8_t address = strtonum(strtok(NULL, " "));
        uint8_t reg = strtonum(strtok(NULL, " "));
        uint8_t len = atoi(strtok(NULL, " "));
        if (len == 0)
            len == 1;
        if( i2c_read(address, reg,buffer,len)!=1){
            printf("[ ");
            for(uint8_t i = 0; i < len; i++){
                printf("0x%02X", buffer[i]);
                if(i != (len-1)){
                    printf(", ");
                }
            }
            printf(" ]\n");
        }
    }else if(memcmp("scan",command,4) == 0){
        int i2c_id = atoi(strtok(NULL, " "));
        i2c_init(i2c_id);
        i2c_scan();
    }else{
        i2c_help();
    }
}