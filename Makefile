# Targeting iOS 26.0 as the minimum deployment version
# Syntax: iphone:clang:<sdk_version>:<deployment_version>
TARGET := iphone:clang:latest:26.2
ARCHS = arm64 arm64e

# Jailed/Rootless compatibility for ESign
export THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics QuartzCore
# We link MobileGestalt weakly to prevent crashes in jailed mode
EnigmaFramework_PRIVATE_FRAMEWORKS = MobileGestalt
EnigmaFramework_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
