# DroneControlQt.pro
#
# Qt 6 (6.5+ / 6.11) port of the DroneControl iOS app - MAVLink v2 ground
# control station for ArduPilot vehicles. Builds for desktop (Windows, Linux,
# macOS) and Android with qmake.

QT += core gui network quick qml quickcontrols2

# Map tab uses Qt Location (OSM plugin). Optional so the project still builds
# on Qt installs without the Location module.
qtHaveModule(location) {
    QT += positioning location
    DEFINES += HAVE_QT_LOCATION
    message("Qt Location found - map tab enabled")
} else {
    message("Qt Location not found - map tab disabled")
}

TARGET = DroneControl
TEMPLATE = app
CONFIG += c++17

VERSION = 1.0.0
DEFINES += APP_VERSION=\\\"$$VERSION\\\"
DEFINES += QT_DEPRECATED_WARNINGS

INCLUDEPATH += $$PWD/src $$PWD/mavlink

# MAVLink headers are C code with packed structs; silence the warnings they trigger
gcc|clang {
    QMAKE_CXXFLAGS += -Wno-address-of-packed-member -Wno-cast-align
}

SOURCES += \
    src/main.cpp \
    src/UdpConnection.cpp \
    src/MavlinkManager.cpp \
    src/ParameterModel.cpp \
    src/MessagesModel.cpp \
    src/SettingsManager.cpp \
    src/GamepadManager.cpp \
    src/DefaultParameters.cpp

HEADERS += \
    src/UdpConnection.h \
    src/MavlinkManager.h \
    src/ParameterModel.h \
    src/MessagesModel.h \
    src/SettingsManager.h \
    src/GamepadManager.h \
    src/DefaultParameters.h

RESOURCES += resources.qrc

# Make the QML files show up in Qt Creator
DISTFILES += \
    qml/Main.qml \
    qml/Theme.qml \
    qml/components/*.qml \
    qml/pages/*.qml \
    android/AndroidManifest.xml \
    README.md

# --- Desktop ---------------------------------------------------------------
win32 {
    RC_ICONS = icons/app_icon.ico
    # XInput is loaded at runtime (LoadLibrary) - no import library needed
}

macx {
    ICON = icons/app_icon.icns
    QMAKE_INFO_PLIST_EXTRA = NSLocalNetworkUsageDescription
}

# --- Android ---------------------------------------------------------------
android {
    ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
    ANDROID_MIN_SDK_VERSION = 28
    ANDROID_TARGET_SDK_VERSION = 35
    ANDROID_VERSION_NAME = $$VERSION
    ANDROID_VERSION_CODE = 1
    # arm64-v8a is the default target; add armeabi-v7a in Qt Creator if needed
}

# Default rules for deployment
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target
