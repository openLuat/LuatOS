
#include "luat_base.h"



typedef struct sdf_opts {
    int (*initialize) (void* userdata);
	int (*status) (void* userdata);
	int (*read) (void* userdata, char* buff, size_t offset, size_t len);
	int (*write) (void* userdata, const char* buff, size_t offset, size_t len);
	int (*erase) (void* userdata, size_t offset, size_t len);
	int (*ioctl) (void* userdata, size_t cmd, void* buff);
}sdf_opts_t;

typedef struct sfd_w25q {
    const sdf_opts_t* opts;
    int spi_id;
    int spi_cs;
    size_t sector_size;
    size_t sector_count;
    size_t erase_size;
    char chip_id[8];
} sfd_w25q_t;

