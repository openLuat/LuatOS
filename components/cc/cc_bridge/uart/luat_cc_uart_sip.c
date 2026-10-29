#include "luat_cc_uart_sip.h"
#include <string.h>

typedef luat_cc_uart_sip_span_t span_t;
typedef luat_cc_uart_sip_message_t message_t;
enum { M_OTHER, M_INVITE, M_UPDATE, M_BYE, M_CANCEL };

static int lower(int ch) { return ch >= 'A' && ch <= 'Z' ? ch + ('a' - 'A') : ch; }
static int eq(span_t s, const char *v) {
    size_t i, n = strlen(v);
    if (s.n != n) return 0;
    for (i = 0; i < n; i++) if (lower((unsigned char)s.p[i]) != lower((unsigned char)v[i])) return 0;
    return 1;
}
static span_t trim(span_t s) {
    while (s.n && (*s.p == ' ' || *s.p == '\t')) { s.p++; s.n--; }
    while (s.n && (s.p[s.n-1] == ' ' || s.p[s.n-1] == '\t')) s.n--;
    return s;
}
static int copy(span_t s, char *out, size_t capacity) {
    if (!s.n || s.n >= capacity || memchr(s.p, 0, s.n)) return 0;
    memcpy(out, s.p, s.n); out[s.n] = 0; return 1;
}
static int number(span_t s, uint32_t max, uint32_t *out) {
    uint32_t v = 0; size_t i;
    if (!s.n) return 0;
    for (i = 0; i < s.n; i++) {
        unsigned d = (unsigned char)s.p[i] - '0';
        if (d > 9 || v > (max - d) / 10U || d > max) return 0;
        v = v * 10U + d;
    }
    *out = v; return 1;
}
static span_t token(span_t *s) {
    span_t t;
    *s = trim(*s); t = *s; t.n = 0;
    while (t.n < s->n && s->p[t.n] != ' ' && s->p[t.n] != '\t') t.n++;
    s->p += t.n; s->n -= t.n; return t;
}
static int line(span_t *s, span_t *out) {
    size_t i;
    if (!s->n) return 0;
    for (i = 0; i < s->n && s->p[i] != '\n'; i++) { }
    *out = *s; out->n = i;
    if (out->n && out->p[out->n-1] == '\r') out->n--;
    s->p += i + (i < s->n); s->n -= i + (i < s->n); return 1;
}
static unsigned method(span_t s) {
    if (eq(s,"INVITE")) return M_INVITE;
    if (eq(s,"UPDATE")) return M_UPDATE;
    if (eq(s,"BYE")) return M_BYE;
    if (eq(s,"CANCEL")) return M_CANCEL;
    return M_OTHER;
}
static int tag(span_t s, char *out) {
    size_t i;
    out[0] = 0;
    for (i = 0; i + 5U <= s.n; i++) if (s.p[i] == ';' &&
        lower(s.p[i+1]) == 't' && lower(s.p[i+2]) == 'a' && lower(s.p[i+3]) == 'g' && s.p[i+4] == '=') {
        span_t v = { s.p+i+5, s.n-i-5 }; size_t j = 0;
        while (j < v.n && v.p[j] != ';' && v.p[j] != ' ' && v.p[j] != '\t') j++;
        v.n = j; return copy(v, out, LUAT_CC_UART_SIP_TAG_MAX);
    }
    return 1;
}
static size_t header_end(const char *p, size_t n) {
    size_t i;
    for (i = 0; i + 3 < n; i++) if (!memcmp(p+i,"\r\n\r\n",4)) return i + 4;
    return 0;
}
/* Require Content-Length, including zero, so TCP boundaries never depend on
 * guessing where a subsequent request starts. Compact SIP forms are accepted. */
static int frame_size(const char *p, size_t end, size_t *total) {
    span_t s = { p, end }, l; uint32_t length = 0; int have = 0;
    if (!line(&s,&l)) return 0;
    while (line(&s,&l) && l.n) {
        const char *colon = (const char *)memchr(l.p, ':', l.n);
        span_t name, value;
        if (!colon || l.p[0] == ' ' || l.p[0] == '\t') return 0;
        name.p = l.p; name.n = (size_t)(colon-l.p); name = trim(name);
        value.p = colon+1; value.n = l.n-(size_t)(colon-l.p)-1; value = trim(value);
        if (eq(name,"Content-Length") || eq(name,"l")) {
            if (have || !number(value, LUAT_CC_UART_SIP_MESSAGE_MAX, &length)) return 0;
            have = 1;
        }
    }
    if (!have) return 0;
    *total = end + length; return 1;
}
static int parse_message(const char *p, size_t n, size_t end, message_t *m) {
    span_t s = { p, end }, l, t; unsigned seen = 0;
    memset(m,0,sizeof(*m));
    if (!line(&s,&l)) return 0;
    t = token(&l);
    if (eq(t,"SIP/2.0")) {
        uint32_t code;
        m->response = 1; t = token(&l);
        if (t.n != 3 || !number(t,699,&code) || code < 100) return 0;
        m->status = code;
    } else {
        m->method = method(t); (void)token(&l); t = token(&l);
        if (!eq(t,"SIP/2.0")) return 0;
    }
    while (line(&s,&l) && l.n) {
        const char *colon = (const char *)memchr(l.p, ':', l.n);
        span_t name, v;
        if (!colon) return 0;
        name.p = l.p; name.n = (size_t)(colon-l.p); name = trim(name);
        v.p = colon+1; v.n = l.n-(size_t)(colon-l.p)-1; v = trim(v);
        if (eq(name,"Call-ID") || eq(name,"i")) {
            if ((seen&1U) || !copy(v,m->id,sizeof(m->id))) return 0; seen |= 1U;
        } else if (eq(name,"CSeq")) {
            unsigned request_method = m->method;
            if (seen&2U) return 0; seen |= 2U; t = token(&v);
            if (!number(t,0x7fffffffU,&m->cseq)) return 0;
            t = token(&v); m->method = method(t);
            if (!m->response && request_method != m->method) return 0;
        } else if (eq(name,"From") || eq(name,"f")) {
            if ((seen&4U) || !tag(v,m->from)) return 0; seen |= 4U;
        } else if (eq(name,"To") || eq(name,"t")) {
            if ((seen&8U) || !tag(v,m->to)) return 0; seen |= 8U;
        } else if (eq(name,"Content-Type") || eq(name,"c")) {
            size_t z = 0; while (z < v.n && v.p[z] != ';') z++; v.n = z;
            m->sdp = (uint8_t)eq(trim(v),"application/sdp");
        }
    }
    m->body.p = p+end; m->body.n = n-end;
    return (seen&15U) == 15U;
}
static int connection(luat_cc_uart_sip_t *c, span_t s, luat_cc_uart_sip_endpoint_t *ep) {
    span_t network = token(&s), family = token(&s), address = token(&s);
    char literal[64]; uint8_t f;
    if (!eq(network,"IN") || trim(s).n || !copy(address,literal,sizeof(literal))) return 0;
    if (eq(family,"IP4")) f = 4; else if (eq(family,"IP6")) f = 6; else return 0;
    memset(ep->address,0,sizeof(ep->address)); ep->family = f;
    return c->parse_address && c->parse_address(literal,f,ep->address);
}
static int event_list(span_t s, uint16_t *mask) {
    uint16_t bits = 0; size_t i = 0;
    s = trim(s);
    while (i < s.n) {
        size_t first = i; uint32_t a,b;
        while (i < s.n && s.p[i] >= '0' && s.p[i] <= '9') i++;
        { span_t v = { s.p+first, i-first }; if (!number(v,255,&a)) return 0; }
        b = a;
        if (i < s.n && s.p[i] == '-') {
            first = ++i; while (i < s.n && s.p[i] >= '0' && s.p[i] <= '9') i++;
            { span_t v = { s.p+first,i-first }; if (!number(v,255,&b) || b < a) return 0; }
        }
        while (a <= b && a < 16U) { bits |= (uint16_t)(1U << a); a++; }
        if (i == s.n) break;
        if (s.p[i++] != ',' || i == s.n) return 0;
    }
    *mask = bits; return bits != 0;
}
static int parse_sdp(luat_cc_uart_sip_t *c, span_t body, luat_cc_uart_sip_sdp_t *out) {
    span_t s = body,l; luat_cc_uart_sip_endpoint_t session_ep = {0}, media_ep = {0};
    uint8_t *payloads = c->scratch.payloads, *have_fmtp = c->scratch.have_fmtp, *bad_fmtp = c->scratch.bad_fmtp;
    uint16_t *fmtp = c->scratch.fmtp;
    uint8_t audio = 0, in_audio = 0, any_media = 0;
    int receiving = 1;
    memset(payloads,0,sizeof(c->scratch.payloads));
    memset(fmtp,0,sizeof(c->scratch.fmtp));
    memset(have_fmtp,0,sizeof(c->scratch.have_fmtp));
    memset(bad_fmtp,0,sizeof(c->scratch.bad_fmtp));
    memset(out,0,sizeof(*out));
    while (line(&s,&l)) {
        span_t value;
        if (!l.n) continue;
        if (l.n < 2 || l.p[1] != '=') return 0;
        value.p = l.p+2; value.n = l.n-2;
        if (l.p[0] == 'm') {
            span_t kind = token(&value), port = token(&value), profile = token(&value), pt;
            uint32_t n;
            any_media = 1; in_audio = (uint8_t)eq(kind,"audio");
            if (!in_audio) continue;
            if (audio++ || !number(port,65535,&n) || !n || !eq(profile,"RTP/AVP")) return 0;
            media_ep.port = (uint16_t)n;
            while ((pt = token(&value)).n) { if (!number(pt,127,&n)) return 0; payloads[n] = 1; }
        } else if (l.p[0] == 'c' && (!any_media || in_audio)) {
            luat_cc_uart_sip_endpoint_t *ep = any_media ? &media_ep : &session_ep;
            if (!connection(c,value,ep)) return 0;
        } else if (l.p[0] == 'a' && (!any_media || in_audio)) {
            const char *colon = (const char *)memchr(value.p,':',value.n);
            span_t name = value;
            if (!colon) {
                if (eq(value,"inactive") || eq(value,"sendonly")) receiving = 0;
                continue;
            }
            name.n = (size_t)(colon-value.p);
            value.n -= name.n+1; value.p = colon+1;
            if (in_audio && eq(name,"rtpmap")) {
                span_t pt = token(&value), encoding = token(&value), codec = encoding, clock;
                const char *slash = (const char *)memchr(encoding.p,'/',encoding.n); uint32_t n,hz;
                if (!number(pt,127,&n) || !slash || trim(value).n) return 0;
                codec.n = (size_t)(slash-codec.p);
                if (!eq(codec,"telephone-event")) continue;
                clock.p = slash+1; clock.n = encoding.n-codec.n-1;
                if (!payloads[n] || !number(clock,48000,&hz) || (hz != 8000 && hz != 16000) || out->count == 4) return 0;
                { unsigned j; for (j=0;j<out->count;j++) if (out->formats[j].payload_type == n) return 0; }
                out->formats[out->count].payload_type = (uint8_t)n;
                out->formats[out->count].clock_hz = hz;
                out->formats[out->count].events = 0xffffU; out->count++;
            } else if (in_audio && eq(name,"fmtp")) {
                span_t pt = token(&value); uint32_t n;
                if (!number(pt,127,&n)) return 0;
                /* Codec fmtp uses key=value; only telephone-event's numeric
                 * event list matters, and rtpmap may appear later in SDP. */
                if (trim(value).n && trim(value).p[0] >= '0' && trim(value).p[0] <= '9') {
                    if (have_fmtp[n] || !event_list(value,&fmtp[n])) return 0;
                    have_fmtp[n] = 1;
                } else bad_fmtp[n] = 1;
            }
        }
    }
    if (audio != 1 || !out->count || !receiving) return 0;
    if (!media_ep.family) { media_ep.family = session_ep.family; memcpy(media_ep.address,session_ep.address,16); }
    if (!media_ep.family) return 0;
    out->endpoint = media_ep;
    { unsigned i; for (i=0;i<out->count;i++) {
        unsigned pt = out->formats[i].payload_type;
        if (bad_fmtp[pt]) return 0;
        if (have_fmtp[pt]) out->formats[i].events = fmtp[pt];
    } }
    return 1;
}
static void invalidate(luat_cc_uart_sip_t *c) { c->valid = 0; }
static void error(luat_cc_uart_sip_t *c) { c->diag.errors++; invalidate(c); }
static void retire(luat_cc_uart_sip_t *c) {
    if (c->call_id[0]) { memcpy(c->retired_id,c->call_id,sizeof(c->retired_id)); c->retired = 1; }
    c->candidate = c->bound = c->valid = c->answered = 0; c->session = 0; c->call_id[0] = 0;
    c->outgoing = c->outgoing_pending = c->incoming_pending = 0;
    c->dialog_fd[0] = c->dialog_fd[1] = -1;
    c->dialog_is_tcp = 0;
    c->remote_tag[0] = c->local_tag[0] = 0;
}
static int match_tags(luat_cc_uart_sip_t *c, const message_t *m, int request_tx) {
    const char *remote = request_tx ? m->to : m->from;
    const char *local = request_tx ? m->from : m->to;
    if (!remote[0] || (c->remote_tag[0] && strcmp(remote,c->remote_tag))) return 0;
    if (c->local_tag[0] && strcmp(local,c->local_tag)) return 0;
    return 1;
}
static int commit(luat_cc_uart_sip_t *c, const luat_cc_uart_sip_sdp_t *answer) {
    const luat_cc_uart_sip_sdp_t *local = c->offer_tx ? &c->offer : answer;
    const luat_cc_uart_sip_sdp_t *remote = c->offer_tx ? answer : &c->offer;
    luat_cc_uart_sip_mapping_t next; unsigned i,j, matches = 0;
    memset(&next,0,sizeof(next)); next.local = local->endpoint; next.remote = remote->endpoint;
    for (i=0;i<local->count;i++) for (j=0;j<remote->count;j++) {
        const luat_cc_uart_sip_format_t *a = &local->formats[i], *b = &remote->formats[j];
        if (a->payload_type == b->payload_type && a->clock_hz == b->clock_hz && (a->events & b->events)) {
            /* SDP with several accepted telephone-event clocks does not reveal
             * which one the modem selected. Do not guess from list order. */
            if (++matches != 1U) return 0;
            next.payload_type = a->payload_type; next.clock_hz = a->clock_hz; next.event_mask = (uint16_t)(a->events & b->events);
        }
    }
    if (!matches) return 0;
    next.generation = c->map.generation;
    if (!c->valid || memcmp(&next,&c->map,sizeof(next))) {
        next.generation = ++c->generation; c->diag.mappings++;
    }
    c->map = next; c->valid = c->answered = 1; return 1;
}
static void process_message(luat_cc_uart_sip_t *c, int fd, int tx, int is_tcp, const char *p, size_t n, size_t end, uint32_t now) {
    message_t *m = &c->scratch.message; luat_cc_uart_sip_sdp_t *sdp = &c->scratch.sdp; int same;
    c->diag.messages++;
    if (!parse_message(p,n,end,m)) { error(c); return; }
    same = c->call_id[0] && !strcmp(m->id,c->call_id);
    if (c->bound && !same) return;
    if (!same) {
        if (m->response || m->method != M_INVITE || !m->from[0] || m->to[0] || !m->sdp) return;
        if (c->retired && !strcmp(m->id,c->retired_id)) return;
        if (c->outgoing_pending || c->incoming_pending) {
            if (tx != (c->outgoing_pending != 0)) return;
            if ((uint32_t)(now-c->candidate_ms) > LUAT_CC_UART_SIP_FRESH_MS) { retire(c); return; }
        } else if (tx) return;
        if (c->candidate && (uint32_t)(now-c->candidate_ms) <= LUAT_CC_UART_SIP_FRESH_MS) {
            c->candidate = 2; error(c); return;
        }
        if (!parse_sdp(c,m->body,sdp)) { c->diag.unsupported++; error(c); return; }
        memcpy(c->call_id,m->id,sizeof(c->call_id));
        c->remote_tag[0] = c->local_tag[0] = 0;
        memcpy(tx ? c->local_tag : c->remote_tag,m->from,sizeof(c->remote_tag));
        c->candidate = 1; c->candidate_ms = now; c->offer = *sdp;
        c->dialog_is_tcp = is_tcp != 0;
        c->dialog_fd[tx] = fd;
        c->dialog_fd[!tx] = is_tcp ? fd : -1;
        c->last_cseq[!tx] = 0; c->last_cseq[tx] = m->cseq;
        c->offer_tx = (uint8_t)tx; c->method = M_INVITE; c->cseq = m->cseq; c->valid = c->answered = 0;
        if (c->outgoing_pending || c->incoming_pending) {
            c->outgoing_pending = c->incoming_pending = 0;
            c->bound = 1; c->diag.bindings++;
        }
        return;
    }
    if (c->candidate == 2 || c->dialog_is_tcp != (is_tcp != 0) ||
        (c->dialog_fd[tx] >= 0 && fd != c->dialog_fd[tx])) return;
    /* A UDP answer may use the SDK's other socket. Only a validated answer
     * can claim that direction; requests and provisional empty replies cannot. */
    if (c->dialog_fd[tx] < 0 && (!m->response || tx == c->offer_tx)) return;
    /* An authenticated retry of the initial outgoing INVITE keeps its
     * Call-ID/local tag, raises CSeq and still has no remote To tag. */
    if (c->outgoing && !c->remote_tag[0] && !m->response && tx &&
        m->method == M_INVITE && !m->to[0] && !strcmp(m->from,c->local_tag)) {
        if (m->cseq <= c->last_cseq[1] || !m->sdp) return;
        if (!parse_sdp(c,m->body,sdp)) { c->diag.unsupported++; error(c); return; }
        c->offer = *sdp; c->offer_tx = 1; c->cseq = m->cseq; c->method = M_INVITE;
        c->last_cseq[1] = m->cseq; invalidate(c); return;
    }
    if (c->outgoing && !m->response && tx && m->method == M_CANCEL &&
        c->method == M_INVITE && m->cseq == c->cseq && !m->to[0] &&
        !strcmp(m->from,c->local_tag)) { retire(c); return; }
    if (!match_tags(c,m,m->response ? c->offer_tx : tx)) return;
    if (!m->response && (m->method == M_BYE || m->method == M_CANCEL)) { retire(c); return; }
    if (m->response) {
        if (tx == c->offer_tx || m->method != c->method || m->cseq != c->cseq) return;
        if (m->status >= 300) { invalidate(c); return; }
        if (m->status < 180 || m->status >= 300 || !m->sdp || !m->body.n) return;
        if (!m->from[0] || !m->to[0]) { error(c); return; }
        if (!parse_sdp(c,m->body,sdp) || !commit(c,sdp)) { c->diag.unsupported++; error(c); return; }
        c->dialog_fd[tx] = fd;
        if (!c->local_tag[0]) {
            const char *local = c->offer_tx ? m->from : m->to;
            if (!local[0]) { error(c); return; }
            memcpy(c->local_tag,local,strlen(local)+1);
        }
        if (!c->remote_tag[0]) {
            const char *remote = c->offer_tx ? m->to : m->from;
            memcpy(c->remote_tag,remote,strlen(remote)+1);
        }
    } else if ((m->method == M_INVITE || m->method == M_UPDATE) && m->sdp) {
        if (m->cseq <= c->last_cseq[tx]) return; /* per-direction request ordering/retransmission */
        if (!parse_sdp(c,m->body,sdp)) { c->diag.unsupported++; error(c); return; }
        c->offer = *sdp; c->offer_tx = (uint8_t)tx; c->cseq = m->cseq; c->method = (uint8_t)m->method; c->answered = 0;
        c->last_cseq[tx] = m->cseq;
        invalidate(c); /* Accept packets only for a completed new negotiation. */
    }
}
static void message(luat_cc_uart_sip_t *c, int fd, int tx, int is_tcp, const char *p, size_t n, size_t end, uint32_t now) {
    process_message(c,fd,tx,is_tcp,p,n,end,now);
    c->scratch.message.body.p = NULL; c->scratch.message.body.n = 0;
}
void luat_cc_uart_sip_init(luat_cc_uart_sip_t *c, luat_cc_uart_sip_addr_parse_fn parse_address) {
    if (c) {
        memset(c,0,sizeof(*c)); c->parse_address = parse_address;
        c->dialog_fd[0] = c->dialog_fd[1] = -1;
    }
}
static void poison(luat_cc_uart_sip_t *c, luat_cc_uart_sip_stream_t *s, int tx, int oversized) {
    s->used[tx] = 0; s->poisoned[tx] = 1;
    if (oversized) c->diag.oversize++; error(c);
}
static int drain(luat_cc_uart_sip_t *c, luat_cc_uart_sip_stream_t *s, int tx, uint32_t now) {
    size_t used = s->used[tx], end, total; char *bytes = s->bytes[tx];
    while (used >= 2 && !memcmp(bytes,"\r\n",2)) { memmove(bytes,bytes+2,used-2); used-=2; }
    s->used[tx] = (uint16_t)used;
    if (!(end = header_end(bytes,used))) return 0;
    if (!frame_size(bytes,end,&total)) { poison(c,s,tx,0); return -1; }
    if (total > LUAT_CC_UART_SIP_MESSAGE_MAX) { poison(c,s,tx,1); return -1; }
    if (used < total) return 0;
    message(c,s->fd,tx,1,bytes,total,end,now);
    memmove(bytes,bytes+total,used-total); s->used[tx] = (uint16_t)(used-total); return 1;
}
void luat_cc_uart_sip_stream(luat_cc_uart_sip_t *c, int fd, int tx, int is_tcp, const void *data, size_t length, uint32_t now) {
    unsigned i; luat_cc_uart_sip_stream_t *s = NULL; const char *bytes = (const char *)data;
    if (!c || !data || !length || fd < 0 || (tx != 0 && tx != 1)) return;
    /* Complete UDP datagrams need no stream reassembly slot. Registration
     * and subscription sockets must not occupy the bounded TCP buffers. */
    if (!is_tcp) {
        size_t end,total;
        if (length > LUAT_CC_UART_SIP_MESSAGE_MAX) { c->diag.oversize++; error(c); return; }
        end = header_end(bytes,length);
        if (!end || !frame_size(bytes,end,&total) || total != length) { error(c); return; }
        message(c,fd,tx,0,bytes,length,end,now); return;
    }
    for (i=0;i<2;i++) if (c->streams[i].occupied && c->streams[i].fd == fd) { s = &c->streams[i]; break; }
    if (!s) for (i=0;i<2;i++) if (!c->streams[i].occupied) {
        s = &c->streams[i]; memset(s,0,sizeof(*s)); s->occupied = 1; s->fd = fd; break;
    }
    if (!s) { c->diag.slots_full++; error(c); return; }
    if (s->poisoned[tx]) return;
    while (length) {
        size_t available = LUAT_CC_UART_SIP_MESSAGE_MAX-s->used[tx], take = length < available ? length : available;
        int result;
        memcpy(s->bytes[tx]+s->used[tx],bytes,take); s->used[tx] += (uint16_t)take; bytes += take; length -= take;
        do { result = drain(c,s,tx,now); } while (result > 0);
        if (result < 0) return;
        if (s->used[tx] == LUAT_CC_UART_SIP_MESSAGE_MAX) { poison(c,s,tx,1); return; }
    }
}
void luat_cc_uart_sip_close(luat_cc_uart_sip_t *c, int fd) {
    unsigned i; if (!c) return;
    for (i=0;i<2;i++) if (c->streams[i].occupied && c->streams[i].fd == fd) memset(&c->streams[i],0,sizeof(c->streams[i]));
    if (c->call_id[0] && (c->dialog_fd[0] == fd || c->dialog_fd[1] == fd)) retire(c);
}
int luat_cc_uart_sip_begin(luat_cc_uart_sip_t *c, uint64_t session, uint32_t now) {
    if (!c || !session) return 0;
    if (c->outgoing) return 0;
    if (c->bound) return c->session == session;
    if (c->incoming_pending) {
        return c->session == session &&
               (uint32_t)(now-c->candidate_ms) <= LUAT_CC_UART_SIP_FRESH_MS;
    }
    if (!c->candidate) {
        /* CC notification can precede the observer's complete INVITE.
         * Keep one bounded reservation rather than losing this call's RX. */
        c->session = session; c->incoming_pending = 1; c->candidate_ms = now;
        return 1;
    }
    /* Do not turn ambiguous or stale candidates into a different call. */
    if (c->candidate != 1 || (uint32_t)(now-c->candidate_ms) > LUAT_CC_UART_SIP_FRESH_MS) return 0;
    c->session = session; c->bound = 1; c->diag.bindings++; return 1;
}
int luat_cc_uart_sip_begin_outgoing(luat_cc_uart_sip_t *c, uint64_t session, uint32_t now) {
    if (!c || !session) return 0;
    if (c->session) return c->outgoing && c->session == session;
    retire(c);
    c->session = session; c->outgoing = c->outgoing_pending = 1; c->candidate_ms = now;
    return 1;
}
void luat_cc_uart_sip_finish(luat_cc_uart_sip_t *c, uint64_t session) {
    if (c && (c->bound || c->outgoing_pending || c->incoming_pending) && c->session == session) retire(c);
}
int luat_cc_uart_sip_mapping(const luat_cc_uart_sip_t *c, uint64_t session, luat_cc_uart_sip_mapping_t *out) {
    if (!c || !out || !session || !c->bound || c->session != session || !c->valid) return 0;
    *out = c->map; return 1;
}
