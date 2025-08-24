#ifndef _LITTLE_FLASH_H_
#define _LITTLE_FLASH_H_

#include "little_flash_define.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
    所有nand flash均使用BUF1模式驱动
    nand flash无统一标准与命令,移植要注意状态寄存器和命令寄存器
*/


lf_err_t little_flash_init(void);

lf_err_t little_flash_deinit(void);

lf_err_t little_flash_device_init(little_flash_t *lf);

lf_err_t little_flash_device_deinit(little_flash_t *lf);

lf_err_t little_flash_erase(const little_flash_t *lf, uint32_t addr, uint32_t len);

lf_err_t little_flash_chip_erase(const little_flash_t *lf);

lf_err_t little_flash_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len);

lf_err_t little_flash_erase_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len);

lf_err_t little_flash_read(const little_flash_t *lf, uint32_t addr, uint8_t *data, uint32_t len);

lf_err_t little_flash_write_status(const little_flash_t *lf, uint8_t address, uint8_t status);

lf_err_t little_flash_read_status(const little_flash_t *lf, uint8_t address, uint8_t *status);


#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_H_ */










