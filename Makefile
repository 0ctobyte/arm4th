AS := arm-none-eabi-gcc 
CC := arm-none-eabi-gcc 
LD := arm-none-eabi-ld
OBJCOPY := arm-none-eabi-objcopy

PROGRAM := arm4th

# Enable building for the BeagleBoneBlack
BBB ?= 0

C_SRCS := $(wildcard *.c)
S_SRCS := $(wildcard *.s)

OBJS := $(patsubst %.s,%.o,$(S_SRCS))
OBJS += $(patsubst %.c,%.o,$(C_SRCS))

INCLUDE := -Iinclude
LSCRIPT := linker.ld

BASEFLAGS := -g -mcpu=cortex-a15 -mfpu=neon -mfloat-abi=hard 
WARNFLAGS := -Wall -Werror -Wno-missing-prototypes -Wno-unused-macros -Wno-bad-function-cast -Wno-sign-conversion
CFLAGS := -std=c99 -fno-builtin -ffreestanding -fomit-frame-pointer $(DEFINES) $(BASEFLAGS) $(WARNFLAGS) $(INCLUDE)
LDFLAGS := -nostdlib -nostdinc -nodefaultlibs -nostartfiles -T $(LSCRIPT)
ASFLAGS := $(BASEFLAGS) $(WARNFLAGS) -x assembler-with-cpp 
OCFLAGS := --target elf32-littlearm --set-section-flags .bss=contents,alloc,load -O binary

ifeq ($(BBB), 1)
	CFLAGS += -DBBB=1
	ASFLAGS += -DBBB=1
endif

$(PROGRAM).bin: $(PROGRAM).elf
	$(OBJCOPY) $(OCFLAGS) $< $@

$(PROGRAM).elf: $(OBJS) linker.ld
	$(LD) $(LDFLAGS) $(OBJS) -o $@

%.o: %.s Makefile
	$(AS) $(ASFLAGS) -c $< -o $@

%.o: %.c Makefile
	$(CC) $(CFLAGS) -c $< -o $@

.PHONY: clean
clean:
	$(RM) -f $(OBJS) $(PROGRAM).elf $(PROGRAM).bin

