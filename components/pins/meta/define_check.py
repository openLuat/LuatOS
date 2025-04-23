#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os, sys, json, logging

logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(filename)s[line:%(lineno)d] - %(levelname)s: %(message)s')

def sort_by_type(data):
    slist = {}
    for item in data :
        tmp = str(item).split("_")
        tp = None
        stp = None
        
        if item == "VBUS" or item == "USB_BOOT" or item == "PWR_KEY" or item == "USIM_DET" :
            tp = item
            stp = ""
        elif len(tmp) == 2 :
            tp = tmp[0]
            stp = tmp[1]
        elif tmp[0].startswith("GPIO") :
            tp = "GPIO"
            stp = tmp[0][4:]
        elif tmp[0].startswith("PWM") :
            tp = "PWM"
            stp = tmp[0][3:]
        elif tmp[0].startswith("WAKEUP") :
            tp = "WAKEUP"
            stp = tmp[0][6:]
        else :
            tp = tmp[0]
            stp = ""
        if tp not in slist :
            slist[tp] = []
        slist[tp].append(stp)
    return slist

def main():
    path = sys.argv[1]
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    # 首先, 管脚号是否有重复
    pin_list = set()
    paddr_list = set()
    alt_list = set()
    alt_dft_list = set()
    for item in data["pins"] :
        pin = item[0]
        paddr = item[1]
        alt = item[2]

        # 管脚物理编号,是否有重复
        if pin in pin_list :
            logging.error("pin %s is duplicate" % pin)
        pin_list.add(pin)

        # paddr 是否有重复
        if paddr in paddr_list and paddr != 0 :
            logging.error("paddr %s is duplicate at pin %d" % (paddr, pin))
        paddr_list.add(paddr)

        # 遍历全部alt
        self_alts = set()
        for altitem in item[3] :
            if "" == altitem :
                continue
            alt_list.add(altitem)
            self_alts.add(altitem)
        # 默认alt是否在self_alts中, 需要排除全是""的alt
        if len(self_alts) > 0 and alt not in self_alts:
            logging.error("alt %s is not in self alt list, pin %d" % (alt, pin))

        # 默认alt是否有重复
        if alt in alt_dft_list :
            logging.error("alt %s is duplicate" % alt)
        alt_dft_list.add(alt)

    alt_list_sorted = sorted(list(alt_list))
    # for alt in alt_list_sorted:
    #     logging.debug("alt %s" % alt)
    slist = sort_by_type(alt_list_sorted)
    for tp in slist :
        slist[tp] = sorted(slist[tp])
        logging.debug("alt %s : %s" % (tp, ",".join(slist[tp])))

    # 打印默认alt功能分类
    
    slist = sort_by_type(alt_dft_list)
    for tp in slist :
        slist[tp] = sorted(slist[tp])
        logging.debug("dft alt %s : %s" % (tp, ",".join(slist[tp])))


if __name__ == '__main__':
    main()
