// UdpConnection.h - DroneControlQt
//
// UDP link to the vehicle (port of UDPConnection.swift).
// Binds a local port, sends to the configured remote endpoint and, like the
// iOS version, also echoes outgoing packets to every peer that has talked to
// us in this session (ESP bridge / SITL forwarders).

#pragma once

#include <QHostAddress>
#include <QObject>
#include <QUdpSocket>
#include <QHash>

class UdpConnection : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(QString connectionState READ connectionState NOTIFY connectedChanged)

public:
    explicit UdpConnection(QObject *parent = nullptr);
    ~UdpConnection() override;

    bool isConnected() const { return m_connected; }
    QString connectionState() const { return m_connected ? QStringLiteral("Connected") : QStringLiteral("Not connected"); }

    QString host() const { return m_host; }
    quint16 port() const { return m_remotePort; }
    quint16 localPort() const { return m_localPort; }

    void setEndpoint(const QString &host, quint16 port, quint16 localPort);
    void updateEndpoint(const QString &host, quint16 port);

public slots:
    void connectSocket();
    void disconnectSocket();
    void send(const QByteArray &data);

signals:
    void dataReceived(const QByteArray &data);
    void connectedChanged(bool connected);

private slots:
    void onReadyRead();

private:
    void setConnected(bool c);
    void resolveHost();

    QUdpSocket *m_socket = nullptr;
    QString m_host = QStringLiteral("192.168.4.1");
    quint16 m_remotePort = 14550;
    quint16 m_localPort = 14550;
    QHostAddress m_remoteAddr;
    bool m_connected = false;

    // "ip:port" -> peer, everyone who sent us a datagram this session
    QHash<QString, QPair<QHostAddress, quint16>> m_sessionTargets;
};
