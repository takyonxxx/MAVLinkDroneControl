// SettingsManager.h - DroneControlQt
// Persistent app settings (port of SettingsManager.swift) backed by QSettings.

#pragma once

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString connectionHost READ connectionHost WRITE setConnectionHost NOTIFY connectionHostChanged)
    Q_PROPERTY(QString connectionPort READ connectionPort WRITE setConnectionPort NOTIFY connectionPortChanged)
    Q_PROPERTY(float gamepadDeadzone READ gamepadDeadzone WRITE setGamepadDeadzone NOTIFY gamepadDeadzoneChanged)
    Q_PROPERTY(bool gamepadHoldThrottle READ gamepadHoldThrottle WRITE setGamepadHoldThrottle NOTIFY gamepadHoldThrottleChanged)
    Q_PROPERTY(float throttleSpeed READ throttleSpeed WRITE setThrottleSpeed NOTIFY throttleSpeedChanged)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    QString connectionHost() const { return m_host; }
    QString connectionPort() const { return m_port; }
    float gamepadDeadzone() const { return m_deadzone; }
    bool gamepadHoldThrottle() const { return m_holdThrottle; }
    float throttleSpeed() const { return m_throttleSpeed; }

    void setConnectionHost(const QString &v);
    void setConnectionPort(const QString &v);
    void setGamepadDeadzone(float v);
    void setGamepadHoldThrottle(bool v);
    void setThrottleSpeed(float v);

    Q_INVOKABLE void resetToDefaults();
    Q_INVOKABLE void clearAllSettings();

signals:
    void connectionHostChanged();
    void connectionPortChanged();
    void gamepadDeadzoneChanged();
    void gamepadHoldThrottleChanged();
    void throttleSpeedChanged();

private:
    QSettings m_settings;
    QString m_host;
    QString m_port;
    float m_deadzone = 0.1f;
    bool m_holdThrottle = true;
    float m_throttleSpeed = 0.010f;
};
