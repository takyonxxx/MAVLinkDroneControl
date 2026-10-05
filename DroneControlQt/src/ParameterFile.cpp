// ParameterFile.cpp - DroneControlQt

#include "ParameterFile.h"

#include <QHash>
#include <QRegularExpression>
#include <algorithm>
#include <cmath>

namespace ParameterFile {

ParseResult parse(const QByteArray &rawData)
{
    ParseResult r;

    QByteArray data = rawData;
    if (data.startsWith("\xEF\xBB\xBF"))   // UTF-8 BOM
        data.remove(0, 3);

    static const QRegularExpression sep(QStringLiteral("[,\\s]+"));
    static const QRegularExpression nameRe(QStringLiteral("^[A-Za-z0-9_]{1,16}$"));

    const QStringList lines = QString::fromUtf8(data).split(QLatin1Char('\n'));
    QHash<QString, int> index;   // name -> position in r.entries

    for (int i = 0; i < lines.size(); ++i) {
        QString line = lines.at(i).trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')) || line.startsWith(QLatin1String("//")))
            continue;
        const int hash = line.indexOf(QLatin1Char('#'));   // trailing comment
        if (hash > 0)
            line = line.left(hash).trimmed();

        const QStringList t = line.split(sep, Qt::SkipEmptyParts);
        QString name, valueText;
        if (t.size() >= 4) {
            // QGroundControl: <sysid> <compid> <name> <value> <type>
            bool okSys = false, okComp = false;
            t.at(0).toInt(&okSys);
            t.at(1).toInt(&okComp);
            if (okSys && okComp) {
                name = t.at(2);
                valueText = t.at(3);
            }
        }
        if (name.isEmpty() && t.size() >= 2) {
            // Mission Planner / MAVProxy: <name>,<value>
            name = t.at(0);
            valueText = t.at(1);
        }

        bool ok = false;
        const double v = valueText.toDouble(&ok);   // C locale, '.' decimal point
        if (!nameRe.match(name).hasMatch() || !ok || !std::isfinite(v)) {
            r.errors << QStringLiteral("line %1: %2").arg(i + 1).arg(lines.at(i).trimmed().left(48));
            continue;
        }

        name = name.toUpper();
        auto it = index.constFind(name);
        if (it != index.constEnd()) {
            r.entries[it.value()].value = float(v);
            ++r.duplicates;
        } else {
            index.insert(name, r.entries.size());
            r.entries.append({name, float(v), i + 1});
        }
    }
    return r;
}

Kind classify(const QString &name)
{
    // Counters / format markers the vehicle owns
    static const QRegularExpression readOnly(QStringLiteral("^(STAT_|FORMAT_VERSION$)"));
    // Values earned on a specific airframe/board: sensor calibration, level trim,
    // RC endpoints, power module calibration, sensor device IDs
    static const QRegularExpression calibration(QStringLiteral(
        "^("
        "COMPASS_(OFS|DIA|ODI|MOT)\\d?_|COMPASS_SCALE\\d?$|COMPASS_DEV_ID\\d?$|COMPASS_PRIO\\d_ID$|"
        "INS_(ACC|GYR)\\d?(OFFS|SCAL)_|INS_(ACC|GYR)\\d?_(CALTEMP|ID)$|INS_TCAL|"
        "AHRS_TRIM_|"
        "RC\\d+_(MIN|MAX|TRIM)$|"
        "BATT\\d?_(AMP_PERVLT|VOLT_MULT|AMP_OFFSET)$|"
        "BARO\\d?_(GND_PRESS|DEVID)$|GND_ABS_PRESS"
        ")"));

    if (readOnly.match(name).hasMatch())
        return Kind::ReadOnly;
    if (calibration.match(name).hasMatch())
        return Kind::Calibration;
    return Kind::Normal;
}

bool valuesEqual(float a, float b)
{
    if (a == b)
        return true;
    const float diff = std::fabs(a - b);
    return diff <= 1e-6f + 1e-5f * std::max(std::fabs(a), std::fabs(b));
}

} // namespace ParameterFile
