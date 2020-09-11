
#include "stdio.h"

#include "luat_vdev.h"

int main(int argc, const char* argv[]) {

    // TODO 读取命令行参数

    // TODO 读取环境变量

    // 初始化虚拟设备
    luat_vdev_init();

    luat_main();

    return 0;
}
