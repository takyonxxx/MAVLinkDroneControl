// SettingsManager.cpp - DroneControlQt

#include "SettingsManager.h"

static const char *KEY_HOST = "connectionHost";
static const char *KEY_PORT = "connectionPort";
static const char *KEY_DEADZONE = "gamepadDeadzone";
static const char *KEY_HOLD = "gamepadHoldThrottle";
static const char *KEY_THR_SPEED = "throttleSpeed";

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("Maren"), QStringLiteral("DroneControl"))
{
    m_host = m_settings.value(KEY_HOST, QStringLiteral("192.168.4.1")).toString();
    m_port = m_settings.value(KEY_PORT, QStringLiteral("14550")).toString();
    const float dz = m_settings.value(KEY_DEADZONE, 0.0f).toFloat();
    m_deadzone = dz > 0 ? dz : 0.1f;
    m_holdThrottle = m_settings.value(KEY_HOLD, true).toBool();
    const float ts = m_settings.value(KEY_THR_SPEED, 0.0f).toFloat();
    m_throttleSpeed = ts > 0 ? ts : 0.010f;
}

void SettingsManager::setConnectionHost(const QString &v)
{
    if (m_host == v)
        return;
    m_host = v;
    m_settings.setValue(KEY_HOST, v);
    emit connectionHostChanged();
}

void SettingsManager::setConnectionPort(const QString &v)
{
    if (m_port == v)
        return;
    m_port = v;
    m_settings.setValue(KEY_PORT, v);
    emit connectionPortChanged();
}

void SettingsManager::setGamepadDeadzone(float v)
{
    if (qFuzzyCompare(m_deadzone, v))
        return;
    m_deadzone = v;
    m_settings.setValue(KEY_DEADZONE, v);
    emit gamepadDeadzoneChanged();
}

void SettingsManager::setGamepadHoldThrottle(bool v)
{
    if (m_holdThrottle == v)
        return;
    m_holdThrottle = v;
    m_settings.setValue(KEY_HOLD, v);
    emit gamepadHoldThrottleChanged();
}

void SettingsManager::setThrottleSpeed(float v)
{
    if (qFuzzyCompare(m_throttleSpeed, v))
        return;
    m_throttleSpeed = v;
    m_settings.setValue(KEY_THR_SPEED, v);
    emit throttleSpeedChanged();
}

void SettingsManager::resetToDefaults()
{
    setConnectionHost(QStringLiteral("192.168.4.1"));
    setConnectionPort(QStringLiteral("14550"));
    setGamepadDeadzone(0.1f);
    setGamepadHoldThrottle(true);
    setThrottleSpeed(0.010f);
}

void SettingsManager::clearAllSettings()
{
    m_settings.remove(KEY_HOST);
    m_settings.remove(KEY_PORT);
    m_settings.remove(KEY_DEADZONE);
    m_settings.remove(KEY_HOLD);
    m_settings.remove(KEY_THR_SPEED);
    resetToDefaults();
}
