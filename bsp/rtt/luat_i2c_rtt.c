

#include "luat_base.h"
#include "luat_i2c.h"
#include "luat_log.h"

#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#define DBG_TAG           "luat.i2c"
#define DBG_LVL           DBG_WARN
#include <rtdbg.h>

#define I2C_DEVICE_ID_MAX 3
static struct rt_i2c_bus_device* i2c_devs[I2C_DEVICE_ID_MAX + 1];

static int luat_i2c_rtt_init() {
    char name[9];
    name[0] = 'i';
    name[1] = '2';
    name[2] = 'c';
    name[4] = 0x00;
    
    // 搜索i2c0,i2c1,i2c2 ....
    for (size_t i = 0; i <= I2C_DEVICE_ID_MAX; i++)
    {
        name[3] = '0' + i;
        i2c_devs[i] = (struct rt_i2c_bus_device *)rt_device_find(name);
        LOG_I("search i2c name=%s ptr=0x%08X", name, i2c_devs[i]);
    }
    // 搜索i2c0soft,i2c1soft,i2c2soft ....
    name[4] = 's';
    name[5] = 'o';
    name[6] = 'f';
    name[7] = 't';
    name[8] = 0x00;
    for (size_t i = 0; i < I2C_DEVICE_ID_MAX; i++)
    {
        if (i2c_devs[i] != RT_NULL) continue;
        name[3] = '0' + i;
        i2c_devs[i] = (struct rt_i2c_bus_device *)rt_device_find(name);
        LOG_I("search i2c name=%s ptr=0x%08X", name, i2c_devs[i]);
    }

    // 看看有没有i2c
    if (i2c_devs[0] == RT_NULL) {
        i2c_devs[0] = (struct rt_i2c_bus_device *)rt_device_find("i2c");
        LOG_I("search i2c name=%s ptr=0x%08X", "i2c", i2c_devs[0]);
    }
    return 0;
}

INIT_COMPONENT_EXPORT(luat_i2c_rtt_init);

int luat_i2c_exist(int id) {
    if (id < 0 || id > I2C_DEVICE_ID_MAX) {
        LOG_W("no such i2c device id=%ld", id);
        return 0;
    }
    LOG_I("i2c id=%d ptr=0x%08X", id, i2c_devs[id]);
    return i2c_devs[id] == RT_NULL ? 0 : 1;
}

static rt_err_t write_reg(struct rt_i2c_bus_device *bus, rt_uint16_t addr, rt_uint8_t reg, rt_uint8_t *data,rt_uint8_t len)
{
    rt_uint8_t buf[3];

    buf[0] = reg; //cmd
    buf[1] = data[0];
    buf[2] = data[1];

    if (rt_i2c_master_send(bus, addr, 0, buf, 3) == 3)
        return RT_EOK;
    else
        return -RT_ERROR;
}

static rt_err_t read_regs(struct rt_i2c_bus_device *bus, rt_uint16_t addr, rt_uint8_t *buf, rt_uint8_t len)
{
    struct rt_i2c_msg msgs;

    msgs.addr = addr;
    msgs.flags = RT_I2C_RD;
    msgs.buf = buf;
    msgs.len = len;

    if (rt_i2c_transfer(bus, &msgs, 1) == 1)
    {
        return RT_EOK;
    }
    else
    {
        return -RT_ERROR;
    }
}


int luat_i2c_setup(int id, int speed, int slaveaddr) {
    if (!luat_i2c_exist(id)) return 1;
    // 无事可做
    rt_device_open(&i2c_devs[id]->parent, 0);
    return 0;
}
int luat_i2c_close(int id) {
    if (!luat_i2c_exist(id)) return 1;
    // 无事可做
    rt_device_close(&i2c_devs[id]->parent);
    return 0;
}

int luat_i2c_transfer(int id, int addr, int flags, void* buff, size_t len) {
    if (!luat_i2c_exist(id)) return -1;
    struct rt_i2c_msg msgs;
    msgs.addr = addr;
    msgs.flags = flags;
    msgs.buf = buff;
    msgs.len = len;
    LOG_I("i2c_transfer len=%d flags=%d", msgs.len, flags);
    if (rt_i2c_transfer(i2c_devs[id], &msgs, 1) == 1)
    {
        return RT_EOK;
    }
    else
    {
        return -RT_ERROR;
    }
}


int luat_i2c_send(int id, int addr, void* buff, size_t len) {
    return luat_i2c_transfer(id, addr, RT_I2C_WR, buff, len);
}
int luat_i2c_recv(int id, int addr, void* buff, size_t len) {
    return luat_i2c_transfer(id, addr, RT_I2C_RD, buff, len);
}

int luat_i2c_write_reg(int id, int addr, int reg, uint16_t value) {
    if (!luat_i2c_exist(id)) return 1;
    rt_uint8_t buf[3];

    buf[0] = reg; //cmd
    buf[1] = (value >> 8) & 0xFF;
    buf[2] = value & 0xFF;

    if (rt_i2c_master_send(i2c_devs[id], addr, 0, buf, 3) == 3)
        return RT_EOK;
    else
        return -RT_ERROR;
}

int luat_i2c_read_reg(int id,  int addr, int reg, uint16_t* value) {
    if (!luat_i2c_exist(id)) return 1;
    // struct rt_i2c_msg msgs;
    // uint8_t a;
    // a = reg;

    // msgs.addr = addr;
    // msgs.flags = RT_I2C_RD;
    // msgs.buf = &a;
    // msgs.len = 1;
    rt_i2c_master_send(i2c_devs[id], addr, 0, (const rt_uint8_t*)&reg, 1);

    char buff[2] = {0};

    rt_i2c_master_recv(i2c_devs[id], addr, 0, buff, 2);

    *value = buff[0] << 8 + buff[1];
    return 0;
}

