APP_NAME := ActiveLeft
BUILD_DIR := build
OBJC_SOURCE := Sources/ActiveLeftObjC/main.m
OBJC_BINARY := $(BUILD_DIR)/$(APP_NAME)
MACOSX_MIN := 13.0

.PHONY: activeleft-bin clean

activeleft-bin: $(OBJC_BINARY)

$(OBJC_BINARY): $(OBJC_SOURCE)
	mkdir -p $(BUILD_DIR)
	clang -fobjc-arc -O2 -mmacosx-version-min=$(MACOSX_MIN) -framework Cocoa $(OBJC_SOURCE) -o $(OBJC_BINARY)

clean:
	rm -rf $(BUILD_DIR) .build
