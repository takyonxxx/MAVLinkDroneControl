// ParameterModel.cpp - DroneControlQt

#include "ParameterModel.h"

#include <QVariantMap>
#include <cmath>

namespace {

struct Category {
    const char *name;
    const char *icon;
    QStringList prefixes;
};

// Order matters: a parameter goes into the first matching category
const QList<Category> &categories()
{
    static const QList<Category> list = {
        {"Servos", "S", {"SERVO"}},
        {"Radio (RC)", "R", {"RC1", "RC2", "RC3", "RC4", "RC5", "RC6", "RC7", "RC8", "RC9",
                            "RC1_", "RC_", "RCMAP", "FLTMODE", "THR_", "PILOT"}},
        {"AutoTune", "A", {"AUTOTUNE"}},
        {"Attitude Control (ATC)", "G", {"ATC_"}},
        {"Motors", "M", {"MOT_"}},
        {"GPS", "L", {"GPS"}},
        {"Compass", "C", {"COMPASS"}},
        {"EKF / AHRS", "E", {"EK2_", "EK3_", "AHRS", "VISO"}},
        {"IMU / Vibration", "I", {"INS_"}},
        {"Battery / Power", "B", {"BATT", "BRD_VBUS", "MOT_BAT"}},
        {"Navigation (Loiter/WP)", "N", {"LOIT", "PSC", "WPNAV", "RTL_", "LAND_", "PHLD", "CIRCLE", "SURFTRAK"}},
        {"Failsafe", "F", {"FS_", "BATT_FS", "FENCE"}},
        {"Arming", "K", {"ARMING", "DISARM"}},
        {"Telemetry / Serial Ports", "T", {"SR0", "SR1", "SR2", "SR3", "SERIAL", "TELEM"}},
        {"Rangefinder / Optical Flow", "D", {"RNGFND", "FLOW"}},
        {"Board / System", "Y", {"BRD_", "SCHED", "LOG_", "STAT_", "SYSID", "FRAME", "NTF_"}},
    };
    return list;
}

int categoryOrder(const QString &category)
{
    const auto &cats = categories();
    for (int i = 0; i < cats.size(); ++i)
        if (category == QLatin1String(cats[i].name))
            return i;
    return cats.size();   // "Other" goes last
}

} // namespace

ParameterModel::ParameterModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_rebuildTimer.setSingleShot(true);
    m_rebuildTimer.setInterval(150);
    connect(&m_rebuildTimer, &QTimer::timeout, this, &ParameterModel::rebuild);
}

QString ParameterModel::categoryFor(const QString &name)
{
    for (const Category &cat : categories())
        for (const QString &p : cat.prefixes)
            if (name.startsWith(p))
                return QString::fromLatin1(cat.name);
    return QStringLiteral("Other");
}

QString ParameterModel::iconFor(const QString &category)
{
    for (const Category &cat : categories())
        if (category == QLatin1String(cat.name))
            return QString::fromLatin1(cat.icon);
    return QStringLiteral("O");
}

QString ParameterModel::formatValue(float v)
{
    if (v == std::round(v) && std::fabs(v) < 1e7f)
        return QString::number(double(v), 'f', 0);
    return QString::number(double(v), 'g', 7);
}

int ParameterModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant ParameterModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const Row &r = m_rows.at(index.row());
    switch (role) {
    case NameRole: return r.name;
    case ValueRole: return r.header ? 0.0f : m_values.value(r.name);
    case ValueTextRole: return r.header ? QString() : formatValue(m_values.value(r.name));
    case CategoryRole: return r.category;
    case IconRole: return iconFor(r.category);
    case IsHeaderRole: return r.header;
    case ExpandedRole: return m_expanded.contains(r.category) || !m_filter.isEmpty();
    case CategoryCountRole: return m_categoryCounts.value(r.category);
    case RecentlyWrittenRole: return !r.header && m_recentlyWritten.contains(r.name);
    }
    return {};
}

QHash<int, QByteArray> ParameterModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {ValueRole, "value"},
        {ValueTextRole, "valueText"},
        {CategoryRole, "category"},
        {IconRole, "icon"},
        {IsHeaderRole, "isHeader"},
        {ExpandedRole, "expanded"},
        {CategoryCountRole, "categoryCount"},
        {RecentlyWrittenRole, "recentlyWritten"},
    };
}

void ParameterModel::setFilter(const QString &f)
{
    if (m_filter == f)
        return;
    m_filter = f;
    emit filterChanged();
    rebuild();
}

void ParameterModel::setValue(const QString &name, float value)
{
    const bool isNew = !m_values.contains(name);
    m_values[name] = value;
    if (isNew) {
        m_categoryCounts[categoryFor(name)]++;
        emit countChanged();
        scheduleRebuild();
    } else {
        const int row = m_rowIndex.value(name, -1);
        if (row >= 0) {
            const QModelIndex idx = index(row);
            emit dataChanged(idx, idx, {ValueRole, ValueTextRole});
        }
    }
    emit valueChanged(name, value);
}

void ParameterModel::clear()
{
    beginResetModel();
    m_values.clear();
    m_categoryCounts.clear();
    m_rows.clear();
    m_rowIndex.clear();
    endResetModel();
    emit countChanged();
}

QVariant ParameterModel::get(const QString &name) const
{
    auto it = m_values.constFind(name);
    if (it == m_values.constEnd())
        return {};
    return it.value();
}

void ParameterModel::toggleCategory(const QString &category)
{
    if (m_expanded.contains(category))
        m_expanded.remove(category);
    else
        m_expanded.insert(category);
    rebuild();
}

bool ParameterModel::isExpanded(const QString &category) const
{
    return m_expanded.contains(category);
}

void ParameterModel::markWritten(const QString &name)
{
    m_recentlyWritten.insert(name);
    auto notify = [this, name]() {
        const int row = m_rowIndex.value(name, -1);
        if (row >= 0) {
            const QModelIndex idx = index(row);
            emit dataChanged(idx, idx, {RecentlyWrittenRole});
        }
    };
    notify();
    QTimer::singleShot(4000, this, [this, name, notify]() {
        m_recentlyWritten.remove(name);
        notify();
    });
}

QVariantList ParameterModel::sortedList() const
{
    QVariantList out;
    out.reserve(m_values.size());
    for (auto it = m_values.constBegin(); it != m_values.constEnd(); ++it) {
        QVariantMap m;
        m.insert(QStringLiteral("name"), it.key());
        m.insert(QStringLiteral("value"), it.value());
        m.insert(QStringLiteral("valueText"), formatValue(it.value()));
        out.append(m);
    }
    return out;
}

void ParameterModel::scheduleRebuild()
{
    if (!m_rebuildTimer.isActive())
        m_rebuildTimer.start();
}

void ParameterModel::rebuild()
{
    m_rebuildTimer.stop();

    const QString filter = m_filter.trimmed().toUpper();
    // category -> sorted names (QMap iteration is already sorted by name)
    QMap<int, QPair<QString, QStringList>> buckets;
    for (auto it = m_values.constBegin(); it != m_values.constEnd(); ++it) {
        if (!filter.isEmpty() && !it.key().toUpper().contains(filter))
            continue;
        const QString cat = categoryFor(it.key());
        auto &b = buckets[categoryOrder(cat)];
        b.first = cat;
        b.second.append(it.key());
    }

    QList<Row> rows;
    QHash<QString, int> rowIndex;
    for (auto it = buckets.constBegin(); it != buckets.constEnd(); ++it) {
        const QString &cat = it.value().first;
        Row h;
        h.header = true;
        h.name = cat;
        h.category = cat;
        rows.append(h);
        if (m_expanded.contains(cat) || !filter.isEmpty()) {
            for (const QString &n : it.value().second) {
                Row r;
                r.name = n;
                r.category = cat;
                rowIndex.insert(n, rows.size());
                rows.append(r);
            }
        }
    }

    beginResetModel();
    m_rows = rows;
    m_rowIndex = rowIndex;
    endResetModel();
}
