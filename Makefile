TARGET := iphone:clang:latest:26.0
ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics QuartzCore
# Note: No PRIVATE_FRAMEWORKS needed because we use dlsym()
EnigmaFramework_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
