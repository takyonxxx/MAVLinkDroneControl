// ParameterModel.h - DroneControlQt
//
// Holds every PARAM_VALUE received from the vehicle and exposes it to QML as a
// flat list: one "header" row per category followed by the parameter rows of
// that category (only when the category is expanded or a search filter is
// active). Categories/prefix rules are a port of ParametersView.swift.

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QMap>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

class ParameterModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,   // parameter name (or category name for headers)
        ValueRole,                     // float value
        ValueTextRole,                 // formatted value
        CategoryRole,                  // category name
        IconRole,                      // category glyph
        IsHeaderRole,                  // true for category header rows
        ExpandedRole,                  // header: category expanded?
        CategoryCountRole,             // header: params in category
        RecentlyWrittenRole            // param: written in the last 4 s
    };

    explicit ParameterModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_values.size(); }
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);

    // Called by MavlinkManager
    void setValue(const QString &name, float value);
    void clear();
    bool contains(const QString &name) const { return m_values.contains(name); }
    float value(const QString &name, float def = 0.0f) const { return m_values.value(name, def); }

    Q_INVOKABLE QVariant get(const QString &name) const;          // undefined if unknown
    Q_INVOKABLE void toggleCategory(const QString &category);
    Q_INVOKABLE bool isExpanded(const QString &category) const;
    Q_INVOKABLE void markWritten(const QString &name);
    Q_INVOKABLE QVariantList sortedList() const;                  // [{name,value,valueText}] all params
    Q_INVOKABLE static QString formatValue(float v);
    static QString categoryFor(const QString &name);
    static QString iconFor(const QString &category);

signals:
    void countChanged();
    void filterChanged();
    void valueChanged(const QString &name, float value);

private:
    struct Row {
        bool header = false;
        QString name;       // param name, or category name for headers
        QString category;
    };

    void scheduleRebuild();
    void rebuild();

    QMap<QString, float> m_values;              // sorted by name
    QHash<QString, int> m_categoryCounts;
    QSet<QString> m_expanded;
    QSet<QString> m_recentlyWritten;
    QString m_filter;
    QList<Row> m_rows;
    QHash<QString, int> m_rowIndex;             // param name -> row (visible rows only)
    QTimer m_rebuildTimer;
};
