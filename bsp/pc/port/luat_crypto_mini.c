
#include "luat_base.h"
#include "luat_crypto.h"
#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"
#include <stdlib.h>
#include <limits.h>
#if defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>
#elif defined(__linux__)
#include <sys/random.h>
#include <errno.h>
#elif !defined(__APPLE__) && !defined(__FreeBSD__) && !defined(__OpenBSD__)
#error "The PC port requires an operating-system cryptographic random source"
#endif

/**
 * @brief PC 端的密码学安全随机源，供密钥生成和密码协议使用。
 *
 * 原实现每次用“时间 ^ 进程号 ^ 计数器”调用 srand()，再取 rand() 的字节。
 * 这只能减少重复，不能保证不可预测：种子可被推测，相同种子产生相同序列，
 * 因而不适合生成 SRTP-SDES 的主密钥/盐，也不适合作为 DTLS 私钥和握手的熵源。
 *
 * 现在使用操作系统维护的密码学安全随机数生成器（CSPRNG）：
 * - Windows：BCryptGenRandom，选择系统首选随机源；按 ULONG 长度上限分块。
 * - Linux：getrandom，循环处理短读取，并在 EINTR 中断后重试。
 * - macOS / FreeBSD / OpenBSD：arc4random_buf。
 * 不再自行播种或调用 srand()/rand()；其他未适配平台在编译时明确报错。
 *
 * Windows/Linux 随机源失败时清空整个输出缓冲区并返回错误，不回退到 rand()。
 * 调用者必须检查返回值，不能继续使用失败时的缓冲区；安全媒体层会中止会话创建。
 *
 * @param buff 输出缓冲区；len 非零时不能为 NULL。
 * @param len 需要生成的字节数，允许为 0。
 * @return 0 表示成功；-1 表示参数无效或 Windows/Linux 随机源失败。
 */
int luat_crypto_trng(char* buff, size_t len) {
    size_t done = 0;
    if (!buff && len) return -1;
#if defined(_WIN32)
    while (done < len) {
        ULONG chunk = len - done > ULONG_MAX ? ULONG_MAX : (ULONG)(len - done);
        if (!BCRYPT_SUCCESS(BCryptGenRandom(NULL, (PUCHAR)buff + done, chunk,
                BCRYPT_USE_SYSTEM_PREFERRED_RNG))) goto failed;
        done += chunk;
    }
#elif defined(__linux__)
    while (done < len) {
        size_t chunk = len - done > 256 ? 256 : len - done;
        ssize_t count = getrandom(buff + done, chunk, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) goto failed;
        done += (size_t)count;
    }
#else
    if (len) arc4random_buf(buff, len);
    (void)done;
#endif
    return 0;
#if defined(_WIN32) || defined(__linux__)
failed:
    /* Do not leave partially generated key material for a caller to reuse. */
    for (size_t i = 0; i < len; i++) ((volatile unsigned char *)buff)[i] = 0;
    LLOGE("operating-system random source failed");
    return -1;
#endif
}
