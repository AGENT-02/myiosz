TARGET := iphone:clang:latest:26.0
ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME=rootless
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PoolAutoPlay

PoolAutoPlay_FILES = Tweak.x
PoolAutoPlay_FRAMEWORKS = UIKit CoreGraphics Foundation
PoolAutoPlay_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
