
#include "little_flash.h"
#include "little_flash_table.h"

extern lf_err_t little_flash_port_init(little_flash_t *lf);

static const little_flash_chipinfo_t little_flash_table[] = LITTLE_FLASH_CHIP_TABLE;

lf_err_t little_flash_write_status(const little_flash_t *lf, uint8_t address, uint8_t status){
    lf_err_t result = LF_ERR_OK;
    uint8_t cmd_data[3]={0};
    cmd_data[0]=LF_CMD_WRITE_STATUS_REGISTER;
    if (address){
        cmd_data[1]=address;
        cmd_data[2]=status;
    }else{
        cmd_data[1]=status;
    }
    result = lf->spi.transfer(lf,cmd_data, address?3:2,LF_NULL,0);
    return result;
}

lf_err_t little_flash_read_status(const little_flash_t *lf, uint8_t address, uint8_t *status){
    lf_err_t result = LF_ERR_OK;
    uint8_t cmd_data[2]={0};
    cmd_data[0]=LF_CMD_READ_STATUS_REGISTER;
    if (address){
        cmd_data[1]=address;
    }
    result = lf->spi.transfer(lf,cmd_data, address?2:1,status,1);
    return result;
}


static lf_err_t little_flash_wait_busy(const little_flash_t *lf) {
    lf_err_t result = LF_ERR_OK;
    size_t retry_times = lf->chip_info.retry_times;
    uint8_t status;
    while (true) {
        if (lf->chip_info.type==LF_DRIVER_NOR_FLASH){
            result = little_flash_read_status(lf, 0, &status);
        }else{
            result = little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        }
        // LF_DEBUG("status 0x%02x",status);
        if (result==LF_ERR_OK && (status&LF_STATUS_REGISTER_BUSY)==0){
            return LF_ERR_OK;
        }
        retry_times--;
        if (retry_times == 0) {
            LF_ERROR("Error: Wait busy timeout.");
            return LF_ERR_TIMEOUT;
        }else{
            lf->wait_10us(1);
        }
    }
    return result;
}

/* 
    reset device
*/
static lf_err_t little_flash_reset(little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    result |= little_flash_wait_busy(lf);
    if(lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_ENABLE_RESET}, 1,LF_NULL,0);
        result |= little_flash_wait_busy(lf);
        if (result) return result;
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_NORFLASH_RESET}, 1,LF_NULL,0);
    }else{
        // nand flash
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_NANDFLASH_RESET}, 1,LF_NULL,0);
    }

    lf->wait_10us(100);
    result |= little_flash_wait_busy(lf);
    if (result) return result;
    if(lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        if(lf->chip_info.prog_size==0) lf->chip_info.prog_size = LF_NORFLASH_PAGE_ZISE;
        if(lf->chip_info.read_size==0) lf->chip_info.read_size = LF_NORFLASH_PAGE_ZISE;
        // 以下需要根据型号进行适配
        result |= little_flash_write_status(lf,0,0x00);
    }else{
        if(lf->chip_info.prog_size==0) lf->chip_info.prog_size = LF_NANDFLASH_PAGE_ZISE;
        if(lf->chip_info.read_size==0) lf->chip_info.read_size = LF_NANDFLASH_PAGE_ZISE;
        // 以下需要根据型号进行适配
        result |= little_flash_write_status(lf,LF_NANDFLASH_STATUS_REGISTER1,0x00);
        // ECC-E = 1, BUF = 1
        result |= little_flash_write_status(lf,LF_NANDFLASH_STATUS_REGISTER2,(1 << 4) | (1 << 3));
    }
    if(lf->chip_info.retry_times==0) lf->chip_info.retry_times = LF_RETRY_TIMES;
            
    return result;
}

static lf_err_t little_flash_write_enabled(const little_flash_t *lf, uint8_t enable){
    lf_err_t result = LF_ERR_OK;
    uint8_t status;
    lf->spi.transfer(lf,enable?(uint8_t[]){LF_CMD_WRITE_ENABLE}:(uint8_t[]){LF_CMD_WRITE_DISABLE}, 1,LF_NULL,0);

    result = little_flash_wait_busy(lf);
    if (result) return result;

    if (lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        result |= little_flash_read_status(lf, 0, &status);
    }else{
        result |= little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
    }
    if (result) return result;
    if (enable && (status & LF_STATUS_REGISTER_WEL) == 0) {
        LF_ERROR("Error: Can't enable write status.");
        result = LF_ERR_WRITE;
    } else if (!enable && (status & LF_STATUS_REGISTER_WEL) != 0) {
        LF_ERROR("Error: Can't disable write status.");
        result = LF_ERR_WRITE;
    }

    return result;
}

lf_err_t little_flash_init(void){
    LF_INFO("Welcome to use little flash V%s .", LF_SW_VERSION);
    LF_INFO("Github Repositories https://github.com/Dozingfiretruck/little_flash .");
    LF_INFO("Gitee Repositories https://gitee.com/Dozingfiretruck/little_flash .");
    return LF_ERR_OK;
}

#ifdef LF_USE_SFDP
lf_err_t little_flash_sfdp_read(const little_flash_t *lf, uint32_t offset, uint8_t *data, size_t size){
    lf_err_t result = LF_ERR_OK;
    uint8_t cmd_data[]={LF_CMD_SFDP_REGISTER,(uint8_t)(offset>>16),(uint8_t)(offset>>8),(uint8_t)(offset),0XFF};
    result = lf->spi.transfer(lf,cmd_data, sizeof(cmd_data), data, size);
    return result;
}

lf_err_t little_flash_sfdp_probe(little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    little_flash_sfdp_t sfdp;
    uint8_t recv_data[8]={0};
    little_flash_sfdp_read(lf, LF_CMD_SFDP_HEADER, recv_data, sizeof(recv_data));
    if (recv_data[0]!='S' || recv_data[1]!='F' || recv_data[2]!='D' || recv_data[3]!='P'){
        LF_DEBUG("SFDP header not found.");
        return LF_ERR_SFDP_HEADER;
    }

    sfdp.minor_rev=recv_data[4];
    sfdp.major_rev=recv_data[5];
    sfdp.nph=recv_data[6];
    sfdp.access_protocol=recv_data[7];
    if (sfdp.access_protocol == 0xFA || (sfdp.access_protocol >= 0xFC && sfdp.access_protocol <= 0xFF)){
        lf->chip_info.type |= LF_DRIVER_NOR_FLASH;
    }else if((sfdp.access_protocol >= 0xF1 && sfdp.access_protocol <= 0xF7)){
        lf->chip_info.type |= LF_DRIVER_NAND_FLASH;
    }else{
        LF_ERROR("Error: Access protocol 0x%02X is not supported.", sfdp.access_protocol);
        return LF_ERR_SFDP_PARAMETER;
    }

    if (sfdp.major_rev>LF_SFDP_MAJOR_REV || sfdp.minor_rev>LF_SFDP_MINOR_REV){
        LF_ERROR("Error: SFDP version %d.%d is not supported.", sfdp.major_rev, sfdp.minor_rev);
        return LF_ERR_SFDP_PARAMETER;
    }
    
    LF_DEBUG("Found SFDP Header. The Revision is V%d.%d, NPN is %d, Access Protocol is 0x%X.",
            sfdp.major_rev, sfdp.minor_rev, sfdp.nph, sfdp.access_protocol);

    little_flash_sfdp_read(lf, LF_CMD_SFDP_PARAMETER_HEADER1, recv_data, sizeof(recv_data));

    sfdp.parameter_id = (uint16_t)recv_data[0] | (uint16_t)recv_data[7] << 8;
    sfdp.parameter_minor_rev = recv_data[1];
    sfdp.parameter_major_rev = recv_data[2];
    sfdp.parameter_length = recv_data[3];
    sfdp.parameter_pointer = (uint32_t)recv_data[4] | (uint32_t)recv_data[5] << 8 | (uint32_t)recv_data[6] << 16;

    if (sfdp.parameter_id!=0xFF00){
        LF_ERROR("Error: SFDP Parameter ID 0x%04X.",sfdp.parameter_id);
        return LF_ERR_SFDP_PARAMETER;
    }

    if (sfdp.parameter_major_rev > LF_SFDP_MAJOR_REV) {
        LF_ERROR("Error: SFDP Parameter Table Revision %d.%d is not supported.", sfdp.parameter_major_rev, sfdp.parameter_minor_rev);
        return LF_ERR_SFDP_PARAMETER;
    }
    if (sfdp.parameter_length < 9) {
        LF_DEBUG("Error: The Parameter Table Length is %d.", sfdp.parameter_length);
        return LF_ERR_SFDP_PARAMETER;
    }
    LF_DEBUG("Parameter Header is OK. The Parameter ID is 0x%04X, Revision is V%d.%d, Length is %d,Parameter Table Pointer is 0x%06lX.",
            sfdp.parameter_id, recv_data[1],recv_data[2],sfdp.parameter_length, sfdp.parameter_pointer);
    uint8_t parameter_table[sfdp.parameter_length * 4];
    little_flash_sfdp_read(lf, sfdp.parameter_pointer, parameter_table, sfdp.parameter_length);

    //      [1] = 0xE5    0x20    0xF1    0xFF
    //      [2] = 0xFF    0xFF    0xFF    0x07
    //      [3] = 0x44    0xD3    0x8B    0x00
    //      [4] = 0xAB    0x13    0x9A    0x00
    //      [5] = 0xA7    0xD3    0x8B    0x00
    //      [6] = 0x00    0xFF    0x00    0x00
    //      [7] = 0x00    0x00    0x00    0x00
    //      [8] = 0x01    0x00    0x00    0x00
    //      [9] = 0x09    0x00    0x00    0x00

    memcpy(&sfdp.pt, parameter_table, sfdp.parameter_length*4);
    LF_DEBUG("sfdp.pt Flash_Memory_Density 0x%08X",sfdp.pt.Flash_Memory_Density);

    if (sfdp.pt.Flash_Memory_Density & 0x80000000){
        lf->chip_info.capacity = sfdp.pt.Flash_Memory_Density;
        lf->chip_info.capacity &= 0x7FFFFFFF;
        lf->chip_info.capacity = 1L << (lf->chip_info.capacity - 3);
    }else{
        lf->chip_info.capacity = (sfdp.pt.Flash_Memory_Density+1)>>3;
    }
    

    if (sfdp.pt.Erase_Sizes==1 && sfdp.pt.Erase_4k){
        lf->chip_info.erase_cmd = sfdp.pt.Erase_4k;
        lf->chip_info.erase_size = 4096;
    }
    
    if (sfdp.pt.Write_Granularity){
        lf->chip_info.prog_size = 256;
    }else{
        lf->chip_info.prog_size = 1;
    }
    // Address Bytes
    if (sfdp.pt.Address_Bytes == 0){
        lf->chip_info.addr_bytes |= LF_ADDR_BYTES_3;
    }else if (sfdp.pt.Address_Bytes == 1){
        lf->chip_info.addr_bytes |= LF_ADDR_BYTES_3;
        lf->chip_info.addr_bytes |= LF_ADDR_BYTES_4;
    }else if (sfdp.pt.Address_Bytes == 2){
        lf->chip_info.addr_bytes |= LF_ADDR_BYTES_4;
    }


    // LF_DEBUG("capacity %d",lf->chip_info.capacity);
    // LF_DEBUG("erase_cmd 0x%02X",lf->chip_info.erase_cmd);
    // LF_DEBUG("erase_size %d",lf->chip_info.erase_size);
    // LF_DEBUG("prog_size %d",lf->chip_info.prog_size);
    // LF_DEBUG("addr_bytes 0x%02X",lf->chip_info.addr_bytes);

    return result;
}
#endif /* LF_USE_SFDP */

lf_err_t little_flash_device_init(little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint8_t manufacturer_id = 0;
    uint16_t device_id = 0;
    little_flash_port_init(lf);
    LF_ASSERT(lf->wait_10us);
    LF_ASSERT(lf->spi.transfer);
#ifdef LF_USE_HEAP
    LF_ASSERT(lf->malloc);
    LF_ASSERT(lf->free);
#endif
#ifdef LF_USE_SFDP
    result = little_flash_sfdp_probe(lf);
    if (result == LF_ERR_OK){
        return little_flash_reset(lf);
    }
#endif
    uint8_t recv_data[4]={0};
    result = lf->spi.transfer(lf,(uint8_t[]){LF_CMD_JEDEC_ID}, 1, recv_data, sizeof(recv_data));
    if(result) return result;
    if (recv_data[0]!=0xFF){
        manufacturer_id = recv_data[0];
        device_id = recv_data[1]<<8|recv_data[2];
    }else{
        manufacturer_id = recv_data[1];
        device_id = recv_data[2]<<8|recv_data[3];
    }

    for (size_t i = 0; i < sizeof(little_flash_table)/sizeof(little_flash_table[0]); i++){
        if (manufacturer_id==little_flash_table[i].manufacturer_id && device_id ==little_flash_table[i].device_id){
            memcpy(&lf->chip_info.name,&little_flash_table[i],sizeof(little_flash_chipinfo_t));
            LF_DEBUG("JEDEC ID: manufacturer_id:0x%02X device_id:0x%04X ",little_flash_table[i].manufacturer_id,little_flash_table[i].device_id);
            LF_DEBUG("little flash fonud flash %s",lf->chip_info.name);
            result = little_flash_reset(lf);
            return result;
        }
    }
    LF_DEBUG("NOT fonud flash");
    return LF_ERR_NO_FLASH;
}

lf_err_t little_flash_device_deinit(little_flash_t *lf){



    return LF_ERR_OK;
}

lf_err_t little_flash_deinit(void){
    return LF_ERR_OK;
}

static lf_err_t little_flash_cheak_erase(const little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint8_t status;
    result |= little_flash_wait_busy(lf);
    if (result) return result;
    if(lf->chip_info.type==LF_DRIVER_NAND_FLASH){
        result |= little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        if (result || (status&0x04)){
            return LF_ERR_ERASE;
        }
    }
    return result;
}

static lf_err_t little_flash_cheak_write(const little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint8_t status;
    result |= little_flash_wait_busy(lf);
    if (result) return result;
    if(lf->chip_info.type==LF_DRIVER_NAND_FLASH){
        result |= little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        if (result||(status&0x08)){
            return LF_ERR_WRITE;
        }
    }
    return result;
}

static lf_err_t little_flash_cheak_read(const little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint8_t status;
    result |= little_flash_wait_busy(lf);
    if (result) return result;
    if(lf->chip_info.type==LF_DRIVER_NAND_FLASH){
        result |= little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        // 以下也是要根据不同型号移植的
        uint8_t ecc = (status & 0x30) >> 4;
        if (result==0 && ecc<2){
            return LF_ERR_OK;
        }
    }
    return result;
}

lf_err_t little_flash_chip_erase(const little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint32_t addr = 0;
    uint8_t cmd_data[4];

    if (lf->lock) {
        lf->lock(lf);
    }

    result |= little_flash_write_enabled(lf, LF_ENABLE);
    if(result) goto error;
    if(lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_ERASE_CHIP}, 1,LF_NULL,0);
        lf->wait_10us(4000000);
        result |= little_flash_cheak_erase(lf);
    }else{
        cmd_data[0] = lf->chip_info.erase_cmd;
        while (true){
            uint32_t page_addr = addr/lf->chip_info.prog_size;
            cmd_data[1] = page_addr >> 16;
            cmd_data[2] = page_addr >> 8;
            cmd_data[3] = page_addr;
            result |= lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
            if(result) goto error;
            lf->wait_10us(200);
            result |= little_flash_cheak_erase(lf);
            if(result) goto error;
            addr += lf->chip_info.erase_size;
            if (addr>=lf->chip_info.capacity){
                break;
            }
        }
    }
    result |= little_flash_write_enabled(lf, LF_DISABLE);
    if (result) goto error;
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_ERASE;
}

lf_err_t little_flash_erase(const little_flash_t *lf, uint32_t addr, uint32_t len){
    lf_err_t result = LF_ERR_OK;
    uint8_t cmd_data[4]={0};
    if (addr + len > lf->chip_info.capacity) {
        LF_ERROR("Error: Flash address is out of bound.");
        return LF_ERR_BAD_ADDRESS;
    }

    if (addr == 0 && len == lf->chip_info.capacity) {
        return little_flash_chip_erase(lf);
    }

    if (lf->lock) {
        lf->lock(lf);
    }

    result = little_flash_write_enabled(lf, LF_ENABLE);
    if(result) goto error;
    cmd_data[0] = lf->chip_info.erase_cmd;
    while (len){
        uint32_t page_addr = addr/lf->chip_info.prog_size;
        cmd_data[1] = page_addr >> 16;
        cmd_data[2] = page_addr >> 8;
        cmd_data[3] = page_addr;
        result |= lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
        if(result) goto error;
        lf->wait_10us(200);
        result |= little_flash_cheak_erase(lf);
        if(result) goto error;
        addr += lf->chip_info.erase_size;
        if (len<=lf->chip_info.erase_size){
            break;
        }else{
            len -= lf->chip_info.erase_size;
        }
    }
    result |= little_flash_write_enabled(lf, LF_DISABLE);
    if (result) goto error;

    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_READ;
}


lf_err_t little_flash_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len){
    lf_err_t result = LF_ERR_OK;
#ifdef LF_USE_HEAP
    uint8_t* cmd_data = (uint8_t*)lf->malloc(4+lf->chip_info.prog_size);
    if (!cmd_data){
        LF_ERROR("Error: malloc failed.");
        return LF_ERR_NO_MEM;
    }
#else
    uint8_t cmd_data[4+lf->chip_info.prog_size];
#endif /* LF_USE_HEAP */
    uint32_t base_addr = addr;
    
    if (lf->lock) {
        lf->lock(lf);
    }

    result = little_flash_write_enabled(lf, LF_ENABLE);
    if(result) goto error;
    while (len){
        result |= little_flash_wait_busy(lf);
        if(result) goto error;
        
        if (lf->chip_info.type==LF_DRIVER_NOR_FLASH){
            cmd_data[0] = LF_CMD_PROG_DATA;
            cmd_data[1] = addr >> 16;
            cmd_data[2] = addr >> 8;
            cmd_data[3] = addr;

            uint16_t column_addr = addr%lf->chip_info.prog_size;
            if (column_addr){
                if ((column_addr+len)<=lf->chip_info.prog_size){
                    memcpy(&cmd_data[4],&data[addr-base_addr],len);
                    lf->spi.transfer(lf,cmd_data, 4+len,LF_NULL,0);
                    break;
                }else{
                    memcpy(&cmd_data[4],&data[addr-base_addr],lf->chip_info.prog_size-column_addr);
                    lf->spi.transfer(lf,cmd_data, 4+lf->chip_info.prog_size-column_addr,LF_NULL,0);
                    len -= (lf->chip_info.prog_size-column_addr);
                    addr += (lf->chip_info.prog_size-column_addr);
                }
            }else{
                if (len<=lf->chip_info.prog_size){
                    memcpy(&cmd_data[4],&data[addr-base_addr],len);
                    lf->spi.transfer(lf,cmd_data, 4+len,LF_NULL,0);
                    break;
                }else{
                    memcpy(&cmd_data[4],&data[addr-base_addr],lf->chip_info.prog_size);
                    lf->spi.transfer(lf,cmd_data, 4+lf->chip_info.prog_size,LF_NULL,0);
                    len -= lf->chip_info.prog_size;
                    addr += lf->chip_info.prog_size;
                }
            }
        }else{
            uint32_t page_addr = addr/lf->chip_info.prog_size;
            uint16_t column_addr = addr%lf->chip_info.prog_size;
            cmd_data[0] = LF_CMD_PROG_DATA;
            cmd_data[1] = column_addr >> 8;
            cmd_data[2] = column_addr;
            if (column_addr){
                if ((column_addr+len)<=lf->chip_info.prog_size){
                    memcpy(&cmd_data[3],&data[addr-base_addr],len);
                    lf->spi.transfer(lf,cmd_data, 3+len,LF_NULL,0);
                    little_flash_wait_busy(lf);
                    cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
                    cmd_data[1] = page_addr >> 16;
                    cmd_data[2] = page_addr >> 8;
                    cmd_data[3] = page_addr;
                    lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
                    little_flash_cheak_write(lf);
                    break;
                }else{
                    memcpy(&cmd_data[3],&data[addr-base_addr],lf->chip_info.prog_size-column_addr);
                    lf->spi.transfer(lf,cmd_data, 3+lf->chip_info.prog_size-column_addr,LF_NULL,0);
                    len -= (lf->chip_info.prog_size-column_addr);
                    addr += (lf->chip_info.prog_size-column_addr);
                }
            }else{
                if (len<=lf->chip_info.prog_size){
                    memcpy(&cmd_data[3],&data[addr-base_addr],len);
                    lf->spi.transfer(lf,cmd_data, 3+len,LF_NULL,0);
                    little_flash_wait_busy(lf);
                    cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
                    cmd_data[1] = page_addr >> 16;
                    cmd_data[2] = page_addr >> 8;
                    cmd_data[3] = page_addr;
                    lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
                    little_flash_cheak_write(lf);
                    break;
                }else{
                    memcpy(&cmd_data[3],&data[addr-base_addr],lf->chip_info.prog_size);
                    lf->spi.transfer(lf,cmd_data, 3+lf->chip_info.prog_size,LF_NULL,0);
                    len -= lf->chip_info.prog_size;
                    addr += lf->chip_info.prog_size;
                }
            }

            little_flash_wait_busy(lf);
            cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
            cmd_data[1] = page_addr >> 16;
            cmd_data[2] = page_addr >> 8;
            cmd_data[3] = page_addr;
            lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
            little_flash_cheak_write(lf);
        }
    }
    result |= little_flash_write_enabled(lf, LF_DISABLE);
    if (result) goto error;
#ifdef LF_USE_HEAP
    lf->free(cmd_data);
#endif /* LF_USE_HEAP */
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_WRITE;
}



lf_err_t little_flash_read(const little_flash_t *lf, uint32_t addr, uint8_t *data, uint32_t len){
    uint8_t cmd_data[4];
    uint32_t base_addr = addr;
    if (lf->lock) {
        lf->lock(lf);
    }
    if (lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        little_flash_wait_busy(lf);
        cmd_data[0] = LF_CMD_READ_DATA;
        cmd_data[1] = addr >> 16;
        cmd_data[2] = addr >> 8;
        cmd_data[3] = addr;
        lf->spi.transfer(lf,cmd_data, 4,data,len);
        if (little_flash_cheak_read(lf)){
            goto error;
        }
    }else{
        while (len){
            little_flash_wait_busy(lf);
            uint32_t page_addr = addr/lf->chip_info.prog_size;
            uint16_t column_addr = addr%lf->chip_info.prog_size;

            cmd_data[0] = LF_NANDFLASH_PAGE_DATA_READ;
            cmd_data[1] = page_addr >> 16;
            cmd_data[2] = page_addr >> 8;
            cmd_data[3] = page_addr;
            lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
            if (little_flash_cheak_read(lf)){
                goto error;
            }
            cmd_data[0] = LF_CMD_READ_DATA;
            cmd_data[1] = column_addr >> 8;
            cmd_data[2] = column_addr;
            cmd_data[3] = 0;
            if (column_addr){
                if ((column_addr+len)<=lf->chip_info.prog_size){
                    lf->spi.transfer(lf,cmd_data, 4,&data[addr-base_addr],len);
                    break;
                }else{
                    lf->spi.transfer(lf,cmd_data, 4,&data[addr-base_addr],lf->chip_info.prog_size-column_addr);
                    len -= (lf->chip_info.prog_size-column_addr);
                    addr += (lf->chip_info.prog_size-column_addr);
                }
            }else{
                if (len<=lf->chip_info.prog_size){
                    lf->spi.transfer(lf,cmd_data, 4,&data[addr-base_addr],len);
                    break;
                }else{
                    lf->spi.transfer(lf,cmd_data, 4,&data[addr-base_addr],lf->chip_info.prog_size);
                    len -= lf->chip_info.prog_size;
                    addr += lf->chip_info.prog_size;
                }
            }
        }
    }
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_READ;
}




















