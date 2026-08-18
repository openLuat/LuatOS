/*
@module  airlink
@summary AirLink nanopb RPC loopback 自测绑定
@catalog 外设API
@version 1.0
@date    2025.05.30
@tag LUAT_USE_AIRLINK
*/

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_LOOPBACK

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "drv_gpio.pb.h"
#include "drv_uart.pb.h"
#include "drv_wlan.pb.h"
#include "drv_pm.pb.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#define AIRLINK_LIB_RPC_ID_GPIO  0x0100
#define AIRLINK_LIB_RPC_ID_UART  0x0200
#define AIRLINK_LIB_RPC_ID_WLAN  0x0300
#define AIRLINK_LIB_RPC_ID_PM    0x0400

/*
nanopb GPIO RPC loopback 自测
@api airlink.testNanopbGpio()
@return int 0=全部通过, 负值=失败步骤号
@usage
-- 在 loopback 模式启动后调用
local rc = airlink.testNanopbGpio()
assert(rc == 0, "nanopb GPIO RPC 测试失败: " .. tostring(rc))
*/
int l_airlink_test_nanopb_gpio(lua_State* L) {
    int rc = 0;

    // step 1: write pin=5 HIGH
    {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_write_tag;
        req.payload.write.pin   = 5;
        req.payload.write.level = drv_gpio_GpioLevel_GPIO_LEVEL_HIGH;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_GPIO,
            drv_gpio_GpioRpcRequest_fields,  &req,
            drv_gpio_GpioRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done; }
        if (resp.which_payload != drv_gpio_GpioRpcResponse_write_tag) { rc = -2; goto done; }
        if (!resp.payload.write.result.has_code ||
            resp.payload.write.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
            rc = -3; goto done;
        }
    }

    // step 2: read pin=5 expect HIGH
    {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_read_tag;
        req.payload.read.pin = 5;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_GPIO,
            drv_gpio_GpioRpcRequest_fields,  &req,
            drv_gpio_GpioRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -4; goto done; }
        if (resp.which_payload != drv_gpio_GpioRpcResponse_read_tag) { rc = -5; goto done; }
        if (!resp.payload.read.result.has_code ||
            resp.payload.read.result.code != drv_gpio_GpioResultCode_GPIO_RES_OK) {
            rc = -6; goto done;
        }
        if (!resp.payload.read.has_level ||
            resp.payload.read.level != drv_gpio_GpioLevel_GPIO_LEVEL_HIGH) {
            rc = -7; goto done;
        }
    }

    // step 3: timeout test (unknown rpc_id, 500ms)
    {
        drv_gpio_GpioRpcRequest  req  = drv_gpio_GpioRpcRequest_init_zero;
        drv_gpio_GpioRpcResponse resp = drv_gpio_GpioRpcResponse_init_zero;
        req.which_payload = drv_gpio_GpioRpcRequest_read_tag;
        req.payload.read.pin = 1;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, 0xFFFF,
            drv_gpio_GpioRpcRequest_fields,  &req,
            drv_gpio_GpioRpcResponse_fields, &resp,
            500);
        if (ret == 0) { rc = -8; goto done; } // 期望非零 (服务端无handler → -404, 或超时 → -1)
    }

done:
    lua_pushinteger(L, rc);
    return 1;
}

/*
nanopb UART RPC loopback 自测
@api airlink.testNanopbUart()
@return int 0=全部通过, 负值=失败步骤号
*/
int l_airlink_test_nanopb_uart(lua_State* L) {
    int rc = 0;

    // step 1: uart setup (PC stub 返回 -1 → FAIL result 也可接受)
    {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload       = drv_uart_UartRpcRequest_setup_tag;
        req.payload.setup.id        = 10;  // airlink uart 0
        req.payload.setup.has_baud_rate = true;
        req.payload.setup.baud_rate = 115200;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_UART,
            drv_uart_UartRpcRequest_fields,  &req,
            drv_uart_UartRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done_uart; }
        if (resp.which_payload != drv_uart_UartRpcResponse_setup_tag) { rc = -2; goto done_uart; }
        // PC stub 可能返回 FAIL, 但只要 RPC 调通即可
    }

    // step 2: uart write (PC stub 无 uart driver, 预期 FAIL, 但 RPC 应答不超时)
    {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload        = drv_uart_UartRpcRequest_write_tag;
        req.payload.write.id     = 10;
        req.payload.write.data.size = 4;
        req.payload.write.data.bytes[0] = 'T';
        req.payload.write.data.bytes[1] = 'E';
        req.payload.write.data.bytes[2] = 'S';
        req.payload.write.data.bytes[3] = 'T';
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_UART,
            drv_uart_UartRpcRequest_fields,  &req,
            drv_uart_UartRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -3; goto done_uart; }
        if (resp.which_payload != drv_uart_UartRpcResponse_write_tag) { rc = -4; goto done_uart; }
    }

    // step 3: uart close
    {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload        = drv_uart_UartRpcRequest_close_tag;
        req.payload.close.id     = 10;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_UART,
            drv_uart_UartRpcRequest_fields,  &req,
            drv_uart_UartRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -5; goto done_uart; }
        if (resp.which_payload != drv_uart_UartRpcResponse_close_tag) { rc = -6; goto done_uart; }
    }

done_uart:
    lua_pushinteger(L, rc);
    return 1;
}

/*
nanopb WLAN RPC loopback 自测
@api airlink.testNanopbWlan()
@return int 0=全部通过, 负值=失败步骤号
*/
int l_airlink_test_nanopb_wlan(lua_State* L) {
    int rc = 0;

    // step 1: wlan init (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_init_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_init_tag) { rc = -2; goto done_wlan; }
        if (!resp.payload.init.result.has_code ||
            resp.payload.init.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -3; goto done_wlan;
        }
    }

    // step 2: wlan scan (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_scan_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -4; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_scan_tag) { rc = -5; goto done_wlan; }
        if (!resp.payload.scan.result.has_code ||
            resp.payload.scan.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -6; goto done_wlan;
        }
    }

    // step 3: wlan ap_start (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_ap_start_tag;
        strncpy(req.payload.ap_start.ssid, "TestAP", sizeof(req.payload.ap_start.ssid) - 1);
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -7; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_ap_start_tag) { rc = -8; goto done_wlan; }
        if (!resp.payload.ap_start.result.has_code ||
            resp.payload.ap_start.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -9; goto done_wlan;
        }
    }

    // step 4: wlan ap_stop (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_ap_stop_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -10; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_ap_stop_tag) { rc = -11; goto done_wlan; }
        if (!resp.payload.ap_stop.result.has_code ||
            resp.payload.ap_stop.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -12; goto done_wlan;
        }
    }

    // step 5: wlan connect (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_connect_tag;
        strncpy(req.payload.connect.ssid, "TestSSID", sizeof(req.payload.connect.ssid) - 1);
        req.payload.connect.has_password = true;
        strncpy(req.payload.connect.password, "testpass", sizeof(req.payload.connect.password) - 1);
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -13; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_connect_tag) { rc = -14; goto done_wlan; }
        if (!resp.payload.connect.result.has_code ||
            resp.payload.connect.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -15; goto done_wlan;
        }
    }

    // step 6: wlan disconnect (PC mock 返回 0 → OK)
    {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_disconnect_tag;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_WLAN,
            drv_wlan_WlanRpcRequest_fields,  &req,
            drv_wlan_WlanRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -16; goto done_wlan; }
        if (resp.which_payload != drv_wlan_WlanRpcResponse_disconnect_tag) { rc = -17; goto done_wlan; }
        if (!resp.payload.disconnect.result.has_code ||
            resp.payload.disconnect.result.code != drv_wlan_WlanResultCode_WLAN_RES_OK) {
            rc = -18; goto done_wlan;
        }
    }

done_wlan:
    lua_pushinteger(L, rc);
    return 1;
}

/*
nanopb PM RPC loopback 自测
@api airlink.testNanopbPm()
@return int 0=全部通过, 负值=失败步骤号
*/
int l_airlink_test_nanopb_pm(lua_State* L) {
    int rc = 0;

    // step 1: pm_power_ctrl (PC stub 返回 0 → OK)
    {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload              = drv_pm_PmRpcRequest_power_ctrl_tag;
        req.payload.power_ctrl.id      = 1;
        req.payload.power_ctrl.val     = 1;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_PM,
            drv_pm_PmRpcRequest_fields,  &req,
            drv_pm_PmRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -1; goto done_pm; }
        if (resp.which_payload != drv_pm_PmRpcResponse_power_ctrl_tag) { rc = -2; goto done_pm; }
        if (!resp.payload.power_ctrl.result.has_code ||
            resp.payload.power_ctrl.result.code != drv_pm_PmResultCode_PM_RES_OK) {
            rc = -3; goto done_pm;
        }
    }

    // step 2: pm_wakeup_pin (PC stub 返回 -1 → FAIL result, 但 RPC 应答不超时)
    {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload             = drv_pm_PmRpcRequest_wakeup_pin_tag;
        req.payload.wakeup_pin.pin    = 5;
        req.payload.wakeup_pin.val    = 1;
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_PM,
            drv_pm_PmRpcRequest_fields,  &req,
            drv_pm_PmRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -4; goto done_pm; }
        if (resp.which_payload != drv_pm_PmRpcResponse_wakeup_pin_tag) { rc = -5; goto done_pm; }
        // PC stub 返回 -1 → FAIL result 也可接受
    }

    // step 3: pm_request (PC stub 返回 0 → OK)
    {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload              = drv_pm_PmRpcRequest_pm_request_tag;
        req.payload.pm_request.mode    = 0;  // LUAT_PM_SLEEP_MODE_NONE
        int ret = luat_airlink_rpc_nb_call(
            LUAT_AIRLINK_MODE_LOOPBACK, AIRLINK_LIB_RPC_ID_PM,
            drv_pm_PmRpcRequest_fields,  &req,
            drv_pm_PmRpcResponse_fields, &resp,
            3000);
        if (ret != 0) { rc = -6; goto done_pm; }
        if (resp.which_payload != drv_pm_PmRpcResponse_pm_request_tag) { rc = -7; goto done_pm; }
        if (!resp.payload.pm_request.result.has_code ||
            resp.payload.pm_request.result.code != drv_pm_PmResultCode_PM_RES_OK) {
            rc = -8; goto done_pm;
        }
    }

done_pm:
    lua_pushinteger(L, rc);
    return 1;
}

#endif /* LUAT_USE_AIRLINK_LOOPBACK */
