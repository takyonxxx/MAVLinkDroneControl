// MessagesModel.cpp - DroneControlQt

#include "MessagesModel.h"

#include <QVariantMap>

MessagesModel::MessagesModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

QString MessagesModel::severityName(quint8 s)
{
    switch (s) {
    case 0: return QStringLiteral("EMERGENCY");
    case 1: return QStringLiteral("ALERT");
    case 2: return QStringLiteral("CRITICAL");
    case 3: return QStringLiteral("ERROR");
    case 4: return QStringLiteral("WARNING");
    case 5: return QStringLiteral("NOTICE");
    case 6: return QStringLiteral("INFO");
    default: return QStringLiteral("DEBUG");
    }
}

int MessagesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_visible.size();
}

QVariant MessagesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visible.size())
        return {};
    const Message &m = m_all.at(m_visible.at(index.row()));
    switch (role) {
    case TextRole: return m.text;
    case SeverityRole: return int(m.severity);
    case SeverityNameRole: return severityName(m.severity);
    case TimeRole: return m.date.toString(QStringLiteral("HH:mm:ss"));
    case TimestampRole: return m.date.toMSecsSinceEpoch();
    }
    return {};
}

QHash<int, QByteArray> MessagesModel::roleNames() const
{
    return {
        {TextRole, "text"},
        {SeverityRole, "severity"},
        {SeverityNameRole, "severityName"},
        {TimeRole, "time"},
        {TimestampRole, "timestamp"},
    };
}

void MessagesModel::setMaxSeverity(int s)
{
    if (m_maxSeverity == s)
        return;
    m_maxSeverity = s;
    emit maxSeverityChanged();
    rebuild();
}

void MessagesModel::append(quint8 severity, const QString &text)
{
    Message m;
    m.date = QDateTime::currentDateTime();
    m.severity = severity;
    m.text = text;

    if (m_all.size() >= kMaxMessages) {
        // Drop the oldest; indexes shift, so rebuild the visible list
        m_all.removeFirst();
        m_all.append(m);
        rebuild();
        return;
    }

    m_all.append(m);
    if (severity <= m_maxSeverity) {
        beginInsertRows(QModelIndex(), m_visible.size(), m_visible.size());
        m_visible.append(m_all.size() - 1);
        endInsertRows();
    }
    emit countChanged();
}

void MessagesModel::clear()
{
    beginResetModel();
    m_all.clear();
    m_visible.clear();
    endResetModel();
    emit countChanged();
}

void MessagesModel::rebuild()
{
    beginResetModel();
    m_visible.clear();
    for (int i = 0; i < m_all.size(); ++i)
        if (m_all.at(i).severity <= m_maxSeverity)
            m_visible.append(i);
    endResetModel();
    emit countChanged();
}

QVariantMap MessagesModel::toMap(const Message &m) const
{
    QVariantMap map;
    map.insert(QStringLiteral("text"), m.text);
    map.insert(QStringLiteral("severity"), int(m.severity));
    map.insert(QStringLiteral("severityName"), severityName(m.severity));
    map.insert(QStringLiteral("time"), m.date.toString(QStringLiteral("HH:mm:ss")));
    return map;
}

QVariantList MessagesModel::filtered(const QStringList &keywords, int limit) const
{
    QVariantList out;
    for (int i = m_all.size() - 1; i >= 0 && out.size() < limit; --i) {
        const Message &m = m_all.at(i);
        const QString upper = m.text.toUpper();
        for (const QString &k : keywords) {
            if (upper.contains(k.toUpper())) {
                out.append(toMap(m));
                break;
            }
        }
    }
    return out;
}
