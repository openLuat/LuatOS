#ifndef LUAT_PCAP_H
#define LUAT_PCAP_H

typedef void 	(*luat_pcap_output)(void *arg, const void *data, size_t len);

int luat_pcap_init(luat_pcap_output output, void *arg);
int luat_pcap_write_head(void);
int luat_pcap_write_macpkg(const void *data, size_t len);

#endif
