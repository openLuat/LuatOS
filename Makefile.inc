LUATOS_DIR      := $(LUATOS_SRC)
CFLAGS_INC    +=  -I $(LUATOS_DIR)/lua/include \
                  -I $(LUATOS_DIR)/luat/include

LUATOS_SRC_DIRS += $(LUATOS_DIR)/lua/src \
					$(LUATOS_DIR)/luat/modules


LUATOS_EXCLUDE_FILES := $(LUATOS_DIR)/luat/modules/luat_lib_socket.c \

LUATOS_CSRC = $(foreach dir, $(LUATOS_SRC_DIRS), $(wildcard $(dir)/*.c))
LUATOS_CFILES = $(filter-out $(LUATOS_EXCLUDE_FILES), $(LUATOS_CSRC))
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
