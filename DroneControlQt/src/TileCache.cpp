// TileCache.cpp - see TileCache.h
#include "TileCache.h"

#include <QTcpSocket>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QDirIterator>
#include <QDebug>
#include <QtMath>
#include <QUrl>
#include <QImage>
#include <QDateTime>
#include <QBuffer>

namespace {
const char *kUserAgent = "DroneControl/1.0 (Qt; +https://marenrobotics.com)";

QByteArray sniffType(const QByteArray &d)
{
    if (d.startsWith("\x89PNG")) return "image/png";
    if (d.startsWith("\xFF\xD8")) return "image/jpeg";
    if (d.startsWith("GIF8")) return "image/gif";
    return "application/octet-stream";
}
} // namespace

TileCache::TileCache(QObject *parent) : QObject(parent)
{
    m_cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/MapTiles");
    QDir().mkpath(m_cacheDir);

    // Tiles already cached by MarenControlConsole (same arcgis/{z}/{y}/{x}.png layout) are used read-only.
    const QString genericCache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    for (const QString &d : { genericCache + QStringLiteral("/Maren Robotics/MarenControlConsole/MapTiles"),
                              genericCache + QStringLiteral("/Maren Robotics/MarenControlConsole/cache/MapTiles"),
                              genericCache + QStringLiteral("/MarenControlConsole/MapTiles") }) {
        if (QDir(d).exists() && QDir(d).absolutePath() != QDir(m_cacheDir).absolutePath())
            m_extraDirs << d;
    }

    m_net.setTransferTimeout(15000);
    connect(&m_server, &QTcpServer::newConnection, this, &TileCache::onNewConnection);
    if (!m_server.listen(QHostAddress::LocalHost, 0)) {
        qWarning() << "[TILES] local tile server failed:" << m_server.errorString();
        return;
    }
    m_port = m_server.serverPort();
    recount();
    qDebug() << "[TILES] serving from" << m_cacheDir << "on 127.0.0.1:" << m_port
             << "extra caches:" << m_extraDirs << "cached tiles:" << m_cachedTiles;
}

void TileCache::recount()
{
    int n = 0;
    QDirIterator it(m_cacheDir, { QStringLiteral("*.png") }, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) { it.next(); ++n; }
    if (n != m_cachedTiles) { m_cachedTiles = n; emit cachedTilesChanged(); }
}

// ---------------------------------------------------------------- paths / urls

QString TileCache::tilePath(const Tile &t) const
{
    const QString dir = t.layer == QLatin1String("satellite") ? QStringLiteral("arcgis") : t.layer;
    return QStringLiteral("%1/%2/%3/%4/%5.png").arg(m_cacheDir, dir).arg(t.z).arg(t.y).arg(t.x);
}

QStringList TileCache::readPaths(const Tile &t) const
{
    QStringList out{ tilePath(t) };
    const QString dir = t.layer == QLatin1String("satellite") ? QStringLiteral("arcgis") : t.layer;
    for (const QString &base : m_extraDirs)
        out << QStringLiteral("%1/%2/%3/%4/%5.png").arg(base, dir).arg(t.z).arg(t.y).arg(t.x);
    return out;
}

QString TileCache::tileUrl(const Tile &t) const
{
    if (t.layer == QLatin1String("street"))
        return QStringLiteral("https://tile.openstreetmap.org/%1/%2/%3.png").arg(t.z).arg(t.x).arg(t.y);
    if (t.layer == QLatin1String("labels"))
        return QStringLiteral("https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/%1/%2/%3").arg(t.z).arg(t.y).arg(t.x);
    if (t.layer == QLatin1String("seamarks"))
        return QStringLiteral("https://tiles.openseamap.org/seamark/%1/%2/%3.png").arg(t.z).arg(t.x).arg(t.y);
    return QStringLiteral("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%1/%2/%3").arg(t.z).arg(t.y).arg(t.x);
}

// ---------------------------------------------------------------- tiny HTTP server

void TileCache::onNewConnection()
{
    while (QTcpSocket *s = m_server.nextPendingConnection()) {
        connect(s, &QTcpSocket::readyRead, this, [this, s]() {
            if (!s->canReadLine()) return;
            handleRequest(s, s->readAll());
        });
        connect(s, &QTcpSocket::errorOccurred, s, [s]() { s->disconnectFromHost(); });
        connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
    }
}

void TileCache::handleRequest(QTcpSocket *socket, const QByteArray &request)
{
    const QList<QByteArray> parts = request.split('\n').first().trimmed().split(' ');
    if (parts.size() < 2 || parts[0] != "GET") { reply(socket, 400, {}, "text/plain"); return; }
    // /tiles/<layer>/<z>/<x>/<y>
    const QStringList seg = QString::fromLatin1(parts[1]).section('?', 0, 0).split('/', Qt::SkipEmptyParts);
    if (seg.size() != 5 || seg[0] != QLatin1String("tiles")) { reply(socket, 404, {}, "text/plain"); return; }
    Tile t{ seg[1], seg[2].toInt(), seg[3].toInt(), seg[4].section('.', 0, 0).toInt() };
    if (t.z < 0 || t.z > 22) { reply(socket, 404, {}, "text/plain"); return; }
    serveTile(socket, t);
}

void TileCache::serveTile(QTcpSocket *socket, const Tile &t)
{
    for (const QString &p : readPaths(t)) {
        QFile f(p);
        if (f.exists() && f.open(QIODevice::ReadOnly)) {
            const QByteArray data = f.readAll();
            if (!data.isEmpty()) { reply(socket, 200, data, sniffType(data)); return; }
        }
    }
    if (!m_online && QDateTime::currentMSecsSinceEpoch() - m_lastProbe > 20000) {
        m_lastProbe = QDateTime::currentMSecsSinceEpoch();       // re-probe the network every 20 s
        fetchTile(t, socket);
        return;
    }
    if (!m_online) {
        // offline: fall back to the nearest cached ancestor tile, scaled up (up to 4 zoom levels)
        for (int up = 1; up <= 4 && t.z - up >= 0; ++up) {
            Tile a{ t.layer, t.z - up, t.x >> up, t.y >> up };
            for (const QString &p : readPaths(a)) {
                QImage img(p);
                if (img.isNull()) continue;
                const int f = 1 << up, sz = img.width() / f;
                const QImage part = img.copy((t.x & (f - 1)) * sz, (t.y & (f - 1)) * sz, sz, sz)
                                        .scaled(img.width(), img.height(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
                QByteArray out;
                QBuffer buf(&out);
                buf.open(QIODevice::WriteOnly);
                part.save(&buf, "PNG");
                reply(socket, 200, out, "image/png");
                return;
            }
        }
    }
    fetchTile(t, socket);
}

void TileCache::reply(QTcpSocket *socket, int code, const QByteArray &body, const QByteArray &type)
{
    if (!socket || socket->state() != QAbstractSocket::ConnectedState) return;
    QByteArray head = "HTTP/1.1 " + QByteArray::number(code) + (code == 200 ? " OK" : (code == 404 ? " Not Found" : " Error")) + "\r\n"
                      "Content-Type: " + type + "\r\n"
                      "Content-Length: " + QByteArray::number(body.size()) + "\r\n"
                      "Cache-Control: max-age=86400\r\n"
                      "Access-Control-Allow-Origin: *\r\n"
                      "Connection: close\r\n\r\n";
    socket->write(head + body);
    socket->disconnectFromHost();
}

// ---------------------------------------------------------------- online fetch

void TileCache::fetchTile(const Tile &t, QTcpSocket *socket, bool forDownload)
{
    const QString key = QStringLiteral("%1/%2/%3/%4").arg(t.layer).arg(t.z).arg(t.x).arg(t.y);
    if (m_pending.contains(key)) {                 // already being fetched: queue the socket
        if (socket) m_pending[key] << socket;
        if (forDownload) { ++m_downloadDone; emit downloadChanged(); }
        return;
    }
    m_pending.insert(key, socket ? QList<QPointer<QTcpSocket>>{ socket } : QList<QPointer<QTcpSocket>>{});

    QNetworkRequest req{ QUrl(tileUrl(t)) };
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(kUserAgent));
    req.setRawHeader("Referer", "https://www.arcgis.com/");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *r = m_net.get(req);
    ++m_inFlight;
    connect(r, &QNetworkReply::finished, this, [this, r, t, key, forDownload]() {
        --m_inFlight;
        r->deleteLater();
        const QByteArray data = r->error() == QNetworkReply::NoError ? r->readAll() : QByteArray();
        const bool ok = !data.isEmpty() && sniffType(data) != "application/octet-stream";
        if (ok) {
            const QString path = tilePath(t);
            QDir().mkpath(QFileInfo(path).path());
            QFile f(path);
            if (f.open(QIODevice::WriteOnly)) { f.write(data); ++m_cachedTiles; emit cachedTilesChanged(); }
            setOnline(true);
        } else {
            if (r->error() != QNetworkReply::NoError && r->error() != QNetworkReply::ContentNotFoundError)
                setOnline(false);
            if (!m_pending.value(key).isEmpty())
                qDebug() << "[TILES] fetch failed" << key << r->errorString();
        }
        const auto sockets = m_pending.take(key);
        for (const QPointer<QTcpSocket> &s : sockets) {
            if (!s) continue;                       // client gave up (tile scrolled out of view)
            if (ok) reply(s, 200, data, sniffType(data));
            else reply(s, 404, {}, "text/plain");
        }
        if (forDownload) {
            if (ok) ++m_downloadDone; else ++m_downloadFailed;
            emit downloadChanged();
            pumpDownload();
        }
    });
}

void TileCache::setOnline(bool on)
{
    if (on == m_online) return;
    m_online = on;
    emit onlineChanged();
    qDebug() << "[TILES] tile server" << (on ? "reachable" : "unreachable - serving cached tiles only");
}

// ---------------------------------------------------------------- area pre-download

void TileCache::downloadArea(double lat, double lon, double radiusM, int zMin, int zMax)
{
    if (m_downloadTotal > 0) return;
    m_queue.clear();
    const double dLat = radiusM / 111320.0;
    const double dLon = radiusM / (111320.0 * qCos(qDegreesToRadians(lat)));
    for (int z = qBound(2, zMin, 19); z <= qBound(2, zMax, 19); ++z) {
        const double n = qPow(2.0, z);
        auto tx = [&](double lo) { return int(qFloor((lo + 180.0) / 360.0 * n)); };
        auto ty = [&](double la) {
            const double r = qDegreesToRadians(la);
            return int(qFloor((1.0 - qLn(qTan(r) + 1.0 / qCos(r)) / M_PI) / 2.0 * n));
        };
        const int x0 = tx(lon - dLon), x1 = tx(lon + dLon), y0 = ty(lat + dLat), y1 = ty(lat - dLat);
        for (int x = x0; x <= x1; ++x)
            for (int y = y0; y <= y1; ++y) {
                Tile t{ QStringLiteral("satellite"), z, x, y };
                if (!QFile::exists(tilePath(t))) m_queue << t;
                if (m_queue.size() > 6000) break;
            }
    }
    m_downloadTotal = m_queue.size();
    m_downloadDone = m_downloadFailed = 0;
    m_cancel = false;
    qDebug() << "[TILES] pre-download" << m_downloadTotal << "tiles around" << lat << lon << "radius" << radiusM << "z" << zMin << "-" << zMax;
    if (m_downloadTotal == 0) { emit downloadFinished(0, 0); return; }
    emit downloadChanged();
    pumpDownload();
}

void TileCache::cancelDownload()
{
    m_cancel = true;
    m_queue.clear();
}

void TileCache::pumpDownload()
{
    while (!m_queue.isEmpty() && m_inFlight < 6 && !m_cancel)
        fetchTile(m_queue.takeFirst(), nullptr, true);
    if ((m_queue.isEmpty() || m_cancel) && m_inFlight == 0 && m_downloadTotal > 0) {
        const int done = m_downloadDone, failed = m_downloadFailed;
        m_downloadTotal = 0;
        m_downloadDone = m_downloadFailed = 0;
        emit downloadChanged();
        emit downloadFinished(done, failed);
        qDebug() << "[TILES] pre-download finished:" << done << "ok," << failed << "failed";
    }
}
