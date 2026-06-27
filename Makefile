TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YallaPro

YallaPro_FILES = Tweak.m
YallaPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
YallaPro_FRAMEWORKS = UIKit CoreGraphics QuartzCore
YallaPro_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 YallaLite" || true
