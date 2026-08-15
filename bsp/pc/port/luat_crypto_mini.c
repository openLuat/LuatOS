
#include "luat_base.h"
#include "luat_crypto.h"
#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"
#include <stdlib.h>
#include <time.h>
#include <windows.h>

int luat_crypto_trng(char* buff, size_t len) {
    static uint32_t counter = 0;
    /* PC 模拟器随机源: 每次调用都用 时间 ^ 进程号 ^ 计数器 重新播种,
     * 防止其他模块调用 srand() 后 rand() 序列退化为固定值
     * (IKE 的 SPIi/Ni/KE 必须每次不同, 否则网关可能命中残留的半开 SA) */
    srand((unsigned int)time(NULL) ^
          (unsigned int)GetCurrentProcessId() ^
          (counter++ * 2654435761u));
    for (size_t i = 0; i < len; i++)
    {
        buff[i] = (char) rand();
    }
    return 0;
}
