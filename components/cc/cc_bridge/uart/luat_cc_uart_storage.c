#include "luat_base.h"
#ifdef LUAT_USE_CC_UART_BRIDGE
#include "luat_cc_uart_storage.h"
#include "luat_rtos.h"
#include "luat_fs.h"
#include <string.h>
#include <stdio.h>
#ifdef _MSC_VER
#include <intrin.h>
#endif

/* Permanent storage; files belong exclusively to storage_task. */
#define REC_SLOTS 51U /* 65280 PCM bytes, just below 64 KiB. */
#define PLAY_SLOTS 8U
#define SEGMENT_FRAMES (60U * 60U * 50U)
static struct {
    luat_cc_uart_config_t config;
    luat_cc_uart_notice_fn notify;
    luat_rtos_task_handle task;
    uint64_t rec_session, play_session;
    uint32_t rec_requested, rec_opening, rec_active, rec_stop, rec_abnormal, rec_failed;
    uint32_t rec_head, rec_count, rec_frames;
    int16_t rec_pcm[REC_SLOTS][640];
    char rec_path[LUAT_CC_UART_PATH_MAX];
    uint32_t play_generation, play_open_generation, play_requested, play_eof, play_failed;
    uint32_t play_head, play_count, play_done;
    int16_t play_pcm[PLAY_SLOTS][320];
    char play_path[LUAT_CC_UART_PATH_MAX];
} s;

static void count_add(uint32_t *value,int amount) {
#ifdef _MSC_VER
    (void)_InterlockedExchangeAdd((volatile long *)value,(long)amount);
#else
    (void)__sync_fetch_and_add(value,amount);
#endif
}

static void notice(const char *event, uint64_t session, const char *data) {
    luat_cc_uart_notice_t n = {0};
    snprintf(n.event, sizeof(n.event), "%s", event);
    n.session = session;
    snprintf(n.data, sizeof(n.data), "%s", data ? data : "");
    s.notify(&n);
}
static void put16(uint8_t *p, unsigned v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void put32(uint8_t *p, uint32_t v) { unsigned i; for (i=0;i<4;i++) p[i]=(uint8_t)(v>>(i*8)); }
static int header(FILE *f, uint32_t bytes) {
    uint8_t h[44] = {0};
    memcpy(h,"RIFF",4); put32(h+4,bytes+36); memcpy(h+8,"WAVEfmt ",8);
    put32(h+16,16); put16(h+20,1); put16(h+22,2); put32(h+24,16000);
    put32(h+28,64000); put16(h+32,4); put16(h+34,16); memcpy(h+36,"data",4); put32(h+40,bytes);
    return luat_fs_fseek(f,0,SEEK_SET) || luat_fs_fwrite(h,1,sizeof(h),f)!=sizeof(h) ? -1 : 0;
}
static int close_record(FILE **file, uint32_t bytes) {
    int result = 0;
    if (*file) {
        if (header(*file,bytes)) result=-1;
        if (luat_fs_fflush(*file)) result=-1;
        if (luat_fs_fclose(*file)) result=-1;
        *file=NULL;
    }
    return result;
}
static FILE *open_segment(const char *base, uint32_t index) {
    char path[LUAT_CC_UART_PATH_MAX + 24];
    FILE *f;
    if (!index) snprintf(path,sizeof(path),"%s",base);
    else snprintf(path,sizeof(path),"%s.%03u.wav",base,(unsigned)index);
    /* Never truncate an existing recording, including after a reboot. */
    if (luat_fs_fexist(path)) return NULL;
    f=luat_fs_fopen(path,"wb");
    if (f && header(f,0)) { luat_fs_fclose(f); return NULL; }
    return f;
}
static void record_failure(uint64_t session, const char *reason) {
    uint32_t cr=luat_rtos_entry_critical();
    uint32_t first=!s.rec_failed;
    s.rec_failed=1; s.rec_stop=1; s.rec_abnormal=1;
    luat_rtos_exit_critical(cr);
    if(first)notice("record_failed",session,reason);
}
static void write_metadata(const char *base, uint64_t session, int abnormal, uint32_t frames) {
    char path[LUAT_CC_UART_PATH_MAX+8], json[160];
    FILE *f;
    snprintf(path,sizeof(path),"%s.json",base);
    snprintf(json,sizeof(json),"{\"session\":\"%08x%08x\",\"abnormal\":%s,\"frames\":%u}\n",
        (unsigned)(session>>32),(unsigned)session,abnormal?"true":"false",(unsigned)frames);
    f=luat_fs_fopen(path,"wb");
    if (!f || luat_fs_fwrite(json,1,strlen(json),f)!=strlen(json))
        record_failure(session,"record metadata write failed");
    if (f && luat_fs_fclose(f)) record_failure(session,"record metadata close failed");
}
static void storage_task(void *unused) {
    FILE *rec=NULL, *play=NULL;
    uint32_t rec_bytes=0, segment=0, segment_frames=0, play_gen=0;
    char rec_path[LUAT_CC_UART_PATH_MAX]={0}, play_path[LUAT_CC_UART_PATH_MAX]={0};
    uint64_t rec_session=0, play_session=0;
    int16_t frame[640];uint32_t play_remaining=0,rec_created=0;
    (void)unused;
    for (;;) {
        uint32_t cr, request, stop, count, gen, eof, slot;
        int worked=0;
        cr=luat_rtos_entry_critical();
        request=s.rec_requested;
        if (request) { s.rec_requested=0; s.rec_opening=1; memcpy(rec_path,s.rec_path,sizeof(rec_path)); rec_session=s.rec_session; }
        luat_rtos_exit_critical(cr);
        if (request) {
            luat_fs_info_t info={0};
            uint64_t available=0;
            rec_created=0;
            if (!luat_fs_info(s.config.record_mount,&info) && info.total_block>=info.block_used)
                available=((uint64_t)info.total_block-(uint64_t)info.block_used)*info.block_size;
            if (available<s.config.min_free_bytes) record_failure(rec_session,"SD free space below admission threshold");
            else {
                rec=open_segment(rec_path,0); rec_bytes=0; segment=0; segment_frames=0;
                if (!rec) record_failure(rec_session,"cannot create WAV on SD");
                else {
                    rec_created=1;
                    cr=luat_rtos_entry_critical();
                    /* A cancelled admission must not resurrect recording. */
                    stop=s.rec_stop;
                    if (!stop) s.rec_active=1;
                    luat_rtos_exit_critical(cr);
                    if (!stop) notice("record_started",rec_session,rec_path);
                }
            }
            cr=luat_rtos_entry_critical();s.rec_opening=0;luat_rtos_exit_critical(cr);
            worked=1;
        }
        cr=luat_rtos_entry_critical();
        count=s.rec_count; stop=s.rec_stop;
        if (count) {
            memcpy(frame,s.rec_pcm[s.rec_head],sizeof(frame));
            s.rec_head=(s.rec_head+1)%REC_SLOTS; count_add(&s.rec_count,-1);
        }
        luat_rtos_exit_critical(cr);
        if (count) {
            if (rec && luat_fs_fwrite(frame,1,sizeof(frame),rec)!=sizeof(frame)) record_failure(rec_session,"SD PCM write failed");
            else if (rec) {
                rec_bytes+=sizeof(frame); segment_frames++;
                if (segment_frames%50==0 && luat_fs_fflush(rec)) record_failure(rec_session,"SD flush failed");
                if (segment_frames>=SEGMENT_FRAMES) {
                    if (close_record(&rec,rec_bytes)) record_failure(rec_session,"WAV segment close failed");
                    else {
                        rec=open_segment(rec_path,++segment); rec_bytes=0; segment_frames=0;
                        if (!rec) record_failure(rec_session,"WAV segment open failed");
                    }
                }
            }
            worked=1;
        } else if (stop) {
            uint32_t abnormal, frames;
            if (close_record(&rec,rec_bytes)) record_failure(rec_session,"WAV header finalization failed");
            cr=luat_rtos_entry_critical(); abnormal=s.rec_abnormal; frames=s.rec_frames; luat_rtos_exit_critical(cr);
            if (rec_created && rec_path[0]) write_metadata(rec_path,rec_session,(int)abnormal,frames);
            rec_path[0]=0;
            cr=luat_rtos_entry_critical(); s.rec_active=0; s.rec_stop=0; luat_rtos_exit_critical(cr);
            notice("record_stopped",rec_session,""); worked=1;
        }

        cr=luat_rtos_entry_critical();
        gen=s.play_generation; request=s.play_requested; eof=s.play_eof;
        count=s.play_count;
        if (request && gen!=play_gen) { memcpy(play_path,s.play_path,sizeof(play_path)); play_session=s.play_session; }
        luat_rtos_exit_critical(cr);
        if (gen!=play_gen) {
            if (play) { luat_fs_fclose(play); play=NULL; }
            play_gen=gen;
            if (request) {
                size_t length=luat_fs_fsize(play_path);
                play_remaining=(uint32_t)length;
                if (!length || length%2) { notice("play_failed",play_session,"PCM file missing or odd byte length"); }
                else play=luat_fs_fopen(play_path,"rb");
                cr=luat_rtos_entry_critical();
                if (s.play_generation==gen) { s.play_open_generation=gen; s.play_failed=play?0:1; s.play_eof=play?0:1; }
                luat_rtos_exit_critical(cr);
                if (!play && length && !(length%2)) notice("play_failed",play_session,"PCM open failed");
            }
            cr=luat_rtos_entry_critical();if(s.play_generation==gen)s.play_open_generation=gen;luat_rtos_exit_critical(cr);
            worked=1;
        }
        if (play && count<PLAY_SLOTS && !eof) {
            size_t n;
            size_t wanted=play_remaining<640?play_remaining:640;
            memset(frame,0,sizeof(frame)); n=luat_fs_fread(frame,1,wanted,play);
            if(n!=wanted) {
                cr=luat_rtos_entry_critical();if(gen==s.play_generation){s.play_failed=1;s.play_eof=1;}luat_rtos_exit_critical(cr);
                notice("play_failed",play_session,"PCM read failed");
                luat_fs_fclose(play);play=NULL;worked=1;continue;
            }
            play_remaining-=(uint32_t)n;
            cr=luat_rtos_entry_critical();
            if (gen==s.play_generation) {
                if (n) { slot=(s.play_head+s.play_count)%PLAY_SLOTS; memcpy(s.play_pcm[slot],frame,640); count_add(&s.play_count,1); }
                if (!play_remaining) s.play_eof=1;
            }
            luat_rtos_exit_critical(cr);
            if (!play_remaining) { luat_fs_fclose(play); play=NULL; }
            worked=1;
        }
        if (!worked) luat_rtos_task_sleep(5);
    }
}
int luat_cc_uart_storage_init(const luat_cc_uart_config_t *config, luat_cc_uart_notice_fn notify) {
    if (s.task) return 0;
    s.config=*config; s.notify=notify;
    return luat_rtos_task_create(&s.task,6144,35,"ccuart_store",storage_task,NULL,0);
}
int luat_cc_uart_storage_play(uint64_t session,const char *path) {
    uint32_t cr;
    if (!path || !path[0] || strlen(path)>=sizeof(s.play_path)) return -1;
    cr=luat_rtos_entry_critical();
    snprintf(s.play_path,sizeof(s.play_path),"%s",path); s.play_session=session;
    count_add(&s.play_generation,1); s.play_requested=1; s.play_eof=0; s.play_done=0; s.play_failed=0; s.play_head=0; s.play_count=0;
    luat_rtos_exit_critical(cr); return 0;
}
void luat_cc_uart_storage_play_stop(void) {
    uint32_t cr=luat_rtos_entry_critical();
    if(s.play_requested) {count_add(&s.play_generation,1);s.play_requested=0;s.play_count=0;s.play_head=0;s.play_eof=0;}
    luat_rtos_exit_critical(cr);
}
void luat_cc_uart_storage_play_frame(int16_t pcm[320]) {
    uint32_t done=0; uint64_t session=0; char path[LUAT_CC_UART_PATH_MAX];
    uint32_t cr=luat_rtos_entry_critical();
    memset(pcm,0,640);
    if (s.play_requested && s.play_count) { memcpy(pcm,s.play_pcm[s.play_head],640); s.play_head=(s.play_head+1)%PLAY_SLOTS; count_add(&s.play_count,-1); }
    if (s.play_requested && s.play_eof && !s.play_count && !s.play_done && !s.play_failed) {
        s.play_done=1; done=1; session=s.play_session; memcpy(path,s.play_path,sizeof(path));
    }
    luat_rtos_exit_critical(cr);
    if (done) notice("play_done",session,path);
}
int luat_cc_uart_storage_record(uint64_t session,const char *path) {
    size_t mount_len=strlen(s.config.record_mount); uint32_t cr;
    if (!path || strlen(path)>=sizeof(s.rec_path) || strncmp(path,s.config.record_mount,mount_len) ||
        path[mount_len]!='/' || strstr(path,"..")) return -1;
    cr=luat_rtos_entry_critical();
    if (s.rec_active || s.rec_requested || s.rec_opening || s.rec_stop) { luat_rtos_exit_critical(cr); return -2; }
    s.rec_session=session; snprintf(s.rec_path,sizeof(s.rec_path),"%s",path);
    s.rec_head=0; s.rec_count=0; s.rec_frames=0; s.rec_failed=0; s.rec_abnormal=0; s.rec_requested=1;
    luat_rtos_exit_critical(cr); return 0;
}
void luat_cc_uart_storage_record_stop(int abnormal) {
    uint32_t cr=luat_rtos_entry_critical();
    if (s.rec_active || s.rec_requested || s.rec_opening) s.rec_stop=1;
    if (abnormal) s.rec_abnormal=1;
    luat_rtos_exit_critical(cr);
}
int luat_cc_uart_storage_record_frame(const int16_t left[320],const int16_t right[320]) {
    uint32_t i,slot,cr=luat_rtos_entry_critical();
    if (!s.rec_active || s.rec_stop) { luat_rtos_exit_critical(cr); return 0; }
    if (s.rec_count==REC_SLOTS) { s.rec_failed=1; s.rec_stop=1; s.rec_abnormal=1; luat_rtos_exit_critical(cr); return -1; }
    slot=(s.rec_head+s.rec_count)%REC_SLOTS;
    for(i=0;i<320;i++) { s.rec_pcm[slot][2*i]=left[i]; s.rec_pcm[slot][2*i+1]=right[i]; }
    count_add(&s.rec_count,1); count_add(&s.rec_frames,1);
    luat_rtos_exit_critical(cr); return 0;
}
int luat_cc_uart_storage_idle(void) {
    int idle; uint32_t cr=luat_rtos_entry_critical();
    idle=!s.rec_active && !s.rec_requested && !s.rec_opening && !s.rec_stop && !s.rec_count && s.play_open_generation==s.play_generation;
    luat_rtos_exit_critical(cr); return idle;
}
void luat_cc_uart_storage_stats(uint32_t *active,uint32_t *frames,uint32_t *failed) {
    uint32_t cr=luat_rtos_entry_critical(); *active=s.rec_active; *frames=s.rec_frames; *failed=s.rec_failed; luat_rtos_exit_critical(cr);
}
#endif
