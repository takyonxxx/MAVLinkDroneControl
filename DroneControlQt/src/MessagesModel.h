// MessagesModel.h - DroneControlQt
// STATUSTEXT log (port of VehicleMessage / statusMessages in MAVLinkManager.swift).

#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QVariantList>

class MessagesModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY countChanged)
    Q_PROPERTY(int maxSeverity READ maxSeverity WRITE setMaxSeverity NOTIFY maxSeverityChanged)

public:
    enum Roles {
        TextRole = Qt::UserRole + 1,
        SeverityRole,
        SeverityNameRole,
        TimeRole,        // "HH:mm:ss"
        TimestampRole    // ms since epoch
    };

    struct Message {
        QDateTime date;
        quint8 severity = 6;
        QString text;
    };

    explicit MessagesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_visible.size(); }
    int totalCount() const { return m_all.size(); }

    // 7 = show everything, 4 = warnings and worse, 3 = errors and worse
    int maxSeverity() const { return m_maxSeverity; }
    void setMaxSeverity(int s);

    void append(quint8 severity, const QString &text);
    Q_INVOKABLE void clear();

    // Newest-first list of messages whose text contains any keyword (case-insensitive)
    Q_INVOKABLE QVariantList filtered(const QStringList &keywords, int limit) const;

    static QString severityName(quint8 s);

signals:
    void countChanged();
    void maxSeverityChanged();

private:
    void rebuild();
    QVariantMap toMap(const Message &m) const;

    QList<Message> m_all;
    QList<int> m_visible;   // indexes into m_all
    int m_maxSeverity = 7;
    static constexpr int kMaxMessages = 300;
};
