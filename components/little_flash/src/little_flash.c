
#include "little_flash.h"
#include "little_flash_table.h"

extern lf_err_t little_flash_port_init(little_flash_t *lf);

static const little_flash_chipinfo_t little_flash_table[] = LITTLE_FLASH_CHIP_TABLE;

static uint32_t little_flash_prog_buf_len(const little_flash_t *lf)
{
    uint32_t len = lf->chip_info.prog_size;
    if (lf->chip_info.type == LF_DRIVER_NAND_FLASH) {
        len += lf->chip_info.spare_size;
    }
    return 4 + len;
}

lf_err_t little_flash_write_status(const little_flash_t *lf, uint8_t address, uint8_t status){
    lf_err_t result = LF_ERR_OK;
    uint8_t cmd_data[3]={0};
    cmd_data[0]=lf->chip_info.type==LF_DRIVER_NOR_FLASH?LF_CMD_NORFLASH_WRITE_STATUS_REGISTER:LF_CMD_NANDFLASH_WRITE_STATUS_REGISTER;
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
    cmd_data[0]=lf->chip_info.type==LF_DRIVER_NOR_FLASH?LF_CMD_NORFLASH_READ_STATUS_REGISTER:LF_CMD_NANDFLASH_READ_STATUS_REGISTER;
    if (address){
        cmd_data[1]=address;
    }
    result = lf->spi.transfer(lf,cmd_data, address?2:1,status,1);
    return result;
}

// timeout unit us
static lf_err_t little_flash_wait_busy(const little_flash_t *lf, uint32_t timeout) {
    lf_err_t result = LF_ERR_OK;
    size_t retry_times = lf->chip_info.retry_times;
    int32_t timeout_us;
    uint8_t status;
    if (retry_times == 0) {
        retry_times = LF_RETRY_TIMES;
    }
    while (retry_times > 0) {
        timeout_us = (int32_t)timeout;
        do {
            if (lf->chip_info.type==LF_DRIVER_NOR_FLASH){
                result = little_flash_read_status(lf, 0, &status);
            }else{
                result = little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
            }
            // LF_DEBUG("status 0x%02x",status);
            if (result==LF_ERR_OK && (status&LF_STATUS_REGISTER_BUSY)==0){
                return LF_ERR_OK;
            }
            if (timeout_us>1000){
                lf->wait_ms(1);
                timeout_us -= 1000;
            }else{
                lf->wait_10us(1);
                timeout_us -= 10;
            }
        } while (timeout_us > 0);
        retry_times--;
    }
    LF_ERROR("Error: Wait busy timeout.");
    return LF_ERR_TIMEOUT;
}

/* 
    reset device
*/
static lf_err_t little_flash_reset(little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    LF_DEBUG("little_flash_reset start");
    result |= little_flash_wait_busy(lf,1000);
    LF_DEBUG("little_flash_reset after wait_busy #1 result=%d", result);
    if(lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_ENABLE_RESET}, 1,LF_NULL,0);
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_NORFLASH_RESET}, 1,LF_NULL,0);
    }else{
        // nand flash
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_NANDFLASH_RESET}, 1,LF_NULL,0);
    }
    lf->wait_ms(50);
    result |= little_flash_wait_busy(lf,1000);
    LF_DEBUG("little_flash_reset after wait_busy #2 result=%d", result);
    if (result) return result;
    if(lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        if(lf->chip_info.prog_size==0) lf->chip_info.prog_size = LF_NORFLASH_PAGE_ZISE;
        if(lf->chip_info.read_size==0) lf->chip_info.read_size = LF_NORFLASH_PAGE_ZISE;
        if(lf->chip_info.erase_times==0) lf->chip_info.erase_times = LF_NORFLASH_ERASE_TIMES;
        // 以下需要根据型号进行适配
        result |= little_flash_write_status(lf,0,0x00);
    }else{
        if(lf->chip_info.prog_size==0) lf->chip_info.prog_size = LF_NANDFLASH_PAGE_ZISE;
        if(lf->chip_info.read_size==0) lf->chip_info.read_size = LF_NANDFLASH_PAGE_ZISE;
        if(lf->chip_info.spare_size==0) lf->chip_info.spare_size = LF_NANDFLASH_SPARE_SIZE;
        if(lf->chip_info.erase_times==0) lf->chip_info.erase_times = LF_NANDFLASH_ERASE_TIMES;
        // 以下需要根据型号进行适配
        result |= little_flash_write_status(lf,LF_NANDFLASH_STATUS_REGISTER1,0x00);
        // ECC-E = 1, BUF = 1
        result |= little_flash_write_status(lf,LF_NANDFLASH_STATUS_REGISTER2,(1 << 4) | (1 << 3));
    }
    if(lf->chip_info.retry_times==0) lf->chip_info.retry_times = LF_RETRY_TIMES;
    lf->wait_10us(5);
#ifdef LF_USE_HEAP
    /* Allocate a persistent write buffer to avoid per-call malloc in little_flash_write */
    if (lf->prog_buf == NULL && lf->malloc != NULL && lf->chip_info.prog_size > 0) {
        lf->prog_buf = (uint8_t *)lf->malloc(little_flash_prog_buf_len(lf));
    }
#endif /* LF_USE_HEAP */
    LF_DEBUG("little_flash_reset done");
    return result;
}

static lf_err_t little_flash_write_enabled(const little_flash_t *lf, uint8_t enable){
    lf_err_t result = LF_ERR_OK;
    uint8_t status;
    lf->spi.transfer(lf,enable?(uint8_t[]){LF_CMD_WRITE_ENABLE}:(uint8_t[]){LF_CMD_WRITE_DISABLE}, 1,LF_NULL,0);

    result = little_flash_wait_busy(lf,1000);
    if (result) {
        LF_ERROR("Error: Write enabled timeout.");
        return result;
    }

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
    LF_INFO("Github Repositories https://github.com/PeakRacing/little_flash .");
    LF_INFO("Gitee Repositories https://gitee.com/PeakRacing/little_flash .");
    return LF_ERR_OK;
}

#ifdef LF_USE_SFDP
static inline lf_err_t little_flash_sfdp_read(const little_flash_t *lf, uint32_t offset, uint8_t *data, size_t size){
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
        lf->chip_info.type = LF_DRIVER_NOR_FLASH;
    }else if((sfdp.access_protocol >= 0xF1 && sfdp.access_protocol <= 0xF7)){
        lf->chip_info.type = LF_DRIVER_NAND_FLASH;
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

    if (sfdp.parameter_length < sizeof(little_flash_sfdp_pt_t)/4){
        LF_WARNING("Table Revision %d.%d parameter_length %d is too short", sfdp.parameter_major_rev, sfdp.parameter_minor_rev,sfdp.parameter_length);
        return LF_ERR_SFDP_PARAMETER;
    }
    little_flash_sfdp_read(lf, sfdp.parameter_pointer, (uint8_t *)&sfdp.pt, sizeof(little_flash_sfdp_pt_t));

    //      [1] = 0xE5    0x20    0xF1    0xFF
    //      [2] = 0xFF    0xFF    0xFF    0x07
    //      [3] = 0x44    0xD3    0x8B    0x00
    //      [4] = 0xAB    0x13    0x9A    0x00
    //      [5] = 0xA7    0xD3    0x8B    0x00
    //      [6] = 0x00    0xFF    0x00    0x00
    //      [7] = 0x00    0x00    0x00    0x00
    //      [8] = 0x01    0x00    0x00    0x00
    //      [9] = 0x09    0x00    0x00    0x00

    // LF_DEBUG("sfdp.pt Flash_Memory_Density 0x%08X",sfdp.pt.Flash_Memory_Density);

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

    // LF_DEBUG("capacity: %d bytes",lf->chip_info.capacity);
    // LF_DEBUG("erase_size: %d bytes",lf->chip_info.erase_size);
    // LF_DEBUG("prog_size: %d bytes",lf->chip_info.prog_size);

    // LF_DEBUG("erase_cmd 0x%02X",lf->chip_info.erase_cmd);
    // LF_DEBUG("addr_bytes 0x%02X",lf->chip_info.addr_bytes);

    LF_DEBUG("Found a flash chip. Size is %d bytes.",lf->chip_info.capacity);

    return result;
}
#endif /* LF_USE_SFDP */

lf_err_t little_flash_device_init(little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint8_t manufacturer_id = 0;
    uint16_t device_id = 0;
    little_flash_port_init(lf);
    LF_ASSERT(lf->wait_10us);
    LF_ASSERT(lf->wait_ms);
    LF_ASSERT(lf->spi.transfer);
#ifdef LF_USE_HEAP
    LF_ASSERT(lf->malloc);
    LF_ASSERT(lf->free);
#endif
#ifdef LF_USE_SFDP
    result = little_flash_sfdp_probe(lf);
    if (result == LF_ERR_OK){
        result = little_flash_reset(lf);
        return result;
    }
#endif
    uint8_t recv_data[4]={0};
    result = lf->spi.transfer(lf,(uint8_t[]){LF_CMD_JEDEC_ID}, 1, recv_data, sizeof(recv_data));
    if(result) return result;
    // LF_DEBUG("JEDEC recv_data: %02X %02X %02X %02X", recv_data[0], recv_data[1], recv_data[2], recv_data[3]);

    // nor flash?
    manufacturer_id = recv_data[0];
    device_id = recv_data[1]<<8|recv_data[2];
    for (size_t i = 0; i < sizeof(little_flash_table)/sizeof(little_flash_table[0]); i++){
        if (manufacturer_id==little_flash_table[i].manufacturer_id && device_id ==little_flash_table[i].device_id){
            memcpy(&lf->chip_info,&little_flash_table[i],sizeof(little_flash_chipinfo_t));
            LF_DEBUG("JEDEC ID: manufacturer_id:0x%02X device_id:0x%04X ",little_flash_table[i].manufacturer_id,little_flash_table[i].device_id);
            LF_DEBUG("little flash found flash %s",lf->chip_info.name);
            LF_DEBUG("little_flash_device_init call reset");
            result = little_flash_reset(lf);
            LF_DEBUG("little_flash_device_init reset ret=%d", result);
            return result;
        }
    }
    // nand flash?
    manufacturer_id = recv_data[1];
    device_id = recv_data[2]<<8|recv_data[3];
    for (size_t i = 0; i < sizeof(little_flash_table)/sizeof(little_flash_table[0]); i++){
        if (manufacturer_id==little_flash_table[i].manufacturer_id && device_id ==little_flash_table[i].device_id){
            memcpy(&lf->chip_info,&little_flash_table[i],sizeof(little_flash_chipinfo_t));
            LF_DEBUG("JEDEC ID: manufacturer_id:0x%02X device_id:0x%04X ",little_flash_table[i].manufacturer_id,little_flash_table[i].device_id);
            LF_DEBUG("little flash found flash %s",lf->chip_info.name);
            result = little_flash_reset(lf);
            return result;
        }
    }
    // all not found
    LF_DEBUG("NOT found flash");
    return LF_ERR_NO_FLASH;
}

lf_err_t little_flash_device_deinit(little_flash_t *lf){
#ifdef LF_USE_HEAP
    if (lf->prog_buf != NULL && lf->free != NULL) {
        lf->free(lf->prog_buf);
        lf->prog_buf = NULL;
    }
#endif /* LF_USE_HEAP */
    return LF_ERR_OK;
}

lf_err_t little_flash_deinit(void){
    return LF_ERR_OK;
}

lf_err_t little_flash_powerdown_status(const little_flash_t *lf, uint8_t status){
    if (status) {
        lf_err_t result = little_flash_wait_busy(lf, 1000);
        if (result) return result;
        return lf->spi.transfer(lf, (uint8_t[]){LF_CMD_POWER_DOWN}, 1, LF_NULL, 0);
    } else {
        lf_err_t result = lf->spi.transfer(lf, (uint8_t[]){LF_CMD_RELEASE_POWER_DOWN, 0x00, 0x00, 0x00}, 4, LF_NULL, 0);
        if (result) return result;
        lf->wait_10us(3); /* tRES1 typical 3us, wait 30us to be safe */
        return LF_ERR_OK;
    }
}

static lf_err_t little_flash_cheak_erase(const little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;
    uint8_t status;
    result |= little_flash_wait_busy(lf,1000 * 1000);// 擦除时间比较长，最长给1s
    if (result) {
        LF_ERROR("Error: Cheak erase timeout.");
        return result;
    }
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
    result |= little_flash_wait_busy(lf,700);
    if (result) {
        LF_ERROR("Error: Cheak write timeout.");
        return result;
    }
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
    result |= little_flash_wait_busy(lf,60);
    if (result) {
        LF_ERROR("Error: Cheak read timeout.");
        return result;
    }
    if(lf->chip_info.type==LF_DRIVER_NAND_FLASH){
        result |= little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        // 以下也是要根据不同型号移植的
        uint8_t ecc = (status & 0x30) >> 4;
        if (result==0 && ecc<2){
            return LF_ERR_OK;
        }
        return LF_ERR_READ;
    }
    return result;
}

static lf_err_t little_flash_nand_reset_config(const little_flash_t *lf)
{
    lf_err_t result = LF_ERR_OK;

    if (!lf || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        return LF_ERR_OK;
    }

    result |= little_flash_wait_busy(lf, 1000);
    result |= lf->spi.transfer(lf, (uint8_t[]){LF_CMD_NANDFLASH_RESET}, 1, LF_NULL, 0);
    if (lf->wait_ms) {
        lf->wait_ms(50);
    }
    result |= little_flash_wait_busy(lf, 1000);
    if (result) {
        return result;
    }

    result |= little_flash_write_status(lf, LF_NANDFLASH_STATUS_REGISTER1, 0x00);
    result |= little_flash_write_status(lf,
                                        LF_NANDFLASH_STATUS_REGISTER2,
                                        (1 << 4) | (1 << 3));
    if (lf->wait_10us) {
        lf->wait_10us(5);
    }
    return result;
}

static lf_err_t little_flash_nand_erase_page_addr(const little_flash_t *lf,
                                                  uint32_t page_addr)
{
    lf_err_t result = LF_ERR_OK;
    uint8_t cmd_data[4];
    uint8_t status = 0;
    uint32_t retry;

    if (!lf || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        return LF_ERR_ERASE;
    }

    cmd_data[0] = lf->chip_info.erase_cmd;
    cmd_data[1] = page_addr >> 16;
    cmd_data[2] = page_addr >> 8;
    cmd_data[3] = page_addr;

    for (retry = 0; retry < 3; retry++) {
        if (retry > 0) {
            LF_WARNING("nand erase retry page=%u status=0x%02X retry=%u",
                       (unsigned int)page_addr,
                       (unsigned int)status,
                       (unsigned int)retry);
            (void)little_flash_nand_reset_config(lf);
        }

        if(little_flash_write_enabled(lf, LF_ENABLE)) {
            return LF_ERR_ERASE;
        }
        result = lf->spi.transfer(lf, cmd_data, 4, LF_NULL, 0);
        if(result) {
            return LF_ERR_ERASE;
        }
        lf->wait_ms(lf->chip_info.erase_times);

        result = little_flash_wait_busy(lf, 1000 * 1000);
        if (!result) {
            result = little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
        }
        if (!result &&
            (status & 0x04) == 0 &&
            (status & LF_STATUS_REGISTER_WEL) == 0) {
            return LF_ERR_OK;
        }
    }

    LF_ERROR("Error: NAND erase page=%u failed status=0x%02X.",
             (unsigned int)page_addr,
             (unsigned int)status);
    return LF_ERR_ERASE;
}

lf_err_t little_flash_chip_erase(const little_flash_t *lf){
    lf_err_t result = LF_ERR_OK;

    if (lf->lock) {
        lf->lock(lf);
    }

    if(lf->chip_info.type==LF_DRIVER_NOR_FLASH){
        if(little_flash_write_enabled(lf, LF_ENABLE)) goto error;
        result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_ERASE_CHIP}, 1,LF_NULL,0);
        lf->wait_ms(lf->chip_info.capacity / lf->chip_info.erase_size * lf->chip_info.erase_times);
        result |= little_flash_cheak_erase(lf);
    }else{
        uint32_t page_size = lf->chip_info.prog_size ? lf->chip_info.prog_size : lf->chip_info.read_size;
        uint32_t pages_per_block = page_size ? (lf->chip_info.erase_size / page_size) : 0;
        uint32_t block_count = lf->chip_info.erase_size ? (lf->chip_info.capacity / lf->chip_info.erase_size) : 0;
        uint32_t block;

        if (pages_per_block == 0 || block_count == 0) {
            goto error;
        }

        LF_DEBUG("nand chip erase blocks=%u pages_per_block=%u last_page=%u",
                 (unsigned int)block_count,
                 (unsigned int)pages_per_block,
                 (unsigned int)((block_count - 1) * pages_per_block));
        for (block = 0; block < block_count; block++) {
            uint32_t page_addr = block * pages_per_block;
            uint8_t status = 0;

            result = little_flash_nand_erase_page_addr(lf, page_addr);
            if(result) goto error;
            if (block == 0 || block + 1 == block_count) {
                (void)little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
                LF_DEBUG("nand chip erase block=%u page=%u status=0x%02X",
                         (unsigned int)block,
                         (unsigned int)page_addr,
                         (unsigned int)status);
            }
        }
        result |= little_flash_nand_reset_config(lf);
        if(result) {
            goto error;
        }
    }

    if (little_flash_write_enabled(lf, LF_DISABLE)) goto error;

    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    LF_ERROR("Error: Chip erase failed.");
    little_flash_write_enabled(lf, LF_DISABLE);
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_ERASE;
}

lf_err_t little_flash_erase(const little_flash_t *lf, uint32_t addr, uint32_t len){
    uint8_t cmd_data[4]={0};
    uint32_t erase_off = 0, erase_addr = 0, erase_len = 0;
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

    cmd_data[0] = lf->chip_info.erase_cmd;

    if(lf->chip_info.type==LF_DRIVER_NAND_FLASH){
        erase_off = addr % lf->chip_info.erase_size;
        erase_addr = (addr / lf->chip_info.erase_size) * (lf->chip_info.erase_size / lf->chip_info.read_size);
    }else{
        erase_off = addr % lf->chip_info.erase_size;
        erase_addr = addr / lf->chip_info.erase_size * lf->chip_info.erase_size;
    }
    erase_len = len + erase_off;// 修正擦除长度,长度对齐擦除起始位置
    while (erase_len){
        if (lf->chip_info.type==LF_DRIVER_NAND_FLASH) {
            if (little_flash_nand_erase_page_addr(lf, erase_addr) != LF_ERR_OK) {
                goto error;
            }
        }
        else {
            if(little_flash_write_enabled(lf, LF_ENABLE)) goto error;
            cmd_data[1] = erase_addr >> 16;
            cmd_data[2] = erase_addr >> 8;
            cmd_data[3] = erase_addr;
            lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);

            lf->wait_ms(lf->chip_info.erase_times);
            // LF_ERROR("erase_times:%d",lf->chip_info.erase_times);
            if(little_flash_cheak_erase(lf)) {
                goto error;
            }
        }

        erase_addr += (lf->chip_info.type==LF_DRIVER_NAND_FLASH)?lf->chip_info.erase_size/lf->chip_info.read_size:lf->chip_info.erase_size;

        if (erase_len<=lf->chip_info.erase_size){
            erase_len = 0;
            break;
        }else{
            erase_len -= lf->chip_info.erase_size;
        }
    }

    if (little_flash_write_enabled(lf, LF_DISABLE)) goto error;

    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    LF_ERROR("Error: Erase failed.");
    little_flash_write_enabled(lf, LF_DISABLE);
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_ERASE;
}

lf_err_t little_flash_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len){
    if (addr + len > lf->chip_info.capacity) {
        LF_ERROR("Error: Flash address is out of bound.");
        return LF_ERR_BAD_ADDRESS;
    }
    uint32_t base_addr = addr;

    if (lf->lock) {
        lf->lock(lf);
    }

#ifdef LF_USE_HEAP
    uint8_t* cmd_data;
    bool buf_from_heap = false;
    if (lf->prog_buf != NULL) {
        cmd_data = lf->prog_buf;            /* use pre-allocated buffer (lock held) */
    } else {
        cmd_data = (uint8_t*)lf->malloc(4 + lf->chip_info.prog_size);
        if (!cmd_data) {
            LF_ERROR("Error: malloc failed.");
            if (lf->unlock) lf->unlock(lf);
            return LF_ERR_NO_MEM;
        }
        buf_from_heap = true;
    }
#else
    uint8_t cmd_data[4+lf->chip_info.prog_size];
#endif /* LF_USE_HEAP */

    while (len){
        if (little_flash_wait_busy(lf,100)){
            goto error;
        }
        
        if(little_flash_write_enabled(lf, LF_ENABLE)){
            goto error;
        }

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
            /* NAND write — identity mapping (logical page == physical page) */
            uint32_t page_addr = addr / lf->chip_info.prog_size;
            uint16_t column_addr = addr % lf->chip_info.prog_size;
            cmd_data[0] = LF_CMD_PROG_DATA;
            cmd_data[1] = column_addr >> 8;
            cmd_data[2] = column_addr;
            if (column_addr){
                if ((column_addr+len)<=lf->chip_info.prog_size){
                    memcpy(&cmd_data[3],&data[addr-base_addr],len);
                    lf->spi.transfer(lf,cmd_data, 3+len,LF_NULL,0);
                    little_flash_wait_busy(lf,100);
                    cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
                    cmd_data[1] = page_addr >> 16;
                    cmd_data[2] = page_addr >> 8;
                    cmd_data[3] = page_addr;
                    lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
                    if (little_flash_cheak_write(lf)) {
                        goto error;
                    }
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
                    little_flash_wait_busy(lf,100);
                    cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
                    cmd_data[1] = page_addr >> 16;
                    cmd_data[2] = page_addr >> 8;
                    cmd_data[3] = page_addr;
                    lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
                    if (little_flash_cheak_write(lf)) {
                        goto error;
                    }
                    break;
                }else{
                    memcpy(&cmd_data[3],&data[addr-base_addr],lf->chip_info.prog_size);
                    lf->spi.transfer(lf,cmd_data, 3+lf->chip_info.prog_size,LF_NULL,0);
                    len -= lf->chip_info.prog_size;
                    addr += lf->chip_info.prog_size;
                }
            }
            little_flash_wait_busy(lf,100);
            cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
            cmd_data[1] = page_addr >> 16;
            cmd_data[2] = page_addr >> 8;
            cmd_data[3] = page_addr;
            lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
            if (little_flash_cheak_write(lf)) {
                goto error;
            }
        }
    }

    if (little_flash_write_enabled(lf, LF_DISABLE)) goto error;
#ifdef LF_USE_HEAP
    if (buf_from_heap) lf->free(cmd_data);
#endif /* LF_USE_HEAP */
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    LF_ERROR("Error: Write failed.");
#ifdef LF_USE_HEAP
    if (buf_from_heap) lf->free(cmd_data);
#endif /* LF_USE_HEAP */
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_WRITE;
}

lf_err_t little_flash_erase_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len){
    lf_err_t result = LF_ERR_OK;
    result = little_flash_erase(lf, addr, len);
    if (result == LF_ERR_OK) {
        result = little_flash_write(lf, addr, data, len);
    }
    return result;
}

static int little_flash_is_all_ff(const uint8_t* data, uint32_t len) {
    uint32_t i = 0;
    if (data == LF_NULL) {
        return 0;
    }
    for (i = 0; i < len; i++) {
        if (data[i] != 0xFF) {
            return 0;
        }
    }
    return 1;
}

static lf_err_t little_flash_nand_check_page_oob_args(const little_flash_t *lf,
                                                      uint32_t page,
                                                      uint16_t data_off,
                                                      const void *data,
                                                      uint32_t data_len,
                                                      uint16_t oob_off,
                                                      const void *oob,
                                                      uint32_t oob_len)
{
    uint32_t page_size;
    uint32_t spare_size;
    uint32_t page_count;

    if (!lf || lf->chip_info.type != LF_DRIVER_NAND_FLASH) {
        return LF_ERR_BAD_ADDRESS;
    }
    page_size = lf->chip_info.prog_size;
    spare_size = lf->chip_info.spare_size;
    if (page_size == 0 || lf->chip_info.capacity == 0) {
        return LF_ERR_BAD_ADDRESS;
    }
    page_count = lf->chip_info.capacity / page_size;
    if (page >= page_count) {
        return LF_ERR_BAD_ADDRESS;
    }
    if ((data_len > 0 && !data) || (oob_len > 0 && !oob)) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (data_off > page_size || data_len > page_size - data_off) {
        return LF_ERR_BAD_ADDRESS;
    }
    if (oob_len > 0) {
        if (spare_size == 0 || oob_off > spare_size || oob_len > spare_size - oob_off) {
            return LF_ERR_BAD_ADDRESS;
        }
    }
    return LF_ERR_OK;
}

lf_err_t little_flash_nand_read_page_oob(const little_flash_t *lf, uint32_t page,
                                         uint16_t data_off, uint8_t *data, uint32_t data_len,
                                         uint16_t oob_off, uint8_t *oob, uint32_t oob_len,
                                         uint8_t *status_out)
{
    lf_err_t result;
    uint8_t cmd_data[4];
    uint8_t status = 0xff;
    uint8_t ecc;
    uint32_t page_size;

    if (status_out) {
        *status_out = status;
    }
    result = little_flash_nand_check_page_oob_args(lf, page,
                                                   data_off, data, data_len,
                                                   oob_off, oob, oob_len);
    if (result != LF_ERR_OK) {
        return result;
    }
    if (data_len == 0 && oob_len == 0) {
        return LF_ERR_OK;
    }

    page_size = lf->chip_info.prog_size;
    if (lf->lock) {
        lf->lock(lf);
    }

    cmd_data[0] = LF_NANDFLASH_PAGE_DATA_READ;
    cmd_data[1] = page >> 16;
    cmd_data[2] = page >> 8;
    cmd_data[3] = page;
    result = lf->spi.transfer(lf, cmd_data, 4, LF_NULL, 0);
    if (result != LF_ERR_OK) {
        goto error;
    }
    result = little_flash_wait_busy(lf, 60);
    if (result != LF_ERR_OK) {
        goto error;
    }
    result = little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
    if (status_out) {
        *status_out = status;
    }
    if (result != LF_ERR_OK) {
        goto error;
    }
    ecc = (status & 0x30) >> 4;

    if (data_len > 0) {
        cmd_data[0] = LF_CMD_READ_DATA;
        cmd_data[1] = data_off >> 8;
        cmd_data[2] = data_off;
        cmd_data[3] = 0;
        result = lf->spi.transfer(lf, cmd_data, 4, data, data_len);
        if (result != LF_ERR_OK || (ecc >= 2 && !little_flash_is_all_ff(data, data_len))) {
            goto error;
        }
    }

    if (oob_len > 0) {
        uint16_t column = (uint16_t)(page_size + oob_off);

        cmd_data[0] = LF_CMD_READ_DATA;
        cmd_data[1] = column >> 8;
        cmd_data[2] = column;
        cmd_data[3] = 0;
        result = lf->spi.transfer(lf, cmd_data, 4, oob, oob_len);
        if (result != LF_ERR_OK || (ecc >= 2 && !little_flash_is_all_ff(oob, oob_len))) {
            goto error;
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

lf_err_t little_flash_nand_write_page_oob(const little_flash_t *lf, uint32_t page,
                                          uint16_t data_off, const uint8_t *data, uint32_t data_len,
                                          uint16_t oob_off, const uint8_t *oob, uint32_t oob_len,
                                          uint8_t *status_out)
{
    lf_err_t result;
    uint32_t page_size;
    uint32_t cache_len;
    uint8_t status = 0xff;
#ifdef LF_USE_HEAP
    uint8_t *cmd_data;
    bool buf_from_heap = false;
#else
    uint8_t cmd_data[3 + LF_NANDFLASH_PAGE_ZISE + LF_NANDFLASH_SPARE_SIZE];
#endif /* LF_USE_HEAP */

    if (status_out) {
        *status_out = status;
    }
    result = little_flash_nand_check_page_oob_args(lf, page,
                                                   data_off, data, data_len,
                                                   oob_off, oob, oob_len);
    if (result != LF_ERR_OK) {
        return result;
    }
    if (data_len == 0 && oob_len == 0) {
        return LF_ERR_OK;
    }

    page_size = lf->chip_info.prog_size;
    cache_len = page_size + lf->chip_info.spare_size;
#ifndef LF_USE_HEAP
    if (cache_len > LF_NANDFLASH_PAGE_ZISE + LF_NANDFLASH_SPARE_SIZE) {
        return LF_ERR_BAD_ADDRESS;
    }
#endif /* LF_USE_HEAP */

#ifdef LF_USE_HEAP
    if (lf->prog_buf != NULL) {
        cmd_data = lf->prog_buf;
    } else {
        if (!lf->malloc) {
            return LF_ERR_NO_MEM;
        }
        cmd_data = (uint8_t *)lf->malloc(3 + cache_len);
        if (!cmd_data) {
            return LF_ERR_NO_MEM;
        }
        buf_from_heap = true;
    }
#endif /* LF_USE_HEAP */

    if (lf->lock) {
        lf->lock(lf);
    }

    result = little_flash_wait_busy(lf, 100);
    if (result != LF_ERR_OK) {
        goto error;
    }
    result = little_flash_write_enabled(lf, LF_ENABLE);
    if (result != LF_ERR_OK) {
        goto error;
    }

    memset(&cmd_data[3], 0xff, cache_len);
    if (data_len > 0) {
        memcpy(&cmd_data[3 + data_off], data, data_len);
    }
    if (oob_len > 0) {
        memcpy(&cmd_data[3 + page_size + oob_off], oob, oob_len);
    }

    cmd_data[0] = LF_CMD_PROG_DATA;
    cmd_data[1] = 0;
    cmd_data[2] = 0;
    result = lf->spi.transfer(lf, cmd_data, 3 + cache_len, LF_NULL, 0);
    if (result != LF_ERR_OK) {
        goto error;
    }
    result = little_flash_wait_busy(lf, 100);
    if (result != LF_ERR_OK) {
        goto error;
    }

    cmd_data[0] = LF_NANDFLASH_PAGE_PROG_EXEC;
    cmd_data[1] = page >> 16;
    cmd_data[2] = page >> 8;
    cmd_data[3] = page;
    result = lf->spi.transfer(lf, cmd_data, 4, LF_NULL, 0);
    if (result != LF_ERR_OK) {
        goto error;
    }
    result = little_flash_cheak_write(lf);
    (void)little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
    if (status_out) {
        *status_out = status;
    }
    if (result != LF_ERR_OK) {
        goto error;
    }

    result = little_flash_write_enabled(lf, LF_DISABLE);
    if (result != LF_ERR_OK) {
        goto error;
    }

#ifdef LF_USE_HEAP
    if (buf_from_heap) {
        lf->free(cmd_data);
    }
#endif /* LF_USE_HEAP */
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;

error:
    (void)little_flash_read_status(lf, LF_NANDFLASH_STATUS_REGISTER3, &status);
    if (status_out) {
        *status_out = status;
    }
    (void)little_flash_write_enabled(lf, LF_DISABLE);
#ifdef LF_USE_HEAP
    if (buf_from_heap) {
        lf->free(cmd_data);
    }
#endif /* LF_USE_HEAP */
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
            /* NAND read — identity mapping (logical page == physical page) */
            uint32_t page_addr = addr / lf->chip_info.read_size;
            uint16_t column_addr = addr % lf->chip_info.read_size;
            uint32_t read_len = 0;
            uint8_t* read_ptr = LF_NULL;
            lf_err_t read_check = LF_ERR_OK;

            cmd_data[0] = LF_NANDFLASH_PAGE_DATA_READ;
            cmd_data[1] = page_addr >> 16;
            cmd_data[2] = page_addr >> 8;
            cmd_data[3] = page_addr;
            lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
            read_check = little_flash_cheak_read(lf);
            cmd_data[0] = LF_CMD_READ_DATA;
            cmd_data[1] = column_addr >> 8;
            cmd_data[2] = column_addr;
            cmd_data[3] = 0;
            if (column_addr){
                if ((column_addr+len)<=lf->chip_info.read_size){
                    read_ptr = &data[addr-base_addr];
                    read_len = len;
                    lf->spi.transfer(lf,cmd_data, 4,read_ptr,read_len);
                    if (read_check && !little_flash_is_all_ff(read_ptr, read_len)) {
                        goto error;
                    }
                    break;
                }else{
                    read_ptr = &data[addr-base_addr];
                    read_len = lf->chip_info.read_size-column_addr;
                    lf->spi.transfer(lf,cmd_data, 4,read_ptr,read_len);
                    if (read_check && !little_flash_is_all_ff(read_ptr, read_len)) {
                        goto error;
                    }
                    len -= (lf->chip_info.read_size-column_addr);
                    addr += (lf->chip_info.read_size-column_addr);
                }
            }else{
                if (len<=lf->chip_info.read_size){
                    read_ptr = &data[addr-base_addr];
                    read_len = len;
                    lf->spi.transfer(lf,cmd_data, 4,read_ptr,read_len);
                    if (read_check && !little_flash_is_all_ff(read_ptr, read_len)) {
                        goto error;
                    }
                    break;
                }else{
                    read_ptr = &data[addr-base_addr];
                    read_len = lf->chip_info.read_size;
                    lf->spi.transfer(lf,cmd_data, 4,read_ptr,read_len);
                    if (read_check && !little_flash_is_all_ff(read_ptr, read_len)) {
                        goto error;
                    }
                    len -= lf->chip_info.read_size;
                    addr += lf->chip_info.read_size;
                }
            }
        }
    }
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_OK;
error:
    LF_ERROR("Error: Read failed.");
    if (lf->unlock) {
        lf->unlock(lf);
    }
    return LF_ERR_READ;
}













