
/*
@module  yhm27xx
@summary yhm27xx充电芯片
@version 1.0
@date    2025.04.2
@tag LUAT_USE_GPIO
@demo yhm27xxx
@usage
-- 请查阅demo/yhm27xx
*/

#include "luat_base.h"
#include "luat_timer.h"
#include "luat_mem.h"
#include "luat_gpio.h"
#include "luat_zbuff.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "yhm27xx"
#include "luat_log.h"


/*
单总线命令读写YHM27XX
@api    yhm27xx.cmd(pin, chip_id, reg, data)
@int    gpio端口号
@int    芯片ID
@int    寄存器地址
@int    要写入的数据，如果没填，则表示从寄存器读取数据
@return boolean 成功返回true,失败返回false
@return int 读取成功返回寄存器值，写入成功无返回
@usage
while 1 do
    sys.wait(1000)
    local result, data = yhm27xx.cmd(15, 0x04, 0x05)
    log.info("yhm27xx", result, data)
end
*/
static int l_yhm27xx_cmd(lua_State *L)
{
  uint8_t pin = luaL_checkinteger(L, 1);
  uint8_t chip_id = luaL_checkinteger(L, 2);
  uint8_t reg = luaL_checkinteger(L, 3);
  uint8_t data = 0;
  uint8_t is_read = 1;
  if (!lua_isnone(L, 4))
  {
    is_read = 0;
    data = luaL_checkinteger(L, 4);
  }
  #ifdef LUAT_USE_DRV_GPIO
  if(luat_drv_gpio_driver_yhm27xx(pin, chip_id, reg, is_read, &data))
  #else
  if(luat_gpio_driver_yhm27xx(pin, chip_id, reg, is_read, &data))
  #endif
  {
    lua_pushboolean(L, 0);
    return 1;
  }
  lua_pushboolean(L, 1);
  if (is_read)
  {
    lua_pushinteger(L, data);
    return 2;
  }
  return 1;
}

static uint8_t reg_infos[9] = {0};

static int l_yhm_27xx_cb(lua_State *L, void *ptr) {
  lua_getglobal(L, "sys_pub");
  if (lua_isfunction(L, -1)) {
    lua_pushstring(L, "YHM27XX_REG");
    lua_pushlstring(L, (const char*)reg_infos, 9);
    lua_call(L, 2, 0);
  }
  return 0;
}

static void luat_gpio_driver_yhm27xx_reqinfo(uint8_t pin, uint8_t chip_id) {
  
  for (uint8_t i = 0; i < 9; i++)
  {
    luat_gpio_driver_yhm27xx(pin, chip_id, i, 1, &(reg_infos[i]));
  }
  rtos_msg_t msg = {0};
  msg.handler = l_yhm_27xx_cb;
  luat_msgbus_put(&msg, 0);
}

/*
获取最新的寄存器信息(异步)
@api    yhm27xx.reqinfo(pin, chip_id)
@int    gpio端口号
@int    芯片ID
@return nil 无返回值
@usage

sys.subscribe("YHM27XX_REG", function(data)
  -- 注意, 会一次性读出0-9,总共8个寄存器值
  log.info("yhm27xx", data and data:toHex())
end)
yhm27xx.reqinfo(24, 0x04)
*/
static int l_yhm27xx_reqinfo(lua_State *L)
{
  uint8_t pin = luaL_checkinteger(L, 1);
  uint8_t chip_id = luaL_checkinteger(L, 2);
  #ifdef LUAT_USE_DRV_GPIO
  luat_drv_gpio_driver_yhm27xx_reqinfo(pin, chip_id);
  #else
  luat_gpio_driver_yhm27xx_reqinfo(pin, chip_id);
  #endif
  return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_yhm27xx[] = {
        {"cmd",     ROREG_FUNC(l_yhm27xx_cmd)},
        {"reqinfo", ROREG_FUNC(l_yhm27xx_reqinfo)},
        {NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_yhm27xx(lua_State *L)
{
  luat_newlib2(L, reg_yhm27xx);
  return 1;
}
