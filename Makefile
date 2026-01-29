# Targeting the latest SDK for iOS 26.2 compatibility
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics QuartzCore
# Note: MobileGestalt is a private framework; ESign usually handles this during signing
EnigmaFramework_PRIVATE_FRAMEWORKS = MobileGestalt
EnigmaFramework_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
