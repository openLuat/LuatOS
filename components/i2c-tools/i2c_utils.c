#include "i2c_utils.h"
#include "luat_i2c.h"

static uint8_t i2c_tools_id = 0;

uint8_t strtonum(const char* str){
    uint8_t data;
    if (strcmp(str, "0x")){
        data = (uint8_t)strtol(str, NULL, 0);
    }else{
        data = atoi(str);
    }
    return data;
}

void i2c_help(void){
    printf_("\n---------------i2c tools help:---------------\n");
    printf_("i2c tools scan i2c_id\n");
    printf_("i2c tools recv i2c_id address register [len=1]\n");
    printf_("i2c tools send i2c_id address [register] data_0 data_1 ...\n\n");
}

uint8_t i2c_init(const uint8_t i2c_id){
    i2c_tools_id = i2c_id;
    return (luat_i2c_setup(i2c_tools_id, 1, NULL));
}

uint8_t i2c_probe(char addr){
	uint8_t data[2] = {0x00};
    return (luat_i2c_send(i2c_tools_id, addr, data, 2,1) ==0);
}

uint8_t i2c_write(char addr, uint8_t* data, int len){
    return (luat_i2c_send(i2c_tools_id, addr, data, len,1) == 0);
}

uint8_t i2c_read(uint8_t addr, uint8_t reg, uint8_t* buffer, uint8_t len){
    int ret = 0;
    ret = luat_i2c_send(i2c_tools_id, addr, &reg, 1,0);
    if (ret != 0)return -1;
    ret = luat_i2c_recv(i2c_tools_id, addr, buffer, len);
    if (ret != 0)return -1;
    return 0;
}

void i2c_scan(void){
    printf_("     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f\n");
    for(unsigned char i=0; i<8; i++){
        printf_("%d0: ", i);
        for(unsigned char j=0; j<16; j++){
            char addr = i*16+j;
            if( i2c_probe(addr) == 1){
                printf_("%02X", addr);
            }else{
                printf_("--");
            }
            printf_(" ");
        }
        printf_("\n");
    }
}
