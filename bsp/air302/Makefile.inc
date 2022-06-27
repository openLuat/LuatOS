LUATOS_DIR      := $(LUATOS_SRC)
CFLAGS_INC    +=  -I $(LUATOS_DIR)/bsp/air302/include \
				  -I $(LUATOS_DIR)/lua/include \
                  -I $(LUATOS_DIR)/luat/include \
				  -I $(LUATOS_DIR)/components/u8g2 \
				  -I $(LUATOS_DIR)/components/minmea \
				  -I $(LUATOS_DIR)/components/eink \
				  -I $(LUATOS_DIR)/components/fonts \
				  -I $(LUATOS_DIR)/components/epaper \
				  -I $(LUATOS_DIR)/components/qrcode \
				  -I $(LUATOS_DIR)/components/tjpgd \
				  -I $(LUATOS_DIR)/components/fatfs \
				  -I $(LUATOS_DIR)/components/lfs \
				  -I $(LUATOS_DIR)/components/lcd \
				  -I $(LUATOS_DIR)/components/fal/inc \
				  -I $(LUATOS_DIR)/components/flashdb/inc \
				  -I $(LUATOS_DIR)/components/sfd \
				  -I $(LUATOS_DIR)/components/shell \
				  -I $(LUATOS_DIR)/components/cmux \
				  -I $(LUATOS_DIR)/components/ymodem \



LUATOS_SRC_DIRS += $(LUATOS_DIR)/lua/src \
					$(LUATOS_DIR)/luat/modules \
					$(LUATOS_DIR)/luat/vfs \
					$(LUATOS_DIR)/luat/weak \
					$(LUATOS_DIR)/components/lua-cjson \
					$(LUATOS_DIR)/components/u8g2 \
					$(LUATOS_DIR)/components/minmea \
				    $(LUATOS_DIR)/components/eink \
				    $(LUATOS_DIR)/components/epaper \
				    $(LUATOS_DIR)/components/fonts \
				    $(LUATOS_DIR)/components/qrcode \
					$(LUATOS_DIR)/components/tjpgd \
				    $(LUATOS_DIR)/components/fatfs \
				    $(LUATOS_DIR)/components/lfs \
					$(LUATOS_DIR)/components/lcd \
				    $(LUATOS_DIR)/components/fal/src \
				    $(LUATOS_DIR)/components/flashdb/src \
				    $(LUATOS_DIR)/components/sfd \
					$(LUATOS_DIR)/components/shell \
					$(LUATOS_DIR)/components/cmux \
					$(LUATOS_DIR)/components/ymodem \
					$(LUATOS_DIR)/bsp/air302/src 


LUATOS_CSRC = $(foreach dir, $(LUATOS_SRC_DIRS), $(wildcard $(dir)/*.c))
LUATOS_CFILES = $(LUATOS_CSRC)
LUATOS_COBJSTEMP := $(patsubst %.c, %.o, $(LUATOS_CFILES))
LUATOS_COBJSTEMP :=$(subst $(LUATOS_DIR),LuatOS,$(LUATOS_COBJSTEMP))
LUATOS_COBJS := $(addprefix $(BUILDDIR)/, $(LUATOS_COBJSTEMP))

-include $(LUATOS_COBJS:.o=.d)

CFLAGS += --c99 -DWITH_POSIX -DAIR302

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
