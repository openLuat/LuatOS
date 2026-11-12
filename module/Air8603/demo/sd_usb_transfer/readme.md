> **看门狗提醒**
>
> 860X上有合宙Air153D 看门狗芯片 其他项目参考本项目时，须确定你的项目硬件上有无看门狗芯片 如果有 但是未添加喂狗逻辑 约12分钟左右 860X会重启

---

## 功能模块介绍

1、main.lua：主程序入口，负责定义PROJECT/VERSION、初始化看门狗，然后加载应用模块；

2、sd_usb_transfer_app.lua：SD卡与U盘文件互传的应用功能模块，包含配置项和主流程；

3、sd_mount.lua：SD/TF卡挂载（SPI1，CS=GPIO8，SD_EN=GPIO74），禁止自动格式化；

4、udisk.lua：U盘枚举与挂载（USB HOST / MSC），J14的+5.5V使能脚自动拉高；

5、file_xfer.lua：目录遍历、32KB分块复制、回读校验、（可选）删源的复制引擎；

## 演示功能概述

1、把SD卡里的一个目录整棵复制到U盘，也可以反向（U盘→SD卡），或者双向同步（两程都只补"对方没有"的文件）；

2、复制按32KB分块流式读写，内存占用与文件大小无关；

3、写完逐块回读比对，校验通过才算成功；

4、支持搬运模式（delete_src=true：复制并校验通过后删除源文件）；

5、过程日志除了打串口，还会写一份到SD卡的 `sd_usb_transfer_log.txt`，方便拔盘后排查；

6、开始复制前做一次空间预检，避免传到一半才发现放不下。

## 演示硬件环境

1、Air8603 开发板一块；

2、SD/TF卡一张（建议FAT32，exFAT也可以，需要V1031及以后固件）；

3、U盘一个（**优先用普通单分区U盘，不要用多合一读卡器**，原因见最后"注意事项"）；

4、12V DC电源一个（Air8603的USB口只走数据，不给整机供电）；

5、USB数据线一根（接Type-C，用于烧录）。

接线方式：

- SD卡插入板上的TF卡座（原理图P7「SPI接口SD卡」）；
- U盘插入 **J14（USB-A母座）**，也可以用 **J7（4pin USB端子）**，两者是兼容设计，同一组D+/D-；
- 12V电源接P1的DC座或12V端子；
- Type-C接电脑，用于烧录。

> 注意：把USB切到主机模式之后，Type-C那个USB串口日志可能会消失（同一路USB控制器），
> 这时候看日志要走 **J10 的UART调试口（921600 8N1）**，或者直接看SD卡里的日志文件。

## 演示软件环境

1、[Luatools 工具](https://docs.openluat.com/common/Luatools/)；

2、内核固件文件（底层 core 固件文件）：

**本demo需要 Air8603 的 V1031 及以后版本固件。**

原因：早期固件（如CDN上当前的V1028）的fatfs只支持1个卷，SD卡和U盘不能同时挂载，
第二个`fatfs.mount`只是给同一个卷加个别名，这时候做互传就是把SD卡拷到SD卡自己。
本demo在开始复制前会检测这种情况并直接中止，日志会打印：

```
中止：/sd 和 /udisk 指向了同一个卷（总容量都是 XXXXXXXX KB）
  说明当前固件的fatfs不支持多卷，SD和U盘不能同时挂载
  Air8603 需要 V1031 及以后的固件，旧版本（如V1028）只能挂一个卷
```

如果你的固件还是V1028，请先向合宙获取V1031及以后的固件再测试本demo。

## 演示核心步骤

### 1、准备两侧的测试文件

在SD卡和U盘里各建一个同名目录（默认是 `8603_xfer`，可以在 `sd_usb_transfer_app.lua` 的 `CFG.pair_dir` 里改），
往里放几个测试文件。建议这样准备，方便验证各种情况：

- SD卡放：`sd_only.txt`、一张图片或者其它大一点的文件；
- U盘放：`usb_only.txt`、另一个文件；
- 两侧都放：一个同名同内容的小文件（用来验证"同名同大小直接跳过"）。

### 2、修改配置

打开 `sd_usb_transfer_app.lua`，按需要改 `CFG`：

```lua
local CFG = {
    direction   = "sd2usb",   -- "sd2usb" / "usb2sd" / "both"
    pair_dir    = "8603_xfer",
    delete_src  = false,      -- true=搬运（校验通过后删源）
    overwrite   = true,
    verify      = true,       -- 写完回读比对
    chunk       = 32 * 1024,
    wait_usb_ms = 60000,      -- 等U盘插入的最长时间
    log_to_sd   = true,
}
```

### 3、烧录并运行

用Luatools把本目录下的所有 `.lua` 文件下载到模块（脚本目录选本demo目录，固件选 Air8603 的 V1031+），
下载完成后自动运行。

### 4、观察日志

以 `direction = "both"` 为例，运行成功的日志类似下面这样：

```
I/user.sd_usb_transfer ===== SD卡 <-> U盘 文件互传 =====
I/user.sd_usb_transfer 方向=both 目录=8603_xfer 覆盖=true 校验=true 删源=false
I/user.sd SD卡挂载成功 /sd，总 60747776 KB / 剩 60731264 KB
I/user.udisk USB口供电脚 GPIO58 已拉高
I/user.udisk USB已切到HOST模式，等待U盘接入…
I/user.sd_usb_transfer 等待U盘插入（最多60秒）…
I/user.udisk 检测到U盘：app_id=0 hub=1 port=1 addr=2
I/user.udisk U盘挂载成功 /udisk（app_id=0）总 30534464 KB / 剩 30525280 KB
I/user.sd_usb_transfer U盘已就绪：/udisk
I/user.sd_usb_transfer ── 第1程：SD卡 → U盘（只补U盘缺的） ──
I/user.sd_usb_transfer 源目录：/sd/8603_xfer
I/user.sd_usb_transfer 目标目录：/udisk/8603_xfer
I/user.sd_usb_transfer   [1/3] /sd/8603_xfer/sd_only.txt
I/user.sd_usb_transfer   [2/3] /sd/8603_xfer/sd_256k.bin
I/user.sd_usb_transfer   [3/3] /sd/8603_xfer/common.txt
I/user.sd_usb_transfer 结果：成功 2 个 / 256.0 KB，跳过 1，失败 0，用时 0.1 s
I/user.sd_usb_transfer ── 第2程：U盘 → SD卡（只补SD卡缺的） ──
I/user.sd_usb_transfer   [1/5] /udisk/8603_xfer/usb_only.txt
I/user.sd_usb_transfer   [2/5] /udisk/8603_xfer/usb_512k.bin
I/user.sd_usb_transfer   [3/5] /udisk/8603_xfer/common.txt
I/user.sd_usb_transfer   [4/5] /udisk/8603_xfer/sd_only.txt
I/user.sd_usb_transfer   [5/5] /udisk/8603_xfer/sd_256k.bin
I/user.sd_usb_transfer 结果：成功 2 个 / 512.0 KB，跳过 3，失败 0，用时 0.1 s
I/user.sd_usb_transfer ===== 完成，剩余空间：SD卡 59258.6 MB / U盘 29809.6 MB =====
I/user.udisk U盘已卸载 /udisk（可以安全拔出）
```

几个判读要点：

- **第1程**里 `common.txt` 被跳过（跳过 1）——因为U盘上已经有同名同大小的文件；
- **第2程**列出了 5 个文件，但只拷了 2 个——第4/5项是第1程刚拷过去的，被判定为"对方已有"而跳过；
- 两程 `失败 0`，说明所有文件都通过了回读校验；
- 最后U盘做了 `unmount`，此时拔盘是安全的。

## 注意事项

1、**不要用多合一读卡器当U盘**。这类设备会暴露多个LUN，而当前MSC驱动只处理LUN 0，
   如果LUN 0正好是空卡槽，就会一直卡在 `test unit ready too much times`，枚举不成功。
   建议用普通的单分区U盘，USB2.0的兼容性更好。

2、**`delete_src = true` 请谨慎使用**。它会在"复制并校验通过"之后删除源文件；
   如果是双向同步（`direction = "both"`）再叠加删源，行为会比较绕，建议只做单向搬运时使用。

3、**双向同步按"文件名 + 大小"判断是否已存在**。如果两侧存在同名同大小但内容不同的文件，
   会被判定为"已同步"而跳过。这种情况请先用 `overwrite = true` 做单向覆盖，再切换回双向。

4、**SD卡和U盘不要热插拔**。U盘拔出后应用会尽力中止当前传输，但已经写了一半的文件需要重新传。
   SD卡在运行过程中拔出会导致挂载点失效，建议重新上电后再跑。

5、J14的+5.5V不是直供，而是由U0022产生、EN接 `UVC_EN`（PIN58/GPIO58），
   `udisk.lua` 里已经把 `pwr_pin` 默认设成58并在启动时拉高。
   如果本机硬件把PIN58贴成了 `485_EN2`，拉高只是让485-2使能，对U盘没有影响。

6、如果只做只读操作（只看目录、不写入），对固件版本没有特殊要求；
   但**只要涉及U盘写入，就必须用V1031及以后的固件**，早期版本的MSC写路径有问题。
