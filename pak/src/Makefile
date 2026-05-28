# Battery Care pak — built inside a NextUI workspace.
# Cross-compiled by the tg5040 toolchain in Docker; see the top-level Makefile.

ifeq (,$(CROSS_COMPILE))
$(error missing CROSS_COMPILE for this toolchain)
endif

PLATFORM ?= $(UNION_PLATFORM)
ifeq (,$(PLATFORM))
PLATFORM = tg5040
endif

TARGET = batterycare
CC = $(CROSS_COMPILE)gcc

INCDIR  = -I. -I../../all/common/ -I../../$(PLATFORM)/platform/ -I../../$(PLATFORM)/libmsettings
INCDIR += -I$(PREFIX)/include -I$(PREFIX_LOCAL)/include

SOURCE  = main.c settings.c settings_io.c \
          ui_fonts.c ui_utils.c \
          ../../all/common/utils.c \
          ../../all/common/api.c \
          ../../all/common/config.c \
          ../../all/common/scaler.c \
          ../../$(PLATFORM)/platform/platform.c

CFLAGS  = -O2 -fomit-frame-pointer -std=gnu99
CFLAGS += $(INCDIR) -DPLATFORM=\"$(PLATFORM)\"
CFLAGS += -DUSE_SDL2 -DUSE_GLES -DGL_GLEXT_PROTOTYPES

LDFLAGS  = -L$(PREFIX)/lib -L$(PREFIX_LOCAL)/lib -L$(PREFIX)/lib/$(CROSS_TRIPLE)
LDFLAGS += -L../../$(PLATFORM)/libmsettings
LDFLAGS += $(shell pkg-config --libs sdl2 glesv2 2>/dev/null || echo "-lSDL2 -lGLESv2")
LDFLAGS += -lSDL2_image -lSDL2_ttf
LDFLAGS += -lmsettings -lsamplerate -lzip -lasound
LDFLAGS += -lm -lpthread -ldl -lz

PRODUCT = ../bin/$(PLATFORM)/$(TARGET).elf

all:
	@mkdir -p ../bin/$(PLATFORM)
	$(CC) $(SOURCE) -o $(PRODUCT) $(CFLAGS) $(LDFLAGS)

clean:
	rm -f ../bin/$(PLATFORM)/$(TARGET).elf
