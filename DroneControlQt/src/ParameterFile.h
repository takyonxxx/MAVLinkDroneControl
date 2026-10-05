// ParameterFile.h - DroneControlQt
//
// Parser for ArduPilot parameter files saved by Mission Planner / MAVProxy
// ("NAME,VALUE" or "NAME VALUE") and QGroundControl ("SYS COMP NAME VALUE TYPE").
// Lines starting with '#' or '//' are comments. Port-twin of ParameterFile.swift.

#pragma once

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringList>

namespace ParameterFile {

struct Entry {
    QString name;
    float value = 0.0f;
    int line = 0;
};

struct ParseResult {
    QList<Entry> entries;     // file order, duplicates collapsed (last value wins)
    QStringList errors;       // "line N: <text>" for unparsable lines
    int duplicates = 0;
};

enum class Kind {
    Normal,
    ReadOnly,       // STAT_*, FORMAT_VERSION - never written
    Calibration     // per-airframe calibration / board IDs - optional skip
};

ParseResult parse(const QByteArray &data);
Kind classify(const QString &name);
bool valuesEqual(float a, float b);

} // namespace ParameterFile
