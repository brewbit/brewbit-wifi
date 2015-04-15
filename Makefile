# tnx to mamalala
# Changelog
# Changed the variables to include the header file directory
# Added global var for the XTENSA tool root
#
# This make file still needs some work.
#
#
# Output directors to store intermediate compiled files
# relative to the project directory
BUILD_BASE	= build

# base directory of the ESP8266 SDK package
SDK_BASE	?= sdk

#Esptool.py path and port
ESPTOOL		?= python $(SDK_BASE)/bin/esptool.py
ESPPORT		?= /dev/tty.usbserial-DA01G13Y

# name for the target project
TARGET		= brewbit-wifi

# which modules (subdirectories) of the project to include in compiling
MODULES		    = src
EXTRA_INCDIR    = include

# libraries used in this project, mainly provided by the SDK
LIBS		= c gcc hal pp phy net80211 lwip wpa main

# compiler flags using during compilation of source files
CFLAGS		= -Os -g -O2 -Wpointer-arith -Wundef -Werror -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals  -D__ets__ -DICACHE_FLASH

# linker flags used to generate the main object file
LDFLAGS		= -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static

# linker script used for the above linkier step
LD_SCRIPT	= eagle.app.v6.ld

# various paths from the SDK used in this project
SDK_LIBDIR	= lib
SDK_LDDIR	= ld
SDK_INCDIR	= include include/json

# select which tools to use as compiler, librarian and linker
CC = $(SDK_BASE)/bin/xtensa-lx106-elf-gcc
AR = $(SDK_BASE)/bin/xtensa-lx106-elf-ar
LD = $(SDK_BASE)/bin/xtensa-lx106-elf-gcc

UNAME = $(shell uname)

####
#### no user configurable options below here
####
SRC_DIR		:= $(MODULES)
BUILD_DIR	:= $(addprefix $(BUILD_BASE)/,$(MODULES))

SDK_LIBDIR	:= $(addprefix $(SDK_BASE)/,$(SDK_LIBDIR))
SDK_INCDIR	:= $(addprefix -I$(SDK_BASE)/,$(SDK_INCDIR))

SRC		:= $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.c))
OBJ		:= $(patsubst %.c,$(BUILD_BASE)/%.o,$(SRC))
LIBS		:= $(addprefix -l,$(LIBS))
APP_AR		:= $(addprefix $(BUILD_BASE)/,$(TARGET)_app.a)
TARGET_OUT	:= $(addprefix $(BUILD_BASE)/,$(TARGET).elf)

LD_SCRIPT	:= $(addprefix -T$(SDK_BASE)/xtensa-lx106-elf/sysroot/usr/lib/,$(LD_SCRIPT))

INCDIR	:= $(addprefix -I,$(SRC_DIR))
EXTRA_INCDIR	:= $(addprefix -I,$(EXTRA_INCDIR))
MODULE_INCDIR	:= $(addsuffix /include,$(INCDIR))

FLASH_IMAGE_1 = $(TARGET_OUT)-0x00000.bin
FLASH_IMAGE_2 = $(TARGET_OUT)-0x40000.bin

V ?= $(VERBOSE)
ifeq ("$(V)","1")
Q :=
vecho := @true
else
Q := @
vecho := @echo
endif

vpath %.c $(SRC_DIR)

define compile-objects
$1:
	mkdir -p $1

$1/%.o: %.c
	$(vecho) "CC $$<"
	
	$(Q) $(CC) $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) $(CFLAGS)  -c $$< -o $$@
endef

.PHONY: all flash flash_images clean

all: build sdk $(TARGET_OUT) flash_images

build:
	mkdir build

ifeq ($(UNAME), Darwin)
build/eos.sparseimage: build
	hdiutil create build/eos -volname eos -type SPARSE -size 8g -fs HFSX

build/eos: build/eos.sparseimage
	hdiutil attach build/eos.sparseimage -mountpoint build/eos
endif

ifeq ($(UNAME), Linux)
build/eos: build
	mkdir build/eos
endif

build/eos/esp-open-sdk: build/eos
	git clone https://github.com/pfalcon/esp-open-sdk.git build/eos/esp-open-sdk	

build/eos/esp-open-sdk/xtensa-lx106-elf: build/eos/esp-open-sdk
	cd build/eos/esp-open-sdk && make STANDALONE=y

sdk: build/eos/esp-open-sdk/xtensa-lx106-elf
	cp -r build/eos/esp-open-sdk/xtensa-lx106-elf sdk

flash_images: $(TARGET_OUT)
	$(vecho) "FW $@"
	$(Q) $(ESPTOOL) elf2image $(TARGET_OUT)

$(TARGET_OUT): $(APP_AR)
	$(vecho) "LD $@"
	$(Q) $(LD) -L$(SDK_LIBDIR) $(LD_SCRIPT) $(LDFLAGS) -Wl,--start-group $(LIBS) $(APP_AR) -Wl,--end-group -o $@

$(APP_AR): $(OBJ)
	$(vecho) "AR $@"
	$(Q) $(AR) cru $@ $^

flash: sdk flash_images
	-$(ESPTOOL) --port $(ESPPORT) write_flash 0x00000 $(FLASH_IMAGE_1) 0x40000 $(FLASH_IMAGE_2)

clean:
	diskutil umount force build/eos
	$(Q) rm -f $(APP_AR)
	$(Q) rm -f $(TARGET_OUT)
	$(Q) rm -rf $(BUILD_DIR)
	$(Q) rm -rf $(BUILD_BASE)


	$(Q) rm -f $(FW_FILE_1)
	$(Q) rm -f $(FW_FILE_2)
	$(Q) rm -rf build

$(foreach bdir,$(BUILD_DIR),$(eval $(call compile-objects,$(bdir))))
