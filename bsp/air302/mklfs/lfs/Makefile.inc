LFS_DIR        := $(TOP)/PLAT/middleware/thirdparty/littlefs

CFLAGS_INC     +=  -I $(LFS_DIR) \
                   -I $(LFS_DIR)/port \
              

LFS_SRC_DIRS += $(LFS_DIR) \
                $(LFS_DIR)/port
LFS_EXCLUDE_FILES :=
LFS_CSRC = $(foreach dir, $(LFS_SRC_DIRS), $(wildcard $(dir)/*.c))
LFS_CFILES = $(filter-out $(LFS_EXCLUDE_FILES), $(LFS_CSRC))
LFS_COBJSTEMP := $(patsubst %.c, %.o, $(LFS_CFILES))
LFS_COBJSTEMP :=$(subst $(LFS_DIR),PLAT/middleware/thirdparty/littlefs,$(LFS_COBJSTEMP))
LFS_COBJS := $(addprefix $(BUILDDIR)/, $(LFS_COBJSTEMP))

CFLAGS += -DLFS_NAME_MAX=63 -DLFS_DEBUG_TRACE -DLFS_THREAD_SAFE_MUTEX

-include $(LFS_COBJS:.o=.d)


ifeq ($(TOOLCHAIN),GCC)

CFLAGS_INC += -I $(TOP)/PLAT/os/freertos/portable/gcc

lib-y += liblfs.a

$(BUILDDIR)/lib/liblfs.a: $(LFS_COBJS)
	@mkdir -p $(dir $@)
	$(ECHO) AR $@
	$(Q)$(AR) -cr $@ $^

endif

ifeq ($(TOOLCHAIN),ARMCC)

CFLAGS_INC += -I $(TOP)/PLAT/os/freertos/portable/keil


lib-y += liblfs.lib

$(BUILDDIR)/lib/liblfs.lib: $(LFS_COBJS)
	@mkdir -p $(dir $@)
	$(ECHO) AR $@
	$(Q)$(AR) $(ARFLAGS) $@ $^

endif
