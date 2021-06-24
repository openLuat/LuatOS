LUATOS_DIR      := $(LUATOS_SRC)
CFLAGS_INC    +=  -I $(LUATOS_DIR)/bsp/air302/include \
				  -I $(LUATOS_DIR)/lua/include \
                  -I $(LUATOS_DIR)/luat/include \
				  -I $(LUATOS_DIR)/luat/packages/u8g2 \
				  -I $(LUATOS_DIR)/luat/packages/minmea \
				  -I $(LUATOS_DIR)/luat/packages/eink \
				  -I $(LUATOS_DIR)/luat/packages/fonts \
				  -I $(LUATOS_DIR)/luat/packages/epaper \
				  -I $(LUATOS_DIR)/luat/packages/qrcode \
				  -I $(LUATOS_DIR)/luat/packages/fatfs \
				  -I $(LUATOS_DIR)/luat/packages/lfs \
				  -I $(LUATOS_DIR)/components/lcd \



LUATOS_SRC_DIRS += $(LUATOS_DIR)/lua/src \
					$(LUATOS_DIR)/luat/modules \
					$(LUATOS_DIR)/luat/vfs \
					$(LUATOS_DIR)/luat/packages/lua-cjson \
					$(LUATOS_DIR)/luat/packages/u8g2 \
					$(LUATOS_DIR)/luat/packages/minmea \
				    $(LUATOS_DIR)/luat/packages/eink \
				    $(LUATOS_DIR)/luat/packages/epaper \
				    $(LUATOS_DIR)/luat/packages/fonts \
				    $(LUATOS_DIR)/luat/packages/qrcode \
				    $(LUATOS_DIR)/luat/packages/fatfs \
				    $(LUATOS_DIR)/luat/packages/lfs \
					$(LUATOS_DIR)/components/lcd \
					$(LUATOS_DIR)/bsp/air302/src 


LUATOS_CSRC = $(foreach dir, $(LUATOS_SRC_DIRS), $(wildcard $(dir)/*.c))
LUATOS_CFILES = $(LUATOS_CSRC)
LUATOS_COBJSTEMP := $(patsubst %.c, %.o, $(LUATOS_CFILES))
LUATOS_COBJSTEMP :=$(subst $(LUATOS_DIR),LuatOS,$(LUATOS_COBJSTEMP))
LUATOS_COBJS := $(addprefix $(BUILDDIR)/, $(LUATOS_COBJSTEMP))

-include $(LUATOS_COBJS:.o=.d)

CFLAGS += -DWITH_POSIX -DAIR302

ifeq ($(USE_CHINESE_WQY12_FONT), y)
CFLAGS += -DUSE_CHINESE_WQY12_FONT 
endif

ifeq ($(TOOLCHAIN),GCC)

CFLAGS_INC += -I $(TOP)/PLAT/os/freertos/portable/gcc
CFLAGS_INC += -I $(GCCLIB_PATH)/arm-none-eabi/include

lib-y += libluatos.a

$(BUILDDIR)/lib/libluatos.a: $(LUATOS_COBJS)
	@mkdir -p $(dir $@)
	$(ECHO) AR $@
	$(Q)$(AR) -cr $@ $^

endif

ifeq ($(TOOLCHAIN),ARMCC)

CFLAGS_INC += -I $(TOP)/PLAT/os/freertos/portable/keil

lib-y += libluatos.lib

$(BUILDDIR)/lib/libluatos.lib: $(LUATOS_COBJS)
	@mkdir -p $(dir $@)
	$(ECHO) AR $@
	$(Q)$(AR) $(ARFLAGS) $@ $^

endif
