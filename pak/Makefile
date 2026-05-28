# Battery Care pak top-level orchestrator.
# Cross-compiles batterycare.elf inside Docker using NextUI's workspace + the
# tg5040 toolchain, then assembles build/Battery Care.pak/.

PLATFORM    ?= tg5040
TG5040_IMG  := ghcr.io/loveretro/tg5040-toolchain:latest

NEXTUI_DIR  := ext/NextUI
PAK_WS      := $(NEXTUI_DIR)/workspace/batterycare
PAK_NAME    := Battery Care.pak
PAK_DIR     := build/$(PAK_NAME)
# GitHub rewrites spaces in release asset names to dots; match that so the
# uploaded artifact name equals pak.json's release_filename (Pak Store check).
RELEASE_ZIP := Battery.Care.pak.zip

.PHONY: all ext tg5040 pak pakz clean help

all: pak

# Clone NextUI on demand (gitignored, single shallow clone).
ext:
	@if [ ! -d $(NEXTUI_DIR) ]; then \
		echo "cloning NextUI into $(NEXTUI_DIR)..."; \
		git clone --depth 1 https://github.com/LoveRetro/NextUI.git $(NEXTUI_DIR); \
	fi
	@mkdir -p $(PAK_WS)/src $(PAK_WS)/res
	@cp -an src/. $(PAK_WS)/src/ 2>/dev/null || true
	@cp -an res/. $(PAK_WS)/res/ 2>/dev/null || true

# Stage our src/ and res/ into the workspace, then build libmsettings + the elf.
tg5040: ext
	cp -a src/. $(PAK_WS)/src/
	cp -a res/. $(PAK_WS)/res/
	docker run --rm \
		-v "$(CURDIR)/$(NEXTUI_DIR)":/workspace \
		-w /workspace $(TG5040_IMG) \
		/bin/bash -c "set -e; \
			cd workspace/tg5040/libmsettings && make >/dev/null && \
			cp libmsettings.so /workspace/workspace/batterycare/ && \
			cd ../../batterycare/src && make"

# Assemble installable .pak/ directory.
pak: tg5040
	rm -rf "$(PAK_DIR)"
	mkdir -p "$(PAK_DIR)/bin/$(PLATFORM)" "$(PAK_DIR)/lib/$(PLATFORM)" "$(PAK_DIR)/res" "$(PAK_DIR)/daemon" "$(PAK_DIR)/hooks"
	cp $(PAK_WS)/bin/$(PLATFORM)/batterycare.elf "$(PAK_DIR)/bin/$(PLATFORM)/"
	cp $(PAK_WS)/libmsettings.so                 "$(PAK_DIR)/lib/$(PLATFORM)/"
	cp -a $(PAK_WS)/res/.                        "$(PAK_DIR)/res/"
	cp launch.sh                                 "$(PAK_DIR)/launch.sh"
	cp ../pak.json                               "$(PAK_DIR)/pak.json"
	cp hook-handler.sh                           "$(PAK_DIR)/hook-handler.sh"
	cp installer.sh                              "$(PAK_DIR)/installer.sh"
	cp daemon/battery-care-daemon.sh             "$(PAK_DIR)/daemon/"
	cp hooks/boot.sh                             "$(PAK_DIR)/hooks/"
	chmod +x "$(PAK_DIR)/launch.sh" \
	         "$(PAK_DIR)/hook-handler.sh" \
	         "$(PAK_DIR)/installer.sh" \
	         "$(PAK_DIR)/daemon/battery-care-daemon.sh" \
	         "$(PAK_DIR)/hooks/boot.sh" \
	         "$(PAK_DIR)/bin/$(PLATFORM)/batterycare.elf"
	@echo "built $(PAK_DIR)/ — copy to SD_ROOT/Tools/$(PLATFORM)/"

pakz: pak
	cd build && rm -f "$(RELEASE_ZIP)" && \
		python3 -c "import zipfile,os; \
z=zipfile.ZipFile('$(RELEASE_ZIP)','w',zipfile.ZIP_DEFLATED); \
[z.write(os.path.join(r,f), os.path.relpath(os.path.join(r,f),'.')) for r,_,fs in os.walk('$(PAK_NAME)') for f in fs]; \
z.close()"
	@echo "built build/$(RELEASE_ZIP)"

# Push the assembled pak to the device via adb (device must be in adb mode).
push: pak
	adb shell "mkdir -p '/mnt/SDCARD/Tools/$(PLATFORM)/$(PAK_NAME)'"
	adb push "$(PAK_DIR)/." "/mnt/SDCARD/Tools/$(PLATFORM)/$(PAK_NAME)/"
	@echo "pushed to /mnt/SDCARD/Tools/$(PLATFORM)/$(PAK_NAME)/"

clean:
	rm -rf build
	-rm -f $(PAK_WS)/bin/$(PLATFORM)/batterycare.elf $(PAK_WS)/libmsettings.so

help:
	@echo "Targets:"
	@echo "  make ext       Clone NextUI source if missing"
	@echo "  make tg5040    Build batterycare.elf + libmsettings.so inside Docker"
	@echo "  make pak       Build + assemble build/$(PAK_NAME)/"
	@echo "  make pakz      Build + zip"
	@echo "  make push      Build + push to device via adb"
	@echo "  make clean     Remove build artifacts"
