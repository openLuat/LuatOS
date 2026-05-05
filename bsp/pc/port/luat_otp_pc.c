#include "luat_base.h"
#include "luat_otp.h"
#include <stdio.h>
#include <string.h>

/*
 * otp.bin layout (776 bytes total):
 *   [0..3]    Magic: 'O','T','P','1'
 *   [4..7]    Lock flags: byte[4+N] = lock flag for zone N (0=unlocked, 1=locked)
 *   [8+N*256 .. 8+N*256+255]  Zone N data (256 bytes, default 0xFF)
 */

#define OTP_FILE_NAME   "otp.bin"
#define OTP_ZONE_COUNT  3
#define OTP_ZONE_SIZE   256
#define OTP_HDR_SIZE    8   /* 4 magic + 4 lock flags */
#define OTP_FILE_SIZE   (OTP_HDR_SIZE + OTP_ZONE_COUNT * OTP_ZONE_SIZE)

static const uint8_t otp_magic[4] = {'O', 'T', 'P', '1'};

/* Returns 0 on success, -1 on failure. Creates/reinitialises the file if needed. */
static int otp_ensure_file(void)
{
    uint8_t magic[4];
    FILE *fp = fopen(OTP_FILE_NAME, "rb");
    if (fp) {
        size_t n = fread(magic, 1, 4, fp);
        fclose(fp);
        if (n == 4 && memcmp(magic, otp_magic, 4) == 0) {
            return 0; /* file OK */
        }
    }

    /* Create / overwrite */
    fp = fopen(OTP_FILE_NAME, "wb");
    if (!fp) return -1;

    uint8_t buf[OTP_FILE_SIZE];
    memcpy(buf, otp_magic, 4);          /* magic */
    memset(buf + 4, 0, 4);              /* lock flags = 0 */
    memset(buf + OTP_HDR_SIZE, 0xFF, OTP_ZONE_COUNT * OTP_ZONE_SIZE); /* data = 0xFF */
    fwrite(buf, 1, OTP_FILE_SIZE, fp);
    fclose(fp);
    return 0;
}

static int otp_is_locked(int zone)
{
    FILE *fp = fopen(OTP_FILE_NAME, "rb");
    if (!fp) return 0;
    uint8_t flag = 0;
    fseek(fp, 4 + zone, SEEK_SET);
    fread(&flag, 1, 1, fp);
    fclose(fp);
    return flag != 0;
}

static int otp_set_lock(int zone)
{
    FILE *fp = fopen(OTP_FILE_NAME, "r+b");
    if (!fp) return -1;
    uint8_t flag = 1;
    fseek(fp, 4 + zone, SEEK_SET);
    fwrite(&flag, 1, 1, fp);
    fclose(fp);
    return 0;
}

int luat_otp_read(int zone, char* buff, size_t offset, size_t len)
{
    if (zone < 0 || zone >= OTP_ZONE_COUNT) return -1;
    if (offset + len > OTP_ZONE_SIZE)       return -1;
    if (len == 0)                            return 0;
    if (otp_ensure_file() != 0)             return -1;

    FILE *fp = fopen(OTP_FILE_NAME, "rb");
    if (!fp) return -1;
    fseek(fp, (long)(OTP_HDR_SIZE + zone * OTP_ZONE_SIZE + offset), SEEK_SET);
    size_t n = fread(buff, 1, len, fp);
    fclose(fp);
    return (int)n;
}

int luat_otp_write(int zone, char* buff, size_t offset, size_t len)
{
    if (zone < 0 || zone >= OTP_ZONE_COUNT) return -1;
    if (offset + len > OTP_ZONE_SIZE)       return -1;
    if (len == 0)                            return 0;
    if (otp_ensure_file() != 0)             return -1;
    if (otp_is_locked(zone))                return -1;

    /* Read existing bytes, OR with new data (OTP: bits can only be set, not cleared) */
    uint8_t tmp[OTP_ZONE_SIZE];
    FILE *fp = fopen(OTP_FILE_NAME, "r+b");
    if (!fp) return -1;

    long data_off = (long)(OTP_HDR_SIZE + zone * OTP_ZONE_SIZE + offset);
    fseek(fp, data_off, SEEK_SET);
    if (fread(tmp, 1, len, fp) != len) { fclose(fp); return -1; }

    for (size_t i = 0; i < len; i++) {
        tmp[i] |= (uint8_t)buff[i];
    }

    fseek(fp, data_off, SEEK_SET);
    fwrite(tmp, 1, len, fp);
    fclose(fp);
    return 0;
}

int luat_otp_erase(int zone, size_t offset, size_t len)
{
    if (zone < 0 || zone >= OTP_ZONE_COUNT) return -1;
    if (offset + len > OTP_ZONE_SIZE)       return -1;
    if (otp_ensure_file() != 0)             return -1;
    if (otp_is_locked(zone))                return -1;

    uint8_t buf[OTP_ZONE_SIZE];
    memset(buf, 0xFF, len);

    FILE *fp = fopen(OTP_FILE_NAME, "r+b");
    if (!fp) return -1;
    fseek(fp, (long)(OTP_HDR_SIZE + zone * OTP_ZONE_SIZE + offset), SEEK_SET);
    fwrite(buf, 1, len, fp);
    fclose(fp);
    return 0;
}

int luat_otp_lock(int zone)
{
    if (zone < 0 || zone >= OTP_ZONE_COUNT) return -1;
    if (otp_ensure_file() != 0)             return -1;
    return otp_set_lock(zone);
}

size_t luat_otp_size(int zone)
{
    if (zone < 0 || zone >= OTP_ZONE_COUNT) return 0;
    return OTP_ZONE_SIZE;
}