// TileCache.h - local tile proxy/cache for the Leaflet map (port of the MarenControlConsole
// OfflineMapCache + tile HTTP server). The map page requests tiles from
// http://127.0.0.1:<port>/tiles/<layer>/<z>/<x>/<y>; tiles are served from the disk cache
// when present, otherwise fetched from the tile server, stored and served. So the map keeps
// working without internet (vehicle Wi-Fi) for every area that was viewed or pre-cached before.
#pragma once

#include <QObject>
#include <QTcpServer>
#include <QNetworkAccessManager>
#include <QHash>
#include <QPointer>
#include <QSet>
#include <QStringList>

class QTcpSocket;
class QNetworkReply;

class TileCache : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int port READ port CONSTANT)
    Q_PROPERTY(QString cacheDir READ cacheDir CONSTANT)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadChanged)
    Q_PROPERTY(int downloadDone READ downloadDone NOTIFY downloadChanged)
    Q_PROPERTY(int downloadTotal READ downloadTotal NOTIFY downloadChanged)
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    Q_PROPERTY(int cachedTiles READ cachedTiles NOTIFY cachedTilesChanged)

public:
    explicit TileCache(QObject *parent = nullptr);

    int port() const { return m_port; }
    QString cacheDir() const { return m_cacheDir; }
    bool downloading() const { return m_downloadTotal > 0; }
    int downloadDone() const { return m_downloadDone; }
    int downloadTotal() const { return m_downloadTotal; }
    bool online() const { return m_online; }
    int cachedTiles() const { return m_cachedTiles; }

    // Pre-download the satellite tiles of a circle (radius in metres) for zoom levels zMin..zMax.
    Q_INVOKABLE void downloadArea(double lat, double lon, double radiusM, int zMin, int zMax);
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void recount();

signals:
    void downloadChanged();
    void onlineChanged();
    void cachedTilesChanged();
    void downloadFinished(int tiles, int failed);

private:
    struct Tile { QString layer; int z, x, y; };

    void onNewConnection();
    void handleRequest(QTcpSocket *socket, const QByteArray &request);
    void serveTile(QTcpSocket *socket, const Tile &t);
    void fetchTile(const Tile &t, QTcpSocket *socket, bool forDownload = false);
    QString tilePath(const Tile &t) const;
    QStringList readPaths(const Tile &t) const;      // own cache + MarenControlConsole cache
    QString tileUrl(const Tile &t) const;
    static void reply(QTcpSocket *socket, int code, const QByteArray &body, const QByteArray &type);
    void pumpDownload();
    void setOnline(bool on);

    QTcpServer m_server;
    QNetworkAccessManager m_net;
    QString m_cacheDir;
    QStringList m_extraDirs;                          // read-only: MarenControlConsole MapTiles
    int m_port = 0;
    bool m_online = true;
    qint64 m_lastProbe = 0;
    int m_cachedTiles = 0;
    // tile key -> sockets waiting for the fetch. QPointer: Leaflet aborts tile requests while
    // panning/zooming, the socket is then deleted before the download finishes.
    QHash<QString, QList<QPointer<QTcpSocket>>> m_pending;

    QList<Tile> m_queue;
    int m_downloadDone = 0, m_downloadTotal = 0, m_downloadFailed = 0, m_inFlight = 0;
    bool m_cancel = false;
};
