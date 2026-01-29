# Targeting iOS 26.0 as the minimum deployment version
# Syntax: iphone:clang:<sdk_version>:<deployment_version>
TARGET := iphone:clang:latest:26.2
ARCHS = arm64 arm64e

# Jailed/Rootless compatibility
export THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EnigmaFramework
EnigmaFramework_FILES = Tweak.x
EnigmaFramework_FRAMEWORKS = UIKit CoreGraphics QuartzCore
# Weak link to prevent crashes
EnigmaFramework_PRIVATE_FRAMEWORKS = MobileGestalt

# FIX: Disable errors for deprecated code and enforce Objective-C++
EnigmaFramework_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error -Wno-unused-variable

include $(THEOS_MAKE_PATH)/tweak.mk
