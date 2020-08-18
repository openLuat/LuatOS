# 如何编译固件

## 准备材料

1. 安装Git, windows安装包可以在 git官网 或 https://gitee.com/openLuat/LuatOS/attach_files 下载
2. 选一个简短的目录, 例如 `D:\gitee`, 并建好, 不要放在C盘,不要有中文路径!!!
3. 下载rtt的环境工具 , 地址 https://pan.baidu.com/s/1cg28rk , 下载并解压到上文所述目录 `D:\gitee\env`

## 开始下载源码

1. 进入env所在目录`D:\gitee\env`, 双击 `env.bat`, 启动env
2. 跳转一下目录 `cd D:\gitee`
3. 获取LuatOS源码 `git clone https://gitee.com/openLuat/LuatOS.git` , 得到LuatOS目录
4. 获取rtt源码 `git clone https://gitee.com/rtthread/rt-thread.git` , 得到rt-thread目录

## 开始编译

1. 先启动env
2. 跳转目录 `cd D:\gitee\LuatOS\air640w\rtt`
3. 设置RTT_ROOT环境变量的值 `set RTT_ROOT=D:\gitee\rt-thread`
3. 执行编译 `scons -j16`
4. 等待编译完成, 在 `D:\gitee\LuatOS\air640w\rtt\Bin` 目录可以看到 FLS结尾的固件文件
