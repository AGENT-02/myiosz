TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x EnigmaMenu.mm
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics QuartzCore
EnigmaFramework_PRIVATE_FRAMEWORKS = MobileGestalt
EnigmaFramework_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
