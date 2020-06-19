LUATOS_DIR      := $(LUATOS_SRC)
CFLAGS_INC    +=  -I $(LUATOS_DIR)/lua/include \
                  -I $(LUATOS_DIR)/luat/include \
				  -I $(LUATOS_DIR)/luat/packages/vsprintf \
				  -I $(LUATOS_DIR)/luat/packages/u8g2 \
				  -I $(LUATOS_DIR)/luat/packages/fatfs \


LUATOS_SRC_DIRS += $(LUATOS_DIR)/lua/src \
					$(LUATOS_DIR)/luat/freertos \
					$(LUATOS_DIR)/luat/modules \
					$(LUATOS_DIR)/luat/packages/vsprintf \
					$(LUATOS_DIR)/luat/packages/lua-cjson \
					$(LUATOS_DIR)/luat/packages/u8g2 \
					$(LUATOS_DIR)/luat/packages/fatfs \
					$(LUATOS_DIR)/luat/air302 



LUATOS_CSRC = $(foreach dir, $(LUATOS_SRC_DIRS), $(wildcard $(dir)/*.c))
LUATOS_CFILES = $(LUATOS_CSRC)
LUATOS_COBJSTEMP := $(patsubst %.c, %.o, $(LUATOS_CFILES))
LUATOS_COBJSTEMP :=$(subst $(LUATOS_DIR),LuatOS,$(LUATOS_COBJSTEMP))
LUATOS_COBJS := $(addprefix $(BUILDDIR)/, $(LUATOS_COBJSTEMP))

-include $(LUATOS_COBJS:.o=.d)

CFLAGS += -DWITH_POSIX

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
