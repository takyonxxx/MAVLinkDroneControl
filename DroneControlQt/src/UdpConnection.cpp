// UdpConnection.cpp - DroneControlQt

#include "UdpConnection.h"

#include <QDebug>
#include <QHostInfo>
#include <QNetworkDatagram>
#include <QTimer>

UdpConnection::UdpConnection(QObject *parent)
    : QObject(parent)
{
}

UdpConnection::~UdpConnection()
{
    disconnectSocket();
}

void UdpConnection::setEndpoint(const QString &host, quint16 port, quint16 localPort)
{
    m_host = host.trimmed();
    m_remotePort = port;
    m_localPort = localPort;
    resolveHost();
}

void UdpConnection::updateEndpoint(const QString &host, quint16 port)
{
    m_host = host.trimmed();
    m_remotePort = port;
    resolveHost();

    if (m_connected) {
        disconnectSocket();
        QTimer::singleShot(500, this, &UdpConnection::connectSocket);
    }
}

void UdpConnection::resolveHost()
{
    QHostAddress addr(m_host);
    if (!addr.isNull()) {
        m_remoteAddr = addr;
        return;
    }
    // Hostname: resolve asynchronously, keep the old address meanwhile
    QHostInfo::lookupHost(m_host, this, [this](const QHostInfo &info) {
        for (const QHostAddress &a : info.addresses()) {
            if (a.protocol() == QAbstractSocket::IPv4Protocol) {
                m_remoteAddr = a;
                qDebug() << "[UDP] Resolved" << m_host << "->" << a.toString();
                return;
            }
        }
        qWarning() << "[UDP] Could not resolve host" << m_host;
    });
}

void UdpConnection::connectSocket()
{
    if (m_socket)
        disconnectSocket();

    qDebug() << "[UDP] Connecting socket, local port" << m_localPort
             << "remote" << m_remoteAddr.toString() << ":" << m_remotePort;

    m_socket = new QUdpSocket(this);
    connect(m_socket, &QUdpSocket::readyRead, this, &UdpConnection::onReadyRead);

    if (!m_socket->bind(QHostAddress::AnyIPv4, m_localPort,
                        QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qWarning() << "[UDP] Failed to bind port" << m_localPort << ":" << m_socket->errorString();
        // Fall back to an ephemeral port so the app can still talk to the vehicle
        if (!m_socket->bind(QHostAddress::AnyIPv4, 0)) {
            qWarning() << "[UDP] Failed to bind any port:" << m_socket->errorString();
            m_socket->deleteLater();
            m_socket = nullptr;
            setConnected(false);
            return;
        }
        qDebug() << "[UDP] Bound to ephemeral port" << m_socket->localPort();
    } else {
        qDebug() << "[UDP] Socket bound to 0.0.0.0:" << m_localPort;
    }

    if (m_remoteAddr.isNull()) {
        qWarning() << "[UDP] Remote host address not resolved yet";
    }

    setConnected(true);
}

void UdpConnection::disconnectSocket()
{
    if (m_socket) {
        qDebug() << "[UDP] Disconnecting";
        m_socket->close();
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    m_sessionTargets.clear();
    setConnected(false);
}

void UdpConnection::onReadyRead()
{
    if (!m_socket)
        return;
    while (m_socket->hasPendingDatagrams()) {
        QNetworkDatagram dg = m_socket->receiveDatagram();
        if (!dg.isValid())
            continue;

        const QHostAddress sender = dg.senderAddress();
        const quint16 senderPort = quint16(dg.senderPort());
        const QString key = sender.toString() + QLatin1Char(':') + QString::number(senderPort);
        if (!m_sessionTargets.contains(key)) {
            m_sessionTargets.insert(key, qMakePair(sender, senderPort));
            qDebug() << "[UDP] New peer" << key;
        }
        emit dataReceived(dg.data());
    }
}

void UdpConnection::send(const QByteArray &data)
{
    if (!m_connected || !m_socket)
        return;

    if (!m_remoteAddr.isNull()) {
        if (m_socket->writeDatagram(data, m_remoteAddr, m_remotePort) < 0)
            qWarning() << "[UDP] Send error:" << m_socket->errorString();
    }

    // Echo to every session peer that is not the primary target
    for (auto it = m_sessionTargets.cbegin(); it != m_sessionTargets.cend(); ++it) {
        const QHostAddress &a = it.value().first;
        const quint16 p = it.value().second;
        if (a.isEqual(m_remoteAddr, QHostAddress::TolerantConversion) && p == m_remotePort)
            continue;
        m_socket->writeDatagram(data, a, p);
    }
}

void UdpConnection::setConnected(bool c)
{
    if (m_connected == c)
        return;
    m_connected = c;
    emit connectedChanged(c);
}
