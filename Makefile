TARGET := iphone:clang:latest:26.0
ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x
# CRITICAL: Added AudioToolbox and CoreAudio
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics AudioToolbox CoreAudio

EnigmaFramework_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
