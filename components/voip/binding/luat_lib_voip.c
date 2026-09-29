
/*
@module  voip
@summary voip语音通话
@catalog 多媒体
@version 1.0
@date    2026.05.18
@demo sip
@tag LUAT_USE_VOIP
@usage
--[[
]]

*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_conf_bsp.h"
#include "luat_voip_core.h"
#ifdef LUAT_USE_VOIP_PLAY
#include "luat_voip_play.h"
#include "luat_msgbus.h"
#endif
#ifdef LUAT_USE_VOIP_BRIDGE
#include "luat_voip_pcm_resampler.h"
#endif
#include "rotable2.h"
#include "luat_network_adapter.h"
#define LUAT_LOG_TAG "voip"
#include "luat_log.h"

#include <string.h>

#ifdef LUAT_USE_SRTP
#define VOIP_SECURITY_META "voip.security"
#define VOIP_IDENTITY_META "voip.security.identity"
typedef struct { luat_voip_security_t *ctx; } voip_security_ud_t;
typedef struct { luat_voip_security_identity_t *identity; } voip_identity_ud_t;

/* These handles own one reference; the media worker retains its own reference. */
static int l_voip_security_release(lua_State *L)
{
    voip_security_ud_t *ud = luaL_testudata(L, 1, VOIP_SECURITY_META);
    voip_identity_ud_t *identity = luaL_testudata(L, 1, VOIP_IDENTITY_META);
    if (ud && ud->ctx) {
        luat_voip_security_release(ud->ctx);
        ud->ctx = NULL;
    }
    if (identity && identity->identity) {
        luat_voip_security_identity_release(identity->identity);
        identity->identity = NULL;
    }
    lua_pushboolean(L, ud || identity);
    return 1;
}

static void voip_security_metatable(lua_State *L, const char *name)
{
    if (luaL_newmetatable(L, name)) {
        lua_pushcfunction(L, l_voip_security_release);
        lua_setfield(L, -2, "__gc");
        lua_pushliteral(L, "protected");
        lua_setfield(L, -2, "__metatable");
    }
    lua_setmetatable(L, -2);
}

static int voip_security_lua_error(lua_State *L, int error)
{
    lua_pushnil(L);
    lua_pushstring(L, luat_voip_security_error_name(error));
    return 2;
}

/*
创建运行期 DTLS 证书身份，仅用于 exsip 安全协商；私钥不导出。
@api voip.securityIdentity()
@return userdata 身份句柄，失败返回nil及原因
*/
static int l_voip_security_identity(lua_State *L)
{
    int error = 0;
    voip_identity_ud_t *ud = lua_newuserdata(L, sizeof(*ud));
    memset(ud, 0, sizeof(*ud));
    voip_security_metatable(L, VOIP_IDENTITY_META);
    ud->identity = luat_voip_security_identity_create(&error);
    if (!ud->identity) return voip_security_lua_error(L, error);
    return 1;
}

/*
创建安全媒体本地协商材料；同一 SDP 重传必须复用此句柄。
@api voip.securityCreate(mode, identity)
@string mode sdes或dtls-srtp
@userdata identity DTLS可选运行期身份
@return userdata 会话句柄，失败返回nil及原因
*/
static int l_voip_security_create(lua_State *L)
{
    const char *mode = luaL_checkstring(L, 1);
    luat_voip_security_mode_t type;
    luat_voip_security_identity_t *identity = NULL;
    int error = 0;
    if (!strcmp(mode, "sdes")) type = LUAT_VOIP_SECURITY_SDES;
    else if (!strcmp(mode, "dtls-srtp")) type = LUAT_VOIP_SECURITY_DTLS;
    else return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_UNSUPPORTED);
    if (!lua_isnoneornil(L, 2)) {
        voip_identity_ud_t *id = luaL_checkudata(L, 2, VOIP_IDENTITY_META);
        if (!id->identity) return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_STATE);
        identity = id->identity;
    }
    voip_security_ud_t *ud = lua_newuserdata(L, sizeof(*ud));
    memset(ud, 0, sizeof(*ud));
    voip_security_metatable(L, VOIP_SECURITY_META);
    ud->ctx = luat_voip_security_create(type, identity, &error);
    if (!ud->ctx) return voip_security_lua_error(L, error);
    return 1;
}

/*
获取本地 SDP 协商信息。SDES key 为敏感信息，只能通过经验证的 TLS 信令发送。
@api voip.securityInfo(handle)
@userdata handle 安全会话句柄
@return table mode及suite/key或hash/fingerprint，失败返回nil及原因
*/
static int l_voip_security_info(lua_State *L)
{
    voip_security_ud_t *ud = luaL_checkudata(L, 1, VOIP_SECURITY_META);
    luat_voip_security_info_t info = {0};
    int error = luat_voip_security_info(ud->ctx, &info);
    if (error) return voip_security_lua_error(L, error);
    lua_newtable(L);
    lua_pushstring(L, info.mode == LUAT_VOIP_SECURITY_SDES ? "sdes" : "dtls-srtp");
    lua_setfield(L, -2, "mode");
    if (info.mode == LUAT_VOIP_SECURITY_SDES) {
        lua_pushliteral(L, LUAT_VOIP_SECURITY_SUITE); lua_setfield(L, -2, "suite");
        lua_pushstring(L, info.key); lua_setfield(L, -2, "key");
    } else {
        lua_pushliteral(L, "sha-256"); lua_setfield(L, -2, "hash");
        lua_pushstring(L, info.fingerprint); lua_setfield(L, -2, "fingerprint");
    }
    for (size_t i = 0; i < sizeof(info); i++) ((volatile unsigned char *)&info)[i] = 0;
    return 1;
}

static const char *voip_security_string_field(lua_State *L, const char *name, size_t *len)
{
    const char *value;
    /* Raw fields remain rooted in the remote table across userdata allocation. */
    lua_pushstring(L, name);
    lua_rawget(L, 2);
    value = lua_type(L, -1) == LUA_TSTRING ? lua_tolstring(L, -1, len) : NULL;
    if (value && memchr(value, 0, *len)) value = NULL;
    lua_pop(L, 1);
    return value;
}

/*
以本地协商材料创建独立的已协商会话，原句柄不变，可交给voip.start的security字段。
@api voip.securitySetRemote(handle, remote)
@userdata handle 本地安全会话句柄
@table remote mode,suite,key或mode,hash,fingerprint,role(active/passive)
@return userdata 新句柄，失败返回nil及原因
*/
static int l_voip_security_set_remote(lua_State *L)
{
    voip_security_ud_t *source = luaL_checkudata(L, 1, VOIP_SECURITY_META);
    luat_voip_security_remote_t remote = {0};
    luat_voip_security_mode_t local_mode;
    size_t len = 0;
    int error;
    luaL_checktype(L, 2, LUA_TTABLE);
    if (!source->ctx) return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_STATE);
    local_mode = luat_voip_security_mode(source->ctx);
    const char *mode = voip_security_string_field(L, "mode", &len);
    if (!mode || strcmp(mode, local_mode == LUAT_VOIP_SECURITY_SDES ? "sdes" : "dtls-srtp"))
        return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_INVALID);
    if (local_mode == LUAT_VOIP_SECURITY_SDES) {
        remote.suite = voip_security_string_field(L, "suite", &len);
        remote.key = voip_security_string_field(L, "key", &len);
        if (!remote.suite || !remote.key || len != LUAT_VOIP_SECURITY_KEY_TEXT - 1)
            return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_INVALID);
    } else {
        const char *hash = voip_security_string_field(L, "hash", &len);
        if (!hash || strcmp(hash, "sha-256"))
            return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_INVALID);
        const char *role = voip_security_string_field(L, "role", &len);
        if (!role || (strcmp(role, "active") && strcmp(role, "passive")))
            return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_INVALID);
        remote.dtls_client = !strcmp(role, "active");
        remote.fingerprint = voip_security_string_field(L, "fingerprint", &len);
        if (!remote.fingerprint || len != LUAT_VOIP_SECURITY_FINGERPRINT_TEXT - 1)
            return voip_security_lua_error(L, LUAT_VOIP_SECURITY_E_INVALID);
    }
    voip_security_ud_t *ud = lua_newuserdata(L, sizeof(*ud));
    memset(ud, 0, sizeof(*ud));
    voip_security_metatable(L, VOIP_SECURITY_META);
    ud->ctx = luat_voip_security_clone_local(source->ctx, &error);
    if (!ud->ctx) return voip_security_lua_error(L, error);
    error = luat_voip_security_set_remote(ud->ctx, &remote);
    if (error) {
        luat_voip_security_release(ud->ctx);
        ud->ctx = NULL;
        return voip_security_lua_error(L, error);
    }
    return 1;
}
#endif

#ifdef LUAT_USE_VOIP_PLAY
static int voip_play_cb_ref;

typedef struct {
    luat_voip_play_status_t status;
    char event[12];
} voip_play_lua_event_t;

static void voip_play_push_status(lua_State *L, const luat_voip_play_status_t *status)
{
    static const char *states[] = {"idle", "loading", "playing", "stopping"};
    lua_newtable(L);
    lua_pushinteger(L, status->id); lua_setfield(L, -2, "id");
    lua_pushinteger(L, status->session); lua_setfield(L, -2, "session");
    lua_pushstring(L, status->state < 4 ? states[status->state] : "idle");
    lua_setfield(L, -2, "state");
    lua_pushstring(L, status->target == LUAT_VOIP_PLAY_TARGET_BOTH ? "both" :
            status->target == LUAT_VOIP_PLAY_TARGET_CC ? "cc" : "sip");
    lua_setfield(L, -2, "target");
    lua_pushstring(L, status->mode == LUAT_VOIP_PLAY_MIX ? "mix" : "replace");
    lua_setfield(L, -2, "mode");
    lua_pushinteger(L, status->played_samples[0]); lua_setfield(L, -2, "sip_samples");
    lua_pushinteger(L, status->played_samples[1]); lua_setfield(L, -2, "cc_samples");
    if (status->reason[0]) lua_pushstring(L, status->reason); else lua_pushnil(L);
    lua_setfield(L, -2, "reason");
}

static int voip_play_lua_handler(lua_State *L, void *ptr)
{
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    voip_play_lua_event_t *event = (voip_play_lua_event_t *)msg->ptr;
    (void)ptr;
    lua_pop(L, 1);
    if (!event) return 0;
    if (voip_play_cb_ref) {
        lua_rawgeti(L, LUA_REGISTRYINDEX, voip_play_cb_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushstring(L, event->event);
            voip_play_push_status(L, &event->status);
            /* Release the snapshot before user Lua can raise an error. */
            luat_heap_free(event);
            lua_call(L, 2, 0);
            return 0;
        }
        lua_pop(L, 1);
    }
    luat_heap_free(event);
    return 0;
}

static void voip_play_notify(const char *name, const luat_voip_play_status_t *status)
{
    voip_play_lua_event_t *event = luat_heap_malloc(sizeof(*event));
    rtos_msg_t msg = {0};
    if (!event) { LLOGW("play event allocation failed"); return; }
    memset(event, 0, sizeof(*event));
    event->status = *status;
    strncpy(event->event, name, sizeof(event->event) - 1);
    msg.handler = voip_play_lua_handler;
    msg.ptr = event;
    if (luat_msgbus_put(&msg, 0) != 0) {
        luat_heap_free(event);
        LLOGW("play event enqueue failed");
    }
}

static int voip_play_options(lua_State *L, luat_voip_play_options_t *options)
{
    lua_Number gain;
    lua_Integer value;
    const char *text;
    memset(options, 0, sizeof(*options));
    options->target = LUAT_VOIP_PLAY_TARGET_SIP;
    options->mode = LUAT_VOIP_PLAY_REPLACE;
    options->gain_q15 = 32768;
    options->speech_gain_q15 = 16384;
    options->sample_rate = 8000;
    options->channels = 1;
    if (lua_isnoneornil(L, 2)) return 0;
    if (!lua_istable(L, 2)) return -1;
    lua_getfield(L, 2, "target");
    text = lua_isnil(L, -1) ? "sip" : lua_tostring(L, -1);
    if (text && !strcmp(text, "sip")) options->target = LUAT_VOIP_PLAY_TARGET_SIP;
    else if (text && !strcmp(text, "cc")) options->target = LUAT_VOIP_PLAY_TARGET_CC;
    else if (text && !strcmp(text, "both")) options->target = LUAT_VOIP_PLAY_TARGET_BOTH;
    else { lua_pop(L, 1); return -1; }
    lua_pop(L, 1);
    lua_getfield(L, 2, "mode");
    text = lua_isnil(L, -1) ? "replace" : lua_tostring(L, -1);
    if (text && !strcmp(text, "replace")) options->mode = LUAT_VOIP_PLAY_REPLACE;
    else if (text && !strcmp(text, "mix")) options->mode = LUAT_VOIP_PLAY_MIX;
    else { lua_pop(L, 1); return -1; }
    lua_pop(L, 1);
    const char *gain_keys[] = {"gain", "speech_gain"};
    for (unsigned i = 0; i < 2; i++) {
        lua_getfield(L, 2, gain_keys[i]);
        if (!lua_isnil(L, -1)) {
            if (!lua_isnumber(L, -1)) { lua_pop(L, 1); return -1; }
            gain = lua_tonumber(L, -1);
            if (!(gain >= 0 && gain <= 1)) { lua_pop(L, 1); return -1; }
            if (i) options->speech_gain_q15 = (uint16_t)(gain * 32768 + 0.5);
            else options->gain_q15 = (uint16_t)(gain * 32768 + 0.5);
        }
        lua_pop(L, 1);
    }
    lua_getfield(L, 2, "sample_rate");
    if (!lua_isnil(L, -1)) {
        int valid;
        value = lua_tointegerx(L, -1, &valid);
        if (!valid || value < 8000 || value > 48000) { lua_pop(L, 1); return -1; }
        options->sample_rate = (uint32_t)value;
    }
    lua_pop(L, 1);
    lua_getfield(L, 2, "channels");
    if (!lua_isnil(L, -1)) {
        int valid;
        value = lua_tointegerx(L, -1, &valid);
        if (!valid || (value != 1 && value != 2)) { lua_pop(L, 1); return -1; }
        options->channels = (uint8_t)value;
    }
    lua_pop(L, 1);
    return 0;
}

static int voip_play_start_lua(lua_State *L, int tts)
{
    size_t length;
    const char *source = luaL_checklstring(L, 1, &length);
    luat_voip_play_options_t options;
    uint32_t id = 0;
    int ret;
    if (!length || memchr(source, 0, length) || voip_play_options(L, &options)) {
        lua_pushnil(L); lua_pushliteral(L, "invalid_options"); return 2;
    }
    ret = luat_voip_play_init(voip_play_notify);
    if (!ret) {
        ret = tts ? luat_voip_play_start_tts(source, length, &options, &id) :
                    luat_voip_play_start_file(source, &options, &id);
    }
    if (ret) {
        lua_pushnil(L); lua_pushstring(L, luat_voip_play_error(ret)); return 2;
    }
    lua_pushinteger(L, id);
    return 1;
}

/*
向当前通话对端播放TTS，不占用本地音频设备。
@api voip.playTTS(text, opts)
@string text UTF-8文本
@table opts 可选配置：target="sip"/"cc"/"both"（cc/both仅支持纯PCM桥接），mode="replace"/"mix"，gain和speech_gain为0~1
@return int 成功返回播放ID，失败返回nil
@return string 失败原因；同一时刻只允许一个播报任务，忙时为busy
@usage
local id, err = voip.playTTS("您好，请稍候", {target="sip", mode="replace"})
*/
static int l_voip_play_tts(lua_State *L) { return voip_play_start_lua(L, 1); }

/*
向当前通话对端播放本地PCM16、PCM WAV或MP3文件。
@api voip.playFile(path, opts)
@string path 文件系统路径
@table opts 同playTTS；裸PCM另支持sample_rate和channels，默认8000和1，格式PCM16LE
@return int 成功返回播放ID，失败返回nil
@return string 失败原因
@usage
local id, err = voip.playFile("/luadb/prompt.mp3", {target="both", mode="mix"})
*/
static int l_voip_play_file(lua_State *L) { return voip_play_start_lua(L, 0); }

/*
异步停止指定通话播报；终态事件或playStatus().state为idle表示资源已释放，可以再次播放。
@api voip.playStop(id)
@int id playTTS/playFile返回的播放ID
@return boolean 是否接受停止请求
@return string 失败原因
*/
static int l_voip_play_stop(lua_State *L)
{
    lua_Integer id = luaL_checkinteger(L, 1);
    int ret = id > 0 && (uint64_t)id <= UINT32_MAX ?
            luat_voip_play_stop((uint32_t)id) : LUAT_VOIP_PLAY_E_INVALID;
    lua_pushboolean(L, ret == 0);
    if (ret) { lua_pushstring(L, luat_voip_play_error(ret)); return 2; }
    return 1;
}

/*
查询通话播报状态。sip_samples/cc_samples为已提交到发送接口的8kHz源样本数，非对端播放确认。
@api voip.playStatus()
@return table id/state/target/mode/sip_samples/cc_samples/reason；state为idle/loading/playing/stopping
*/
static int l_voip_play_status(lua_State *L)
{
    luat_voip_play_status_t status = {0};
    luat_voip_play_get_status(&status);
    voip_play_push_status(L, &status);
    return 1;
}
#endif

/*
启动voip语音通话
@api voip.start(opts)
@table opts 配置表
@return boolean 成功返回 true, 失败返回 false
@usage
voip.start({
    remote_ip   = "192.168.1.100",
    remote_port = 10000,
    local_port  = 10000,
    codec       = 0,            -- 0:PCMU  1:PCMA
    ptime       = 20,           -- 打包时长 ms
    sample_rate = 8000,
    jitter_depth= 3,
    multimedia_id = 0,
    stats_interval = 5000,      -- 统计回调间隔 ms, 0=不回调
    aec = true,
    aec_mode = "speex",       -- "speex" 或 "bk"
    aec_denoise = true,
    aec_agc = false,
    aec_delay_samples = 160,
    aec_tail = 120,
})
*/
static int l_voip_start(lua_State *L)
{
    if (!lua_istable(L, 1)) {
        LLOGE("voip.start requires a table argument");
        lua_pushboolean(L, 0);
        return 1;
    }

    voip_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));

    /* remote_ip */
    lua_getfield(L, 1, "remote_ip");
    if (lua_isstring(L, -1)) {
        const char *ip = lua_tostring(L, -1);
        size_t len = strlen(ip);
        if (len >= sizeof(cfg.remote_ip)) len = sizeof(cfg.remote_ip) - 1;
        memcpy(cfg.remote_ip, ip, len);
        cfg.remote_ip[len] = '\0';
    }
    lua_pop(L, 1);

    /* remote_port */
    lua_getfield(L, 1, "remote_port");
    cfg.remote_port = (uint16_t)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /* local_port */
    lua_getfield(L, 1, "local_port");
    cfg.local_port = (uint16_t)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /* codec: 0=PCMU, 1=PCMA */
    lua_getfield(L, 1, "codec");
    cfg.codec = (uint8_t)luaL_optinteger(L, -1, VOIP_CODEC_PCMU);
    lua_pop(L, 1);

    /* ptime */
    lua_getfield(L, 1, "ptime");
    cfg.ptime = (uint16_t)luaL_optinteger(L, -1, VOIP_FRAME_MS_DEFAULT);
    lua_pop(L, 1);

    /* sample_rate */
    lua_getfield(L, 1, "sample_rate");
    cfg.sample_rate = (uint32_t)luaL_optinteger(L, -1, VOIP_SAMPLE_RATE_DEFAULT);
    lua_pop(L, 1);


    /* jitter_depth */
    lua_getfield(L, 1, "jitter_depth");
    cfg.jitter_depth = (uint16_t)luaL_optinteger(L, -1, VOIP_JB_DEPTH_DEFAULT);
    lua_pop(L, 1);

    /* multimedia_id */
    lua_getfield(L, 1, "multimedia_id");
    cfg.multimedia_id = (uint8_t)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /* stats_interval */
    lua_getfield(L, 1, "stats_interval");
    cfg.stats_interval_ms = (uint32_t)luaL_optinteger(L, -1, VOIP_STATS_INTERVAL_DEFAULT);
    lua_pop(L, 1);

    /* aec */
    lua_getfield(L, 1, "aec");
    cfg.aec_enable = lua_toboolean(L, -1) ? 1 : 0;
    lua_pop(L, 1);

    /* aec_denoise */
    lua_getfield(L, 1, "aec_denoise");
    cfg.aec_denoise = lua_isboolean(L, -1) ? (lua_toboolean(L, -1) ? 1 : 0) : cfg.aec_enable;
    lua_pop(L, 1);

    /* aec_mode */
    cfg.aec_mode = VOIP_AEC_MODE_SPEEX;
    lua_getfield(L, 1, "aec_mode");
    if (lua_isstring(L, -1)) {
        const char *mode = lua_tostring(L, -1);
        if (!strcmp(mode, "speex")) {
            cfg.aec_mode = VOIP_AEC_MODE_SPEEX;
        } else if (!strcmp(mode, "bk")) {
            cfg.aec_mode = VOIP_AEC_MODE_BK;
        } else {
            LLOGE("voip.start: aec_mode must be 'speex' or 'bk'");
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            return 1;
        }
    }
    lua_pop(L, 1);

    /* aec_agc */
    lua_getfield(L, 1, "aec_agc");
    if (lua_isboolean(L, -1)) {
        cfg.aec_agc = lua_toboolean(L, -1) ? 1 : 0;
    } else {
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        cfg.aec_agc = 0;
#else
        /* Preserve the legacy Speex behavior on existing BSPs. */
        cfg.aec_agc = cfg.aec_denoise;
#endif
    }
    lua_pop(L, 1);

    /* aec_tail */
    lua_getfield(L, 1, "aec_tail");
    cfg.aec_tail_ms = (uint16_t)luaL_optinteger(L, -1, 120);
    lua_pop(L, 1);

    /* aec_delay_samples */
    lua_getfield(L, 1, "aec_delay_samples");
    cfg.aec_delay_samples = (uint16_t)luaL_optinteger(L, -1, 160);
    lua_pop(L, 1);

    /* adapter */
    lua_getfield(L, 1, "adapter");
    cfg.adapter = (int)luaL_optinteger(L, -1, network_register_get_default());
    lua_pop(L, 1);

    lua_getfield(L, 1, "security");
    if (!lua_isnil(L, -1)) {
#ifdef LUAT_USE_SRTP
        voip_security_ud_t *security = luaL_testudata(L, -1, VOIP_SECURITY_META);
        if (!security || !security->ctx) {
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            lua_pushliteral(L, "invalid_media_security");
            return 2;
        }
        cfg.security = security->ctx;
#else
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        lua_pushliteral(L, "media_security_unsupported");
        return 2;
#endif
    }
    lua_pop(L, 1);

    /* 基本校验 */
    if (cfg.remote_ip[0] == '\0' || cfg.remote_port == 0) {
        LLOGE("voip.start: remote_ip and remote_port are required");
        lua_pushboolean(L, 0);
        return 1;
    }

    int ret = voip_start(&cfg);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
停止voip语音通话
@api voip.stop()
@return boolean 成功返回 true
@usage
voip.stop()
*/
static int l_voip_stop(lua_State *L)
{
    (void)L;
    int ret = voip_stop();
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
注册voip回调函数
@api voip.on(event, callback)
@string event 事件名: "state", "stats", "error", "record", "play"；play回调为(event, info)，事件为started/done/stopped/error
@function callback 回调函数
@return nil
@usage
voip.on("state", function(state)
    log.info("voip", "state changed:", state)  -- "started"/"stopped"/"error"
end)

voip.on("stats", function(stats)
    log.info("voip", "tx_packets:", stats.tx_packets, "rx_packets:", stats.rx_packets)
end)

voip.on("error", function(err)
    log.error("voip", "error:", err)
end)
*/
static int l_voip_on(lua_State *L)
{
    const char *event = luaL_checkstring(L, 1);
    voip_ctx_t *ctx = voip_get_ctx();

    if (!lua_isfunction(L, 2) && !lua_isnil(L, 2)) {
        return luaL_argerror(L, 2, "function or nil expected");
    }

    int *ref_ptr = NULL;
    if (strcmp(event, "state") == 0) {
        ref_ptr = &ctx->cb_state_ref;
    } else if (strcmp(event, "stats") == 0) {
        ref_ptr = &ctx->cb_stats_ref;
    } else if (strcmp(event, "error") == 0) {
        ref_ptr = &ctx->cb_error_ref;
#ifdef LUAT_USE_VOIP_PLAY
    } else if (strcmp(event, "play") == 0) {
        ref_ptr = &voip_play_cb_ref;
#endif
#ifdef LUAT_USE_VOIP_RECORD
    } else if (strcmp(event, "record") == 0) {
        ref_ptr = &ctx->cb_record_ref;
#endif
    } else {
        LLOGW("voip.on: unknown event '%s'", event);
        return 0;
    }

    /* 释放旧的引用 */
    if (*ref_ptr != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, *ref_ptr);
        *ref_ptr = 0;
    }

    /* 设置新引用 */
    if (lua_isfunction(L, 2)) {
        lua_pushvalue(L, 2);
        *ref_ptr = luaL_ref(L, LUA_REGISTRYINDEX);
    }

    return 0;
}

/*
获取voip统计信息
@api voip.stats()
@return table 统计信息
@usage
local s = voip.stats()
log.info("voip", "tx_packets:", s.tx_packets)
*/
static int l_voip_stats(lua_State *L)
{
    voip_push_stats(L);
    return 1;
}

/*
获取voip是否正在运行
@api voip.isRunning()
@return boolean 是否正在运行
@usage
if voip.isRunning() then
    log.info("voip", "audio active")
end
*/
static int l_voip_is_running(lua_State *L)
{
    lua_pushboolean(L, voip_is_running());
    return 1;
}

/*
获取voip当前状态
@api voip.getState()
@return string 状态字符串: "idle"/"starting"/"running"/"stopping"/"error"
@usage
log.info("voip", "state:", voip.getState())
*/
static int l_voip_get_state(lua_State *L)
{
    voip_state_t state = voip_get_state();
    const char *s;
    switch (state) {
    case VOIP_STATE_IDLE:     s = "idle"; break;
    case VOIP_STATE_STARTING: s = "starting"; break;
    case VOIP_STATE_RUNNING:  s = "running"; break;
    case VOIP_STATE_STOPPING: s = "stopping"; break;
    case VOIP_STATE_ERROR:    s = "error"; break;
    default:                  s = "unknown"; break;
    }
    lua_pushstring(L, s);
    return 1;
}

#ifdef LUAT_USE_VOIP_RECORD
static const char *voip_record_error_name(int ret)
{
    switch (ret) {
    case -1: return "invalid_path";
    case -2: return "invalid_state";
    case -3: return "already_recording";
    default: return "no_memory";
    }
}

/*
开始本地双声道WAV录音。
@api voip.recordStart(path, opts)
@string path 以.wav结尾的文件路径
@table opts 可选配置，max_seconds默认7200
@return boolean 成功返回true
@return string 失败原因，成功时为nil
*/
static int l_voip_record_start(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    uint32_t max_seconds = 7200;
    int ret;
    if (lua_istable(L, 2)) {
        lua_Integer value;
        lua_getfield(L, 2, "max_seconds");
        value = luaL_optinteger(L, -1, 7200);
        if (value > 0) max_seconds = (uint32_t)value;
        lua_pop(L, 1);
    }
    ret = voip_record_start(path, max_seconds);
    lua_pushboolean(L, ret == 0);
    if (ret == 0) lua_pushnil(L); else lua_pushstring(L, voip_record_error_name(ret));
    return 2;
}

/*
异步停止并收尾当前录音。
@api voip.recordStop()
@return boolean 成功返回true
@return string 失败原因，成功时为nil
*/
static int l_voip_record_stop(lua_State *L)
{
    int ret = voip_record_stop();
    lua_pushboolean(L, ret == 0);
    if (ret == 0) lua_pushnil(L); else lua_pushstring(L, "invalid_state");
    return 2;
}

/*
获取本地录音状态。
@api voip.recordStatus()
@return table 当前录音状态
*/
static int l_voip_record_status(lua_State *L)
{
    voip_record_status_t status;
    voip_record_get_status(&status);
    lua_newtable(L);
    lua_pushstring(L, luat_voip_record_state_name(status.state)); lua_setfield(L, -2, "state");
    lua_pushstring(L, status.path); lua_setfield(L, -2, "path");
    lua_pushinteger(L, status.bytes); lua_setfield(L, -2, "bytes");
    lua_pushinteger(L, status.duration_ms); lua_setfield(L, -2, "duration_ms");
    lua_pushinteger(L, status.queued_frames); lua_setfield(L, -2, "queued_frames");
    lua_pushinteger(L, status.dropped_frames); lua_setfield(L, -2, "dropped_frames");
    if (status.reason[0]) lua_pushstring(L, status.reason); else lua_pushnil(L);
    lua_setfield(L, -2, "reason");
    return 1;
}
#endif

/*
设置音频工作模式
@api voip.setAudioMode(mode)
@int mode 0: I2S直接硬件模式, 1: 桥接模式
@return boolean 成功返回true
@usage
voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)
*/
#ifdef LUAT_USE_VOIP_BRIDGE
static int l_voip_set_audio_mode(lua_State *L)
{
    int mode = luaL_checkinteger(L, 1);
    int ret = voip_set_audio_mode((voip_audio_mode_t)mode);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
注入上行PCM数据（桥接模式）
外部采集的PCM数据送入voip，编码后通过RTP发送
@api voip.pcmIn(data)
@string data 16bit单声道PCM数据（小端字节序）
@return int 实际消耗的样本数
@usage
local consumed = voip.pcmIn(pcm_data)
*/
static int l_voip_pcm_in(lua_State *L)
{
    size_t len = 0;
    const char *data = luaL_checklstring(L, 1, &len);
    if (len == 0) {
        lua_pushinteger(L, 0);
        return 1;
    }
    uint16_t samples = (uint16_t)(len / sizeof(int16_t));
    int ret = voip_bridge_pcm_in((const int16_t *)data, samples);
    lua_pushinteger(L, ret);
    return 1;
}

/*
取出下行PCM数据（桥接模式）
从voip获取SIP服务器发送过来的解码后PCM数据，用于播放
@api voip.pcmOut(max_samples)
@int max_samples 最大请求样本数
@return string 解码后的PCM数据，无数据返回nil
@usage
local pcm = voip.pcmOut(160)
*/
static int l_voip_pcm_out(lua_State *L)
{
    uint16_t max_samples = (uint16_t)luaL_checkinteger(L, 1);
    if (max_samples == 0) {
        lua_pushnil(L);
        return 1;
    }
    int16_t *buf = (int16_t *)luat_heap_malloc(max_samples * sizeof(int16_t));
    if (!buf) {
        lua_pushnil(L);
        return 1;
    }
    int ret = voip_bridge_pcm_out(buf, max_samples);
    if (ret > 0) {
        lua_pushlstring(L, (const char *)buf, (size_t)ret * sizeof(int16_t));
    } else {
        lua_pushnil(L);
    }
    luat_heap_free(buf);
    return 1;
}

/* The converter belongs to its Lua caller, independently of the VoIP session
 * and CC route. It has no external resources and needs no __gc callback. */
#define VOIP_PCM_RESAMPLER_META "voip.pcmResampler"

static int l_voip_pcm_resampler_process(lua_State *L)
{
    voip_pcm_resampler_t *state = (voip_pcm_resampler_t *)luaL_checkudata(L, 1, VOIP_PCM_RESAMPLER_META);
    size_t bytes = 0;
    const uint8_t *input = (const uint8_t *)luaL_checklstring(L, 2, &bytes);
    uint8_t output[VOIP_PCM_RESAMPLER_MAX_OUTPUT_BYTES];
    uint32_t clipped = 0;
    int produced = voip_pcm_resampler_process(state, input, bytes, output, sizeof(output), &clipped);
    if (produced < 0) {
        return luaL_argerror(L, 2, "invalid PCM block size for this converter");
    }
    lua_pushlstring(L, (const char *)output, (size_t)produced);
    lua_pushinteger(L, clipped);
    return 2;
}

static int l_voip_pcm_resampler_reset(lua_State *L)
{
    voip_pcm_resampler_t *state = (voip_pcm_resampler_t *)luaL_checkudata(L, 1, VOIP_PCM_RESAMPLER_META);
    voip_pcm_resampler_reset(state);
    return 0;
}

/*
创建外部PCM通道的有状态采样率转换器，仅通用PCM桥接固件提供。
16k→8k沿用7抽头二项式低通抽取，8k→16k使用相邻样本线性插值。
输入输出均为PCM16小端单声道；滤波历史跨process调用保留，reset清零历史。
每次16k输入最多512字节且长度为4的倍数，8k输入最多320字节且长度为2的倍数。
process返回转换后的PCM字符串和本次增益限幅的样本数；空输入返回空字符串和0。
非法参数抛出Lua错误，不改变转换器状态。每路音频应使用独立实例，通话开始/结束时reset。
@api voip.pcmResampler(input_rate, output_rate, gain)
@int input_rate 输入采样率，仅支持16000→8000或8000→16000
@int output_rate 输出采样率
@int gain 可选，16k→8k的整数增益1..8，默认1；8k→16k只支持1
@return userdata PCM转换器，提供process(data)和reset()方法
@usage
local mic = voip.pcmResampler(16000, 8000, 1)
local speaker = voip.pcmResampler(8000, 16000)
local pcm8k, clipped = mic:process(pcm16k) -- pcm16k是一帧512字节
local consumed = voip.pcmIn(pcm8k)        -- 仍返回8kHz采样数，保留未消费尾部再送入
local downlink = voip.pcmOut(160)
if downlink then
    local pcm16k_play = speaker:process(downlink)
end
mic:reset()
speaker:reset()
*/
static int l_voip_pcm_resampler(lua_State *L)
{
    lua_Integer input_rate = luaL_checkinteger(L, 1);
    lua_Integer output_rate = luaL_checkinteger(L, 2);
    lua_Integer gain = luaL_optinteger(L, 3, 1);
    if (!((input_rate == 16000 && output_rate == 8000) ||
            (input_rate == 8000 && output_rate == 16000))) {
        return luaL_error(L, "PCM converter supports only 16000/8000 or 8000/16000");
    }
    if (gain < 1 || gain > 8 || (input_rate == 8000 && gain != 1)) {
        return luaL_argerror(L, 3, "gain must be 1..8 for 16k input, or 1 for 8k input");
    }
    voip_pcm_resampler_t *state = (voip_pcm_resampler_t *)lua_newuserdata(L, sizeof(*state));
    memset(state, 0, sizeof(*state));
    voip_pcm_resampler_init(state, (uint32_t)input_rate, (uint32_t)output_rate, (unsigned)gain);
    if (luaL_newmetatable(L, VOIP_PCM_RESAMPLER_META)) {
        lua_pushcfunction(L, l_voip_pcm_resampler_process);
        lua_setfield(L, -2, "process");
        lua_pushcfunction(L, l_voip_pcm_resampler_reset);
        lua_setfield(L, -2, "reset");
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}

/*
控制桥接模式内部早期提示音。
@api voip.bridgeTone(on)
@boolean on true启动，false停止
@return boolean 成功返回 true
@usage
voip.bridgeTone(true)
*/
static int l_voip_bridge_tone(lua_State *L)
{
    int ret = voip_bridge_tone(lua_toboolean(L, 1) ? 1 : 0);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
控制运行中的纯 PCM 桥接双向通话语音静音，TTS/音频注入和媒体节拍不受影响。
仅 cc.AUDIO_MODE_BRIDGE_PCM 后端支持；会话启动和停止时自动恢复为未静音。
@api voip.bridgeMute(on)
@boolean on true静音原通话语音，false恢复
@return boolean 成功返回true，非运行中的纯PCM桥接返回false
@usage
voip.bridgeMute(true)
*/
static int l_voip_bridge_mute(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TBOOLEAN);
    lua_pushboolean(L, voip_bridge_mute(lua_toboolean(L, 1)) == 0);
    return 1;
}

#endif

#include "rotable2.h"

static const rotable_Reg_t reg_voip[] =
{
    { "start",      ROREG_FUNC(l_voip_start)},
    { "stop",       ROREG_FUNC(l_voip_stop)},
    { "on",         ROREG_FUNC(l_voip_on)},
    { "stats",      ROREG_FUNC(l_voip_stats)},
    { "isRunning",  ROREG_FUNC(l_voip_is_running)},
    { "getState",   ROREG_FUNC(l_voip_get_state)},
#ifdef LUAT_USE_SRTP
    { "securityIdentity", ROREG_FUNC(l_voip_security_identity)},
    { "securityCreate", ROREG_FUNC(l_voip_security_create)},
    { "securityInfo", ROREG_FUNC(l_voip_security_info)},
    { "securitySetRemote", ROREG_FUNC(l_voip_security_set_remote)},
    { "securityRelease", ROREG_FUNC(l_voip_security_release)},
#endif
#ifdef LUAT_USE_VOIP_PLAY
    { "playTTS", ROREG_FUNC(l_voip_play_tts)},
    { "playFile", ROREG_FUNC(l_voip_play_file)},
    { "playStop", ROREG_FUNC(l_voip_play_stop)},
    { "playStatus", ROREG_FUNC(l_voip_play_status)},
#endif
#ifdef LUAT_USE_VOIP_RECORD
    { "recordStart", ROREG_FUNC(l_voip_record_start)},
    { "recordStop",  ROREG_FUNC(l_voip_record_stop)},
    { "recordStatus", ROREG_FUNC(l_voip_record_status)},
#endif

#ifdef LUAT_USE_VOIP_BRIDGE
    { "setAudioMode", ROREG_FUNC(l_voip_set_audio_mode)},
    { "pcmIn",      ROREG_FUNC(l_voip_pcm_in)},
    { "pcmOut",     ROREG_FUNC(l_voip_pcm_out)},
    { "pcmResampler", ROREG_FUNC(l_voip_pcm_resampler)},
    { "bridgeTone", ROREG_FUNC(l_voip_bridge_tone)},
    { "bridgeMute", ROREG_FUNC(l_voip_bridge_mute)},
#endif

    /* 常量 */
    { "PCMU",       ROREG_INT(VOIP_CODEC_PCMU)},
    { "PCMA",       ROREG_INT(VOIP_CODEC_PCMA)},
    { "AUDIO_MODE_I2S",   ROREG_INT(VOIP_AUDIO_MODE_I2S)},
#ifdef LUAT_USE_VOIP_BRIDGE
    { "AUDIO_MODE_BRIDGE", ROREG_INT(VOIP_AUDIO_MODE_BRIDGE)},
#endif

    { NULL,         ROREG_INT(0)}
};

LUAMOD_API int luaopen_voip(lua_State *L)
{
    luat_newlib2(L, reg_voip);
    return 1;
}
