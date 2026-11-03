#include "luat_base.h"
#ifdef LUAT_USE_AIRLINK_LOOPBACK
#include "luat_airlink.h"
#include "luat_airlink_arq.h"

int l_airlink_test_arq(lua_State* L) {
#define CHECK(x) do { if (!(x)) return luaL_error(L, "ARQ regression line %d", __LINE__); } while (0)
    luat_airlink_arq_init();
    luat_airlink_arq_on_peer_caps(0xff);
    CHECK(luat_airlink_arq_state() == ARQ_STATE_LEGACY);
    uint8_t bytes[sizeof(luat_airlink_cmd_t) + sizeof(luat_airlink_dev_info_t) + AIRLINK_ARQ_HELLO_SIZE];
    luat_airlink_dev_info_t info = {0}; info.tp = 1; info.caps = 0xff;
    luat_airlink_arq_devinfo(bytes, &info);
    luat_airlink_cmd_t* hello = (void*)bytes;
    CHECK(!(hello->data[1] & AIRLINK_CAP_ARQ));
    uint8_t* tail = hello->data + sizeof(info);
    uint32_t local, peer = 0x12345678;
    memcpy(&local, tail + 8, 4);
    CHECK(local != 0);
    memcpy(tail + 8, &peer, 4);
    luat_airlink_arq_peer_info(hello);
    CHECK(luat_airlink_arq_state() == ARQ_STATE_NEGOTIATING);
    memcpy(tail + 12, &local, 4);
    luat_airlink_arq_peer_info(hello);
    luat_airlink_arq_check_giveup(0);
    CHECK(luat_airlink_arq_state() == ARQ_STATE_ARQ);
    airlink_link_data_t frame = {0}; frame.flags.reserved = 3;
    CHECK(!luat_airlink_arq_frame_valid(&frame)); // old RPC/FRAG flag collision
    frame.flags.reserved |= (uint32_t)luat_airlink_arq_tag() << 8;
    CHECK(luat_airlink_arq_frame_valid(&frame));

    CHECK(luat_airlink_arq_rx(0) == ARQ_RX_DELIVER);
    CHECK(luat_airlink_arq_peek_ack() == 0); // rejected queue/OOM must not ACK
    CHECK(luat_airlink_arq_rx(0) == ARQ_RX_DELIVER); // retry is still deliverable
    luat_airlink_arq_rx_commit(0);
    CHECK(luat_airlink_arq_rx(0) == ARQ_RX_DUP);
    CHECK(luat_airlink_arq_rx(65534) == ARQ_RX_DUP); // delayed, not just last seq
    CHECK(luat_airlink_arq_rx(5) == ARQ_RX_DUP); // out of order cannot ADOPT
    CHECK(luat_airlink_arq_peek_ack() == 1);
    for (unsigned i = 1; i < 65536; i++) {
        CHECK(luat_airlink_arq_rx((uint16_t)i) == ARQ_RX_DELIVER);
        luat_airlink_arq_rx_commit((uint16_t)i);
    }
    CHECK(luat_airlink_arq_peek_ack() == 0);

    luat_airlink_cmd_t* pending = luat_airlink_cmd_new(0x21, 0);
    CHECK(pending != NULL);
    luat_airlink_arq_pending_set(pending, 1);
    luat_airlink_arq_put_peer(2);
    CHECK(!luat_airlink_arq_pending_try_ack());
    luat_airlink_arq_check_giveup(10000);
    CHECK(luat_airlink_arq_pending_cmd() == pending); // no silent timeout loss
    CHECK(luat_airlink_arq_consume_force_down());
    CHECK(!luat_airlink_arq_consume_force_down());
    luat_airlink_arq_put_peer(1);
    CHECK(luat_airlink_arq_pending_try_ack());
    CHECK(!luat_airlink_arq_pending_active());

    peer++;
    memcpy(tail + 8, &peer, 4);
    luat_airlink_arq_peer_info(hello);
    CHECK(!luat_airlink_arq_frame_valid(&frame)); // stale session ACK/data rejected
    CHECK(luat_airlink_arq_peek_ack() == 0);
    peer--;
    memcpy(tail + 8, &peer, 4);
    luat_airlink_arq_peer_info(hello);
    CHECK(!luat_airlink_arq_frame_valid(&frame)); // retired HELLO cannot roll back
    luat_airlink_arq_stop();
    CHECK(!luat_airlink_arq_allow_legacy(&frame)); // reboot before HELLO
    frame.flags.reserved = 3;
    CHECK(luat_airlink_arq_allow_legacy(&frame)); // old RPC/FRAG still deliver
    uint8_t old_bytes[sizeof(airlink_link_data_t) + 128] = {0};
    airlink_link_data_t* old_frame = (void*)old_bytes;
    luat_airlink_cmd_t* old_cmd = (void*)old_frame->data;
    old_frame->len = old_cmd->len = 128; old_cmd->cmd = 0x10;
    CHECK(luat_airlink_arq_command_valid(old_frame) && old_cmd->len == 124);
    old_cmd->cmd = 0x01; old_cmd->len = 128;
    CHECK(!luat_airlink_arq_command_valid(old_frame));
    extern int luat_airlink_uart_parser_selftest(void);
    CHECK(luat_airlink_uart_parser_selftest() == 0);
    lua_pushboolean(L, 1);
    return 1;
#undef CHECK
}
#endif
