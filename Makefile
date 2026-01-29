# Target iOS 26.0
TARGET := iphone:clang:latest:26.0
ARCHS = arm64 arm64e

# Jailed compatibility
export THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics QuartzCore
# REMOVED: EnigmaFramework_PRIVATE_FRAMEWORKS = MobileGestalt 
# ^ This line was causing the error. We will handle it manually in code.

EnigmaFramework_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
