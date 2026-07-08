/**
 * @file luat_camera_pc.c
 * @brief PC 模拟器摄像头 stub
 *
 * RTMP 组件在真机上通过摄像头采集视频，PC 模拟器没有摄像头硬件，
 * 这里提供空实现避免链接错误。实际推流测试时应从文件读取 H.264。
 */

#include "luat_base.h"

int luat_camera_capture(int id, uint8_t quality, const char *path) {
    (void)id;
    (void)quality;
    (void)path;
    return -1;
}

int luat_camera_stop(int id) {
    (void)id;
    return -1;
}
