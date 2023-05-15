/**
 * @copyright (C) 2017 Melexis N.V.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#include "luat_base.h"
#include "luat_malloc.h"
#include "MLX90640_I2C_Driver.h"

extern mlx90640_i2c_t mlx90640_i2c;

void MLX90640_I2CInit(void)
{   

}

int MLX90640_I2CRead(uint8_t slaveAddr, uint16_t startAddress, uint16_t nMemAddressRead, uint16_t *data)
{
    int ret = 0;  
    int cnt = 0;
    int i = 0;
    char* i2cData = NULL;
    uint16_t *p;
    p = data;
    char cmd[2] = {0,0};
    cmd[0] = startAddress >> 8;
    cmd[1] = startAddress & 0x00FF;

    i2cData = (char *)luat_heap_malloc(2*nMemAddressRead);
    
    if (mlx90640_i2c.i2c_id == -1){
        ret = i2c_soft_send(mlx90640_i2c.ei2c, slaveAddr, (char*)cmd, 2,0);
        ret = i2c_soft_recv(mlx90640_i2c.ei2c, slaveAddr, (char*)i2cData, 2*nMemAddressRead);
    }else{
        ret = luat_i2c_transfer(mlx90640_i2c.i2c_id, slaveAddr, (uint8_t*)cmd, 2, (uint8_t*)i2cData, 2*nMemAddressRead);
    }
    
    if (ret != 0){
        luat_heap_free(i2cData);
        return -1;
    }
    for(cnt=0; cnt < nMemAddressRead; cnt++)
    {
        i = cnt << 1;
        *p++ = (uint16_t)i2cData[i]*256 + (uint16_t)i2cData[i+1];
    }
    luat_heap_free(i2cData);
    return 0;   
} 

int MLX90640_I2CWrite(uint8_t slaveAddr, uint16_t writeAddress, uint16_t data)
{
    int ret = 0; 
    static uint16_t dataCheck;
    uint8_t cmd[4];
    cmd[0] = writeAddress >> 8;
    cmd[1] = writeAddress & 0x00FF;
    cmd[2] = data >> 8;
    cmd[3] = data & 0x00FF;

    if (mlx90640_i2c.i2c_id == -1){
        ret = i2c_soft_send(mlx90640_i2c.ei2c, slaveAddr, (char*)cmd, 4,0);
    }else{
        ret = luat_i2c_send(mlx90640_i2c.i2c_id, slaveAddr, cmd, 4,0);
        if (ret != 0)return -1;
    }
    ret = MLX90640_I2CRead(slaveAddr,writeAddress,1, &dataCheck);
    if (ret != 0)return -1;

    if ( dataCheck != data)
    {
        return -2;
    }    
    
    return 0;
}

