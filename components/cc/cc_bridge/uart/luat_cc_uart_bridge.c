#include "luat_base.h"
#ifdef LUAT_USE_CC_UART_BRIDGE
#include "luat_cc_uart_bridge.h"
#include "luat_cc_uart_platform.h"
#include "luat_cc_uart_protocol.h"
#include "luat_cc_uart_media.h"
#include "luat_cc_uart_storage.h"
#include "luat_cc_pcm_upload.h"
#include "luat_uart.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#include "luat_cc_uart_dtmf.h"
#include <stdio.h>
#include <string.h>

#define CAPTURE_SLOTS 6U
#define TX_SLOTS 2U
#define CONTROL_SLOTS 8U
#define NOTICE_SLOTS 32U
#define LOCK() luat_rtos_mutex_lock(s.lock,LUAT_WAIT_FOREVER)
#define UNLOCK() luat_rtos_mutex_unlock(s.lock)
#define FAILED() __atomic_load_n(&s.failed,__ATOMIC_ACQUIRE)
#define COUNT(name) __sync_add_and_fetch(&s.stats.name,1)
typedef struct { uint16_t samples; uint32_t rate; int16_t pcm[320]; } capture_t;
typedef struct { uint32_t epoch,sequence; int16_t pcm[320]; } audio_t;
typedef struct { uint64_t session; uint32_t sequence,sent_ms,sends; uint16_t length; char json[257]; } control_t;
static struct {
    luat_cc_uart_config_t config;
    luat_cc_uart_notice_fn notify;
    luat_rtos_mutex_t lock;
    luat_rtos_task_handle media_task,uart_task,notice_task;
    luat_rtos_queue_t notices;
    luat_rtos_semaphore_t uart_wake;
    luat_cc_uart_parser_t parser;
    luat_cc_uart_media_t media;
    luat_cc_uart_resampler_t dl_convert,ul_convert,record_convert;
    luat_cc_uart_stats_t stats;
    uint32_t initialized,boot,call_counter,peer_boot,last_rx_ms,last_hello_ms,last_heartbeat_ms;
    uint32_t record_clock_started,upload_fail_run;
    uint32_t connected,stop_requested,finish_requested,failed,fault_announced;
    uint32_t tx_done,tx_busy,tx_started_ms,tx_sequence,control_sequence;
    uint32_t peer_epoch,peer_epoch_floor,wire_epoch,primed_notified,dtmf_enabled;
    uint32_t platform_stopped,setup_attempted;
    uint32_t capture_head,capture_count;
    capture_t capture[CAPTURE_SLOTS];
    audio_t audio[TX_SLOTS]; uint32_t audio_head,audio_count;
    control_t control[CONTROL_SLOTS];
    struct { uint64_t session; uint32_t sequence; } accepted[16];
    uint32_t accepted_at;
    uint64_t retired_session;
    char fault_reason[128];
    luat_cc_uart_dtmf_t dtmf;
} s;

static uint32_t now_ms(void) { return (uint32_t)luat_mcu_tick64_ms(); }
/* Queue acceptance is the control ACK boundary. No producer enters Lua. */
static int enqueue_notice(const luat_cc_uart_notice_t *n) {
    if (!s.notices || luat_rtos_queue_send(s.notices,(void *)n,sizeof(*n),0)) {
        __sync_add_and_fetch(&s.stats.notice_dropped,1);
        return -1;
    }
    return 0;
}
static void storage_notice(const luat_cc_uart_notice_t *n) {
    if (!strcmp(n->event,"record_failed")) luat_cc_uart_fault(n->data);
    if (enqueue_notice(n)) luat_cc_uart_fault("notification queue exhausted");
}
static void notice(const char *event,uint64_t session,uint32_t value,const char *data) {
    luat_cc_uart_notice_t n={0};
    snprintf(n.event,sizeof(n.event),"%s",event); n.session=session; n.value=value;n.epoch=s.stats.media_epoch;
    snprintf(n.data,sizeof(n.data),"%s",data?data:"");
    if (enqueue_notice(&n)) luat_cc_uart_fault("notification queue exhausted");
}
static void network_dtmf_tick(void) {
    char digit;
    luat_cc_uart_dtmf_end_t ended;
    if (!s.stats.active || s.finish_requested || FAILED() || !s.dtmf_enabled ||
        !s.stats.media_ready || !s.connected) return;
    while (luat_cc_uart_platform_rx_poll(s.stats.session, &digit)) {
        char value[2] = {digit, 0};
        notice("dtmf", s.stats.session, 0, value);
    }
    while (luat_cc_uart_platform_rx_poll_end(s.stats.session, &ended)) {
        luat_cc_uart_notice_t n = {0};
        snprintf(n.event, sizeof(n.event), "dtmf_end");
        n.session = s.stats.session;
        n.epoch = s.stats.media_epoch;
        n.dtmf_end = ended;
        if (enqueue_notice(&n)) luat_cc_uart_fault("notification queue exhausted");
    }
}
void luat_cc_uart_fault(const char *reason) {
    uint32_t cr=luat_rtos_entry_critical();
    if (!FAILED()) { snprintf(s.fault_reason,sizeof(s.fault_reason),"%s",reason?reason:"media fault"); __atomic_store_n(&s.failed,1,__ATOMIC_RELEASE); }
    __atomic_store_n(&s.stop_requested,1,__ATOMIC_RELEASE);
    luat_rtos_exit_critical(cr);
}
static void notification_task(void *unused) {
    luat_cc_uart_notice_t n;
    (void)unused;
    for (;;) if (!luat_rtos_queue_recv(s.notices,&n,sizeof(n),LUAT_WAIT_FOREVER)) s.notify(&n);
}
static void rx_callback(int id,uint32_t length) { (void)id; (void)length; luat_rtos_semaphore_release(s.uart_wake); }
static void sent_callback(int id,void *unused) { (void)id; (void)unused; __atomic_store_n(&s.tx_done,1,__ATOMIC_RELEASE); }

void luat_cc_uart_capture(const int16_t *pcm,uint16_t samples,uint32_t rate) {
    uint32_t slot,cr;
    if (!pcm || (rate!=8000 && rate!=16000) || samples!=rate/50) { luat_cc_uart_fault("invalid 20ms HAL PCM notification"); return; }
    cr=luat_rtos_entry_critical();
    if (!s.stats.active || s.stop_requested) { luat_rtos_exit_critical(cr); return; }
    COUNT(capture_frames);
    if (s.capture_count==CAPTURE_SLOTS) { s.capture_head=(s.capture_head+1)%CAPTURE_SLOTS; __sync_sub_and_fetch(&s.capture_count,1); __sync_add_and_fetch(&s.stats.capture_dropped,1); }
    slot=(s.capture_head+s.capture_count)%CAPTURE_SLOTS;
    s.capture[slot].samples=samples; s.capture[slot].rate=rate; memcpy(s.capture[slot].pcm,pcm,samples*2U); __sync_add_and_fetch(&s.capture_count,1);
    luat_rtos_exit_critical(cr);
}
void luat_cc_uart_connected(int connected) {
    uint32_t cr=luat_rtos_entry_critical(); s.connected=connected?1:0; luat_rtos_exit_critical(cr);
    if (!connected) luat_cc_uart_local_stop();
}
void luat_cc_uart_local_stop(void) {
    __atomic_store_n(&s.stop_requested,1,__ATOMIC_RELEASE);
}
static int matching(uint64_t session) { return s.stats.active && session && session==s.stats.session && !s.finish_requested; }
int luat_cc_uart_setup_done(void) { return __atomic_load_n(&s.initialized,__ATOMIC_ACQUIRE)!=0; }
int luat_cc_uart_active(void) { int a; uint32_t cr=luat_rtos_entry_critical(); a=s.stats.active && !s.finish_requested && !s.failed; luat_rtos_exit_critical(cr); return a; }

static int wire(uint8_t type,uint64_t session,uint32_t sequence,const void *data,uint16_t length,uint8_t *encoded) {
    luat_cc_uart_packet_t p={type,session,sequence,length,(const uint8_t *)data};
    int n=luat_cc_uart_encode(&p,encoded,LUAT_CC_UART_MAX_ENCODED);
    if (n<0) return -1;
    __atomic_store_n(&s.tx_done,0,__ATOMIC_RELEASE);
    if (luat_uart_write(s.config.uart_id,encoded,(size_t)n)!=n) return -1;
    s.tx_busy=1; s.tx_started_ms=now_ms(); return 0;
}
/* ACKs are queued separately so packet callbacks never overwrite in-flight DMA. */
static struct { uint64_t session; uint32_t sequence; } acks[16];
static uint32_t ack_head,ack_count;
static void ack(uint64_t session,uint32_t sequence) {
    if (ack_count<16) { uint32_t at=(ack_head+ack_count)%16; acks[at].session=session; acks[at].sequence=sequence; ack_count++; }
    else luat_cc_uart_fault("ACK queue exhausted");
}
static uint32_t read32(const uint8_t *p) { return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24); }
static void write32(uint8_t *p,uint32_t v) { unsigned i; for(i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i)); }
static void received(void *unused,const luat_cc_uart_packet_t *p) {
    unsigned i; uint32_t tick=now_ms();
    (void)unused;
    if (p->type==LUAT_CC_UART_HELLO || p->type==LUAT_CC_UART_HEARTBEAT) {
        uint32_t boot;
        if (p->payload_len!=5 || p->payload[0]==s.config.role || (p->payload[0]!='A' && p->payload[0]!='B')) return;
        boot=read32(p->payload+1); if (!boot) return;
        if(p->type==LUAT_CC_UART_HEARTBEAT && (!s.stats.link_ready || boot!=s.peer_boot))return;
        if (s.peer_boot && s.peer_boot!=boot) {
            if(s.stats.active) luat_cc_uart_fault("peer rebooted during call");
            memset(s.accepted,0,sizeof(s.accepted)); s.retired_session=0;
        }
        s.peer_boot=boot; s.last_rx_ms=tick;
        if (!s.stats.link_ready) { s.stats.link_ready=1; notice("link_ready",0,0,""); }
        return;
    }
    if (!s.stats.link_ready) return;
    s.last_rx_ms=tick;
    if (p->type==LUAT_CC_UART_ACK) {
        if (p->payload_len) return;
        for(i=0;i<CONTROL_SLOTS;i++) if(s.control[i].length && s.control[i].session==p->session && s.control[i].sequence==p->sequence) s.control[i].length=0;
    } else if (p->type==LUAT_CC_UART_CONTROL) {
        luat_cc_uart_notice_t n={0};
        for(i=0;i<16;i++) if(s.accepted[i].session==p->session && s.accepted[i].sequence==p->sequence) { ack(p->session,p->sequence); return; }
        uint32_t session_boot=s.config.role=='A'?s.boot:s.peer_boot;
        if (!p->session || (uint32_t)(p->session>>32)!=session_boot || p->session==s.retired_session || (s.stats.active && p->session!=s.stats.session) || (!s.stats.active && s.config.role!='B')) { COUNT(stale_packets); return; }
        snprintf(n.event,sizeof(n.event),"control"); n.session=p->session; n.sequence=p->sequence;
        if (!p->payload_len || p->payload_len>256) return;
        memcpy(n.data,p->payload,p->payload_len); n.data[p->payload_len]=0;
        if (!enqueue_notice(&n)) {
            s.accepted[s.accepted_at].session=p->session; s.accepted[s.accepted_at].sequence=p->sequence; s.accepted_at=(s.accepted_at+1)%16;
            ack(p->session,p->sequence);
        }
    } else if (p->type==LUAT_CC_UART_AUDIO) {
        uint32_t epoch; int16_t pcm[320];
        if (!matching(p->session) || s.stats.route==LUAT_CC_UART_ISOLATED) { COUNT(stale_packets); return; }
        epoch=read32(p->payload); if(!epoch || (s.peer_epoch_floor && (int32_t)(epoch-s.peer_epoch_floor)<=0)) {COUNT(stale_packets);return;}
        if (epoch!=s.peer_epoch) {
            if (s.peer_epoch && (int32_t)(epoch-s.peer_epoch)<=0) {COUNT(stale_packets);return;}
            s.peer_epoch=epoch; s.primed_notified=0; luat_cc_uart_media_start(&s.media,p->session,epoch);
        }
        for(i=0;i<320;i++) pcm[i]=(int16_t)((unsigned)p->payload[4+2*i]|((unsigned)p->payload[5+2*i]<<8));
        if (luat_cc_uart_media_push(&s.media,p->session,epoch,p->sequence,pcm)>0) COUNT(rx_frames);
    }
}
static void uart_worker(void *unused) {
    uint8_t encoded[LUAT_CC_UART_MAX_ENCODED], rx[1024], payload[644];
    (void)unused;
    for (;;) {
        int n; uint32_t tick,i,send=0;
        LOCK();
        while ((n=luat_uart_read(s.config.uart_id,rx,sizeof(rx)))>0) luat_cc_uart_parser_feed(&s.parser,rx,(size_t)n,received,NULL);
        /* received() timestamps packets while draining RX. Sample after it
         * finishes so unsigned elapsed times cannot see a future last_rx_ms. */
        tick=now_ms();
        if (s.stats.link_ready && tick-s.last_rx_ms>=3000) {
            s.stats.link_ready=0; notice("link_lost",s.stats.session,0,"peer watchdog timeout");
            if(s.stats.active)luat_cc_uart_fault("UART link lost");
        }
        if (s.tx_busy && __atomic_load_n(&s.tx_done,__ATOMIC_ACQUIRE) && luat_cc_uart_platform_uart_tx_idle(s.config.uart_id)) s.tx_busy=0;
        if (s.tx_busy && tick-s.tx_started_ms>100) luat_cc_uart_fault("UART TX completion timeout");
        if (!s.tx_busy) {
            if (ack_count) {
                if (!wire(LUAT_CC_UART_ACK,acks[ack_head].session,acks[ack_head].sequence,NULL,0,encoded)) { ack_head=(ack_head+1)%16;ack_count--;send=1; }
            } else {
                control_t *c=NULL;
                for(i=0;i<CONTROL_SLOTS;i++)if(s.control[i].length && (!c || (int32_t)(s.control[i].sequence-c->sequence)<0))c=&s.control[i];
                if(c && (!c->sends || tick-c->sent_ms>=200)) {
                    if(c->sends>=3) { luat_cc_uart_notice_t fail={0}; snprintf(fail.event,sizeof(fail.event),"send_failed");fail.session=c->session;fail.sequence=c->sequence;memcpy(fail.data,c->json,c->length+1);enqueue_notice(&fail);c->length=0; }
                    else if (!wire(LUAT_CC_UART_CONTROL,c->session,c->sequence,c->json,c->length,encoded)) { if(c->sends)COUNT(control_retries);__sync_add_and_fetch(&c->sends,1);c->sent_ms=tick;send=1; }
                }
            }
            if(!send && tick-s.last_hello_ms>=(!s.stats.link_ready?1000U:3000U)) {
                payload[0]=(uint8_t)s.config.role;write32(payload+1,s.boot);
                if(!wire(LUAT_CC_UART_HELLO,0,0,payload,5,encoded)) {s.last_hello_ms=tick;send=1;}
            }
            if(!send && s.stats.link_ready && tick-s.last_heartbeat_ms>=1000) {
                payload[0]=(uint8_t)s.config.role;write32(payload+1,s.boot);
                if(!wire(LUAT_CC_UART_HEARTBEAT,0,0,payload,5,encoded)) {s.last_heartbeat_ms=tick;send=1;}
            }
            if(!send && s.audio_count && s.stats.active && s.stats.route!=LUAT_CC_UART_ISOLATED) {
                audio_t *a=&s.audio[s.audio_head]; write32(payload,a->epoch);
                for(i=0;i<320;i++) { payload[4+2*i]=(uint8_t)a->pcm[i];payload[5+2*i]=(uint8_t)((uint16_t)a->pcm[i]>>8); }
                if(!wire(LUAT_CC_UART_AUDIO,s.stats.session,a->sequence,payload,644,encoded)) {s.audio_head=(s.audio_head+1)%TX_SLOTS;__sync_sub_and_fetch(&s.audio_count,1);COUNT(tx_frames);}
            }
        }
        UNLOCK();
        luat_rtos_semaphore_take(s.uart_wake,2);
    }
}
static void dtmf_frame(const int16_t pcm[320]) {
    /* Once this call negotiated telephone-event, consume its authoritative
     * numeric events instead of independently detecting speech/noise as keys. */
    if (!s.dtmf_enabled || luat_cc_uart_platform_rx_network_mode()) return;
    char symbol=luat_cc_uart_dtmf_feed(&s.dtmf,pcm);
    if(symbol) {char digit[2]={symbol,0};notice("dtmf",s.stats.session,0,digit);}
}
static void stop_media_locked(void) {
    uint32_t cr=luat_rtos_entry_critical(); s.capture_count=0;s.capture_head=0;luat_rtos_exit_critical(cr);
    s.stats.route=LUAT_CC_UART_ISOLATED; s.audio_count=0;
    if (s.peer_epoch) luat_cc_uart_media_stop(&s.media,s.stats.session);
    luat_cc_pcm_upload_stop();
    if(s.stats.media_ready)notice("media_stopped",s.stats.session,0,"");
    s.stats.media_ready=0; s.stats.connected=0;
}
static void media_worker(void *unused) {
    uint32_t next=now_ms(),last_epoch=0;
    capture_t cap; int16_t dl[320],ul[320],native[320],record_ul[320];
    (void)unused;
    for (;;) {
        uint32_t tick=now_ms(),have=0,cr,hangup=0,missed=0;
        luat_cc_pcm_upload_stats_t upload={0};
        if ((int32_t)(tick-next)<0) {luat_rtos_task_sleep(next-tick);continue;}
        if (tick-next>=20) {missed=(tick-next)/20;__sync_add_and_fetch(&s.stats.clock_skipped,missed);next=tick;}
        next+=20;
        LOCK();
        if (FAILED() && !s.fault_announced) {s.fault_announced=1;notice("fault",s.stats.session,0,s.fault_reason);hangup=s.stats.active;s.finish_requested=s.stats.active;}
        if (__atomic_exchange_n(&s.stop_requested,0,__ATOMIC_ACQ_REL)) stop_media_locked();
        if (s.finish_requested) {
            luat_cc_uart_storage_play_stop();
            luat_cc_uart_storage_record_stop(FAILED()!=0);
            stop_media_locked();
            if(!s.platform_stopped) {luat_cc_uart_platform_stop();s.platform_stopped=1;}
            /* The native idle query can wait for the SDK event task, which can
             * itself wait for Lua to consume an event. Leave the bridge lock
             * available to Lua while that synchronous query is in flight. */
            uint64_t finishing_session=s.stats.session;
            int native_idle=0;
            if (luat_cc_uart_storage_idle() && !luat_cc_pcm_upload_get_stats(&upload) && !upload.pending && !upload.stop_waiting) {
                UNLOCK();
                native_idle=luat_cc_uart_platform_idle();
                LOCK();
            }
            if (native_idle && s.finish_requested && s.stats.session==finishing_session) {
                uint64_t ended=s.stats.session;
                s.retired_session=ended; cr=luat_rtos_entry_critical();s.stats.active=0;s.stats.session=0;s.finish_requested=0;luat_rtos_exit_critical(cr);
                uint32_t recording,frames,record_fault;luat_cc_uart_storage_stats(&recording,&frames,&record_fault);
                if(!record_fault && !upload.fault) {cr=luat_rtos_entry_critical();__atomic_store_n(&s.failed,0,__ATOMIC_RELEASE);s.fault_announced=0;s.fault_reason[0]=0;luat_rtos_exit_critical(cr);}
                notice("finished",ended,0,"");
            }
            UNLOCK(); if(hangup)luat_cc_uart_platform_hangup();continue;
        }
        if (!s.stats.active) {UNLOCK();if(hangup)luat_cc_uart_platform_hangup();continue;}
        network_dtmf_tick();
        /* Preserve the WAV time axis even if this worker missed upload ticks. */
        if(missed && s.record_clock_started) {
            int16_t silence[320]={0};uint32_t i;
            for(i=0;i<missed && i<52;i++)if(luat_cc_uart_storage_record_frame(silence,silence)) {luat_cc_uart_fault("record time-axis queue overflow");break;}
            if(missed>51)luat_cc_uart_fault("media clock stalled beyond recording buffer");
        }
        cr=luat_rtos_entry_critical();
        s.stats.connected=s.connected;
        if(s.capture_count) { cap=s.capture[s.capture_head];s.capture_head=(s.capture_head+1)%CAPTURE_SLOTS;__sync_sub_and_fetch(&s.capture_count,1);have=1; }
        luat_rtos_exit_critical(cr);
        memset(dl,0,sizeof(dl));memset(ul,0,sizeof(ul));memset(record_ul,0,sizeof(record_ul));
        if (have) {
            if(luat_cc_uart_resampler_convert(&s.dl_convert,cap.pcm,cap.samples,cap.rate,dl,320,16000)!=320)luat_cc_uart_fault("downlink conversion failed");
            s.stats.rate=cap.rate;
        }
        if(luat_cc_pcm_upload_get_stats(&upload) || upload.fault) { if(upload.fault)luat_cc_uart_fault("SoC upload lifecycle fault"); }
        /* A codec transition can stop and restart the SDK recorder before the
         * next media tick. Never let a delayed old PLAY_STOP stop a new epoch.
         * While the recorder is inactive, isolate the bridge and await READY. */
        if(!upload.active && s.stats.media_ready && s.stats.connected && !FAILED()) {
            s.stats.media_ready=0;s.stats.route=LUAT_CC_UART_ISOLATED;s.audio_count=0;
            if(s.peer_epoch)s.peer_epoch_floor=s.peer_epoch;
            s.peer_epoch=0;s.primed_notified=0;luat_cc_uart_media_stop(&s.media,s.stats.session);
            notice("media_changed",s.stats.session,s.stats.rate,"");
        }
        if(upload.active && upload.epoch!=last_epoch) {
            uint32_t changed=s.stats.media_ready;
            last_epoch=upload.epoch; s.stats.media_epoch=upload.epoch;
            if(s.peer_epoch)s.peer_epoch_floor=s.peer_epoch;
            s.peer_epoch=0;s.primed_notified=0;s.audio_count=0;
            luat_cc_uart_resampler_init(&s.ul_convert);luat_cc_uart_resampler_init(&s.dl_convert);luat_cc_uart_resampler_init(&s.record_convert);
            luat_cc_uart_media_stop(&s.media,s.stats.session);
            s.stats.media_ready=0;
            if(changed) {s.stats.route=LUAT_CC_UART_ISOLATED;notice("media_changed",s.stats.session,upload.codec==1?16000:8000,"");}
        }
        if(have && cap.rate!=(upload.codec==LUAT_CC_PCM_UPLOAD_CODEC_WB?16000U:8000U)) {have=0;memset(dl,0,sizeof(dl));}
        if(!FAILED() && s.stats.connected && upload.active && have && !s.stats.media_ready) {s.stats.media_ready=1;s.record_clock_started=1;notice("media_ready",s.stats.session,cap.rate,"");}
        if(s.stats.media_ready && !FAILED() && upload.active) {
            if(s.stats.route!=LUAT_CC_UART_ISOLATED) {
                if(s.audio_count==TX_SLOTS) {s.audio_head=(s.audio_head+1)%TX_SLOTS;__sync_sub_and_fetch(&s.audio_count,1);COUNT(tx_dropped);}
                audio_t *a=&s.audio[(s.audio_head+s.audio_count)%TX_SLOTS];a->epoch=s.wire_epoch;a->sequence=__sync_add_and_fetch(&s.tx_sequence,1);memcpy(a->pcm,dl,640);__sync_add_and_fetch(&s.audio_count,1);
                if(s.peer_epoch && luat_cc_uart_media_ready(&s.media) && !s.primed_notified) {s.primed_notified=1;notice("primed",s.stats.session,s.wire_epoch,"");}
                if(s.stats.route==LUAT_CC_UART_BRIDGE && s.peer_epoch) luat_cc_uart_media_pop(&s.media,s.stats.session,s.peer_epoch,ul);
            } else luat_cc_uart_storage_play_frame(ul);
            if (s.dtmf_enabled && !have) COUNT(dtmf_missing_frames);
            dtmf_frame(dl);
            uint32_t rate=upload.codec==LUAT_CC_PCM_UPLOAD_CODEC_WB?16000:8000;
            int count=luat_cc_uart_resampler_convert(&s.ul_convert,ul,320,16000,native,320,rate);
            if(count>0 && !luat_cc_pcm_upload_submit(native,(uint32_t)count*2,upload.epoch)) {
                s.upload_fail_run=0;
                luat_cc_uart_resampler_convert(&s.record_convert,native,(uint16_t)count,rate,record_ul,320,16000);
            } else {COUNT(upload_errors);if(__sync_add_and_fetch(&s.upload_fail_run,1)>=3)luat_cc_uart_fault("SoC PCM upload rejected on consecutive ticks");}
        }
        if(s.record_clock_started && luat_cc_uart_storage_record_frame(dl,record_ul)) {notice("record_failed",s.stats.session,0,"record queue overflow");luat_cc_uart_fault("record queue overflow");}
        UNLOCK();
        if(hangup)luat_cc_uart_platform_hangup();
    }
}
int luat_cc_uart_setup(const luat_cc_uart_config_t *config,luat_cc_uart_notice_fn notify) {
    luat_uart_t uart={0};
    if(s.setup_attempted)return -2;
    if(!config || !notify || (config->role!='A' && config->role!='B') || (config->dtmf_only && config->role!='A') || config->uart_id<1 || config->uart_id>3 || config->baud_rate!=2000000)return -1;
    s.setup_attempted=1;
    if(luat_crypto_trng((char *)&s.boot,sizeof(s.boot)) || !s.boot)return -3;
    s.config=*config;s.notify=notify;
    if(luat_rtos_mutex_create(&s.lock) || luat_rtos_queue_create(&s.notices,NOTICE_SLOTS,sizeof(luat_cc_uart_notice_t)) || luat_rtos_semaphore_create(&s.uart_wake,0))return -3;
    if(!config->dtmf_only) {
        uart.id=config->uart_id;uart.baud_rate=config->baud_rate;uart.data_bits=8;uart.stop_bits=1;uart.bit_order=LUAT_BIT_ORDER_LSB;uart.parity=LUAT_PARITY_NONE;uart.bufsz=16384;uart.pin485=0xffffffffU;
        if(luat_uart_setup(&uart) || luat_uart_ctrl(uart.id,LUAT_UART_SET_RECV_CALLBACK,(void *)rx_callback) || luat_uart_ctrl(uart.id,LUAT_UART_SET_SENT_CALLBACK,(void *)sent_callback))return -3;
    }
    luat_cc_uart_parser_init(&s.parser);luat_cc_uart_media_init(&s.media);
    luat_cc_uart_media_clock_config_t clock={config->clock_p_ppm,config->clock_i_ppm,config->clock_limit_ppm,config->clock_slew_ppm};
    if(luat_cc_uart_media_configure(&s.media,&clock))return -1;
    if(luat_cc_uart_platform_rx_setup(config->role) || luat_cc_uart_storage_init(config,storage_notice) || luat_rtos_task_create(&s.notice_task,4096,40,"ccuart_notice",notification_task,NULL,0) ||
        (!config->dtmf_only && luat_rtos_task_create(&s.uart_task,6144,65,"ccuart_uart",uart_worker,NULL,0)) || luat_rtos_task_create(&s.media_task,6144,75,"ccuart_media",media_worker,NULL,0))return -3;
    __atomic_store_n(&s.initialized,1,__ATOMIC_RELEASE);return 0;
}
int luat_cc_uart_begin(uint64_t requested,uint64_t *session) {
    uint32_t cr;
    if(!session || !luat_cc_uart_setup_done() || !luat_cc_uart_selected())return -1;
    LOCK();
    if(s.stats.active || (!s.config.dtmf_only && !s.stats.link_ready) || FAILED() || !luat_cc_uart_storage_idle()) {UNLOCK();return -2;}
    if(s.config.role=='A')requested=((uint64_t)s.boot<<32)|__sync_add_and_fetch(&s.call_counter,1);
    else if(!requested || (uint32_t)(requested>>32)!=s.peer_boot || requested==s.retired_session) {UNLOCK();return -1;}
    cr=luat_rtos_entry_critical(); s.stats.session=requested;s.stats.active=1;s.connected=0;__atomic_store_n(&s.stop_requested,0,__ATOMIC_RELEASE);s.finish_requested=0;s.capture_head=0;s.capture_count=0;s.stats.capture_frames=0;s.stats.dtmf_missing_frames=0;luat_rtos_exit_critical(cr);
    s.stats.route=LUAT_CC_UART_ISOLATED;s.stats.media_ready=0;s.peer_epoch=0;s.peer_epoch_floor=0;s.wire_epoch=0;s.primed_notified=0;s.tx_sequence=0;s.dtmf_enabled=0;s.audio_count=0;s.platform_stopped=0;s.record_clock_started=0;
    s.stats.upload_errors=0;s.upload_fail_run=0;
    luat_cc_uart_media_stop(&s.media,requested);luat_cc_uart_resampler_init(&s.dl_convert);luat_cc_uart_resampler_init(&s.ul_convert);
    luat_cc_uart_platform_rx_begin(requested);
    *session=requested;UNLOCK();return 0;
}
int luat_cc_uart_send(uint64_t session,const char *json,size_t length,uint32_t *sequence) {
    unsigned i;if(!json || !length || length>256 || !sequence || !s.lock)return -1;
    LOCK();if(s.config.dtmf_only || !session || (session!=s.stats.session && session!=s.retired_session)) {UNLOCK();return -2;}
    for(i=0;i<CONTROL_SLOTS;i++)if(!s.control[i].length) {control_t *c=&s.control[i];memset(c,0,sizeof(*c));c->session=session;c->sequence=__sync_add_and_fetch(&s.control_sequence,1);c->length=(uint16_t)length;memcpy(c->json,json,length);c->json[length]=0;*sequence=c->sequence;UNLOCK();return 0;}
    UNLOCK();return -3;
}
int luat_cc_uart_route(uint64_t session,unsigned mode) {
    if(mode>LUAT_CC_UART_BRIDGE || !s.lock)return -1;
    LOCK();if(!matching(session) || (s.config.dtmf_only && mode!=LUAT_CC_UART_ISOLATED)) {UNLOCK();return -2;}
    if(mode!=s.stats.route) {
        if(mode==LUAT_CC_UART_ISOLATED || mode==LUAT_CC_UART_PRIMING) {
            s.audio_count=0;if(s.peer_epoch)s.peer_epoch_floor=s.peer_epoch;s.peer_epoch=0;s.primed_notified=0;
            luat_cc_uart_media_stop(&s.media,session);
            if(mode==LUAT_CC_UART_PRIMING && !__sync_add_and_fetch(&s.wire_epoch,1))__sync_add_and_fetch(&s.wire_epoch,1);
        }
        s.stats.route=mode;
    }
    UNLOCK();return 0;
}
int luat_cc_uart_play(uint64_t session,const char *path) {int r;if(!s.lock)return -1;LOCK();r=matching(session)?luat_cc_uart_storage_play(session,path):-2;UNLOCK();return r;}
int luat_cc_uart_play_stop(uint64_t session) {if(!s.lock)return -1;LOCK();if(!matching(session)){UNLOCK();return -2;}luat_cc_uart_storage_play_stop();UNLOCK();return 0;}
int luat_cc_uart_dtmf(uint64_t session,int enabled) {if(!s.lock)return -1;LOCK();if(!matching(session)){UNLOCK();return -2;}s.dtmf_enabled=enabled?1:0;luat_cc_uart_dtmf_init(&s.dtmf);luat_cc_uart_platform_rx_enable(session,enabled);UNLOCK();return 0;}
int luat_cc_uart_record(uint64_t session,const char *path) {int r;if(!s.lock)return -1;LOCK();r=matching(session)&&s.config.role=='A'?luat_cc_uart_storage_record(session,path):-2;UNLOCK();return r;}
int luat_cc_uart_record_stop(uint64_t session) {if(!s.lock)return -1;LOCK();if(!matching(session)){UNLOCK();return -2;}luat_cc_uart_storage_record_stop(0);UNLOCK();return 0;}
int luat_cc_uart_finish(uint64_t session) {if(!s.lock)return -1;LOCK();if(session==s.retired_session){UNLOCK();return 0;}if(!s.stats.active || session!=s.stats.session){UNLOCK();return -2;}s.finish_requested=1;luat_cc_uart_platform_rx_stop(session);__atomic_store_n(&s.stop_requested,1,__ATOMIC_RELEASE);UNLOCK();return 0;}
int luat_cc_uart_get_stats(luat_cc_uart_stats_t *stats) {
    luat_cc_uart_media_stats_t media;luat_cc_uart_parser_stats_t parser;
    if(!stats || !s.lock)return -1;
    LOCK();uint32_t cr=luat_rtos_entry_critical();*stats=s.stats;luat_rtos_exit_critical(cr);stats->wire_epoch=s.wire_epoch;stats->ready=(s.config.dtmf_only || s.stats.link_ready) && !s.stats.active && !FAILED() && luat_cc_uart_storage_idle();
    stats->dtmf_only=s.config.dtmf_only;
    stats->dtmf_enabled=s.dtmf_enabled;stats->dtmf=s.dtmf.diag;
    luat_cc_uart_platform_source_diag(&stats->source);
    luat_cc_uart_platform_rx_stats(&stats->network_dtmf);
    luat_cc_uart_media_get_stats(&s.media,&media);stats->underflow=media.underflows;stats->overflow=media.dropped_samples/320;stats->queue_samples=media.queued_samples;stats->correction_ppm=media.clock_ppm;
    luat_cc_uart_parser_get_stats(&s.parser,&parser);stats->crc_errors=parser.crc_errors;stats->framing_errors=parser.cobs_errors+parser.length_errors+parser.format_errors+parser.oversize_errors;
    luat_cc_uart_storage_stats(&stats->record_active,&stats->record_frames,&stats->record_failed);UNLOCK();return 0;
}
#endif
