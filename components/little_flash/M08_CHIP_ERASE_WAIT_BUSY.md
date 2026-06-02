# M-08 chip_erase wait_busy 修复

## 改动概要
修复 `little_flash_chip_erase` 中两处问题:
1. **race condition**: 用 `lf->wait_ms(estimated_time)` 估算擦除耗时,如果芯片比预期慢,后续操作会读到未擦完的数据。改用 `little_flash_wait_busy` 轮询 SR/SR3 的 BUSY 位,等芯片真正完成。
2. **错误码累积**: 同 S-01,把 `result |=` 模式改成 `if (result == LF_ERR_OK) result = ...`,保留首个错误码而非位或叠加。

## 改动文件
- `D:\github\LuatOS\.worktrees\fix-storage-quickwins\components\little_flash\src\little_flash.c`
  - `little_flash_chip_erase` (lines 430-484)
  - NOR 分支(lines 441-444 之前): 加 `if (result == LF_ERR_OK)` 短路 + 用 `little_flash_wait_busy(lf, 1000 * 1000)` 替代 `lf->wait_ms(...)`
  - NAND 分支(循环内 lines 453-456 之前): 同上替换 + 用 `little_flash_wait_busy(lf, lf->chip_info.erase_times * 1000)` 替代 `lf->wait_ms(lf->chip_info.erase_times)`

## 关键 diff

```c
// 改前 (NOR 分支)
result |= lf->spi.transfer(lf,(uint8_t[]){LF_CMD_ERASE_CHIP}, 1,LF_NULL,0);
lf->wait_ms(lf->chip_info.capacity / lf->chip_info.erase_size * lf->chip_info.erase_times);
result |= little_flash_cheak_erase(lf);

// 改后
if (result == LF_ERR_OK) result = lf->spi.transfer(lf,(uint8_t[]){LF_CMD_ERASE_CHIP}, 1,LF_NULL,0);
if (result == LF_ERR_OK) result = little_flash_wait_busy(lf, 1000 * 1000);  // 1s timeout for full chip erase
if (result == LF_ERR_OK) result = little_flash_cheak_erase(lf);
```

```c
// 改前 (NAND 分支内)
result |= lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
if(result) goto error;
lf->wait_ms(lf->chip_info.erase_times);
result |= little_flash_cheak_erase(lf);
if(result) goto error;

// 改后
if (result == LF_ERR_OK) result = lf->spi.transfer(lf,cmd_data, 4,LF_NULL,0);
if(result) goto error;
if (result == LF_ERR_OK) result = little_flash_wait_busy(lf, lf->chip_info.erase_times * 1000);
if (result == LF_ERR_OK) result = little_flash_cheak_erase(lf);
if(result) goto error;
```

## 设计说明
- `little_flash_wait_busy(lf, timeout_us)` 内部用 `timeout_us > 1000` 区分 1ms 步长 vs 10us 步长,单位是微秒
- chip_erase 是耗时操作,NOR 一般几十 ms,NAND block 1-2 ms,1s timeout 已经覆盖 ~3 个数量级冗余
- NAND 循环里 timeout 直接用 `erase_times` (单位 ms) × 1000 转微秒,让单次 block erase 真正等到芯片响应
- 兜底:如果 `little_flash_wait_busy` 超时返回 `LF_ERR_TIMEOUT`,自然走 `result = LF_ERR_TIMEOUT`,后续 `goto error` 路径

## 验证
- PC 32-bit build: `Build completed successfully`(0 新增 warning,本次改动只触动 4 行)
- c_utest_little_flash_basic: **22/22 PASS** (`### OVERALL_PASS ###`)
- pgfs_basic: **9/9 PASS** (`### OVERALL_PASS ###`)
- 与 master build diff: 仅触动 `little_flash.c:430-484` 区域,无其他模块漂移
