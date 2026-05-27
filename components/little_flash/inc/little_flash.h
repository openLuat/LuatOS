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

/**
 * @brief 初始化 little_flash 库
 *
 * 打印版本信息和仓库地址。调用其他 API 前无需强制调用本函数，
 * 但建议在应用启动时调用一次以输出调试信息。
 *
 * @return LF_ERR_OK 始终返回成功
 */
lf_err_t little_flash_init(void);

/**
 * @brief 反初始化 little_flash 库
 *
 * 释放库级别的全局资源（当前实现为空操作，预留扩展用）。
 *
 * @return LF_ERR_OK 始终返回成功
 */
lf_err_t little_flash_deinit(void);

/**
 * @brief 初始化单个 Flash 设备
 *
 * 调用平台移植接口 `little_flash_port_init`，然后通过 SFDP 自动探测
 * 或 JEDEC ID 查表识别芯片型号，最后复位设备并配置默认参数。
 *
 * 调用本函数前，@p lf 中以下字段必须已填写：
 * - `spi.transfer`：SPI 传输回调
 * - `wait_10us`、`wait_ms`：延时回调
 * - 若启用了 `LF_USE_HEAP`，还需填写 `malloc` 和 `free`
 *
 * @param[in,out] lf  Flash 设备句柄；识别成功后 `chip_info` 字段将被填充
 * @return LF_ERR_OK       初始化成功
 * @return LF_ERR_NO_FLASH 未能识别芯片（SFDP 探测失败且 JEDEC ID 不在内置列表中）
 * @return 其他错误码       SPI 传输失败或复位超时
 */
lf_err_t little_flash_device_init(little_flash_t *lf);

/**
 * @brief 反初始化单个 Flash 设备
 *
 * 释放设备级别的资源（当前实现为空操作，预留扩展用）。
 *
 * @param[in] lf  Flash 设备句柄
 * @return LF_ERR_OK 始终返回成功
 */
lf_err_t little_flash_device_deinit(little_flash_t *lf);

/**
 * @brief 按地址范围擦除 Flash
 *
 * 按 `chip_info.erase_size` 为最小擦除粒度对指定范围执行块擦除。
 * 若 @p addr 不在块边界上，会自动向下对齐到块起始地址。
 * 若 @p addr == 0 且 @p len == `chip_info.capacity`，则等价于调用
 * `little_flash_chip_erase`。
 *
 * @param[in] lf    Flash 设备句柄
 * @param[in] addr  起始字节地址（NOR flash 为绝对地址；NAND flash 亦同）
 * @param[in] len   需要擦除的字节数
 * @return LF_ERR_OK          擦除成功
 * @return LF_ERR_BAD_ADDRESS 地址超出芯片容量
 * @return LF_ERR_ERASE       擦除操作失败（超时或状态寄存器报错）
 */
lf_err_t little_flash_erase(const little_flash_t *lf, uint32_t addr, uint32_t len);

/**
 * @brief 全片擦除 Flash
 *
 * NOR flash 使用 Chip Erase 命令（0xC7）一次性擦除；
 * NAND flash 则逐块循环擦除直到覆盖全部容量。
 *
 * @warning 该操作耗时较长（几十毫秒到数秒不等），请勿在中断或时间敏感上下文中调用。
 *
 * @param[in] lf  Flash 设备句柄
 * @return LF_ERR_OK    擦除成功
 * @return LF_ERR_ERASE 擦除操作失败
 */
lf_err_t little_flash_chip_erase(const little_flash_t *lf);

/**
 * @brief 向 Flash 写入数据（不自动擦除）
 *
 * 按页（`chip_info.prog_size`）分包写入，自动处理跨页边界的情况。
 * **写入前必须确保目标区域已被擦除**，否则结果未定义。
 * 如需擦后写，请使用 `little_flash_erase_write`。
 *
 * @param[in] lf    Flash 设备句柄
 * @param[in] addr  目标起始字节地址
 * @param[in] data  待写入数据缓冲区
 * @param[in] len   写入字节数
 * @return LF_ERR_OK          写入成功
 * @return LF_ERR_BAD_ADDRESS 地址超出芯片容量
 * @return LF_ERR_NO_MEM      堆内存分配失败（仅在启用 `LF_USE_HEAP` 时可能返回）
 * @return LF_ERR_WRITE       写入操作失败（超时或状态寄存器报错）
 */
lf_err_t little_flash_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len);

/**
 * @brief 先擦除再写入 Flash（原子擦写）
 *
 * 等价于先调用 `little_flash_erase(lf, addr, len)`，
 * 成功后再调用 `little_flash_write(lf, addr, data, len)`。
 *
 * @param[in] lf    Flash 设备句柄
 * @param[in] addr  目标起始字节地址
 * @param[in] data  待写入数据缓冲区
 * @param[in] len   写入字节数
 * @return LF_ERR_OK    操作成功
 * @return LF_ERR_ERASE 擦除阶段失败
 * @return LF_ERR_WRITE 写入阶段失败
 */
lf_err_t little_flash_erase_write(const little_flash_t *lf, uint32_t addr, const uint8_t *data, uint32_t len);

/**
 * @brief 从 Flash 读取数据
 *
 * NOR flash 使用连续读命令一次性读取；
 * NAND flash 按页（`chip_info.read_size`）分批读取，并在每页读取后检查 ECC 状态。
 *
 * @param[in]  lf    Flash 设备句柄
 * @param[in]  addr  源起始字节地址
 * @param[out] data  接收数据的缓冲区，调用方负责分配不少于 @p len 字节的空间
 * @param[in]  len   读取字节数
 * @return LF_ERR_OK   读取成功
 * @return LF_ERR_READ 读取失败（超时或 ECC 错误）
 */
lf_err_t little_flash_read(const little_flash_t *lf, uint32_t addr, uint8_t *data, uint32_t len);

/**
 * @brief 控制 Flash 进入或退出深度掉电模式（NOR 和 NAND flash 均支持）
 *
 * - @p status 为非零值（建议使用 `LF_ENABLE`）：发送 0xB9 命令，使芯片进入超低功耗
 *   待机状态。进入后除本函数外的所有操作均不可用。
 * - @p status 为 0（建议使用 `LF_DISABLE`）：发送 0xAB + 3 个哑字节命令，唤醒芯片
 *   并等待 tRES1（≈30μs）确保芯片完全恢复到正常工作状态。
 *
 * @param[in] lf      Flash 设备句柄
 * @param[in] status  `LF_ENABLE`(1) 进入掉电模式，`LF_DISABLE`(0) 退出掉电模式
 * @return LF_ERR_OK      操作成功
 * @return LF_ERR_TIMEOUT 进入掉电前等待芯片就绪超时（仅 enter 路径）
 * @return 其他错误码     SPI 传输失败
 */
lf_err_t little_flash_powerdown_status(const little_flash_t *lf, uint8_t status);

/**
 * @brief 写入 Flash 状态寄存器
 *
 * - NOR flash：@p address 传 0 时发送单字节命令 + 状态值（02h 格式）；
 *   传非零值时发送命令 + 寄存器地址 + 状态值（03h 格式）。
 * - NAND flash：@p address 指定寄存器地址（如 `LF_NANDFLASH_STATUS_REGISTER1`
 *   ~ `LF_NANDFLASH_STATUS_REGISTER4`），命令自动切换为 0x1F。
 *
 * @param[in] lf      Flash 设备句柄
 * @param[in] address 寄存器地址；NOR flash 填 0 表示不带地址字节
 * @param[in] status  待写入的状态值
 * @return LF_ERR_OK   写入成功
 * @return 其他错误码  SPI 传输失败
 */
lf_err_t little_flash_write_status(const little_flash_t *lf, uint8_t address, uint8_t status);

/**
 * @brief 读取 Flash 状态寄存器
 *
 * - NOR flash：@p address 传 0 时发送单字节命令读取默认状态寄存器（0x05 格式）；
 *   传非零值时发送命令 + 寄存器地址（02h 格式）。
 * - NAND flash：@p address 指定寄存器地址（如 `LF_NANDFLASH_STATUS_REGISTER3`），
 *   命令自动切换为 0x0F。
 *
 * @param[in]  lf      Flash 设备句柄
 * @param[in]  address 寄存器地址；NOR flash 填 0 表示不带地址字节
 * @param[out] status  读取到的状态值
 * @return LF_ERR_OK   读取成功
 * @return 其他错误码  SPI 传输失败
 */
lf_err_t little_flash_read_status(const little_flash_t *lf, uint8_t address, uint8_t *status);


#ifdef __cplusplus
}
#endif

#endif /* _LITTLE_FLASH_H_ */











