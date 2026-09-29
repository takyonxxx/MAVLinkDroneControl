// DefaultParameters.h - DroneControlQt
// Known-good parameter snapshot (turkay_copter_v6) used by "Restore Defaults".
// Auto-generated from DefaultParameters.swift - do not edit by hand.
//
// Excluded on purpose - earned/calibrated values must survive a restore:
//  * Tuning: ATC_* (AutoTune writes here), AUTOTUNE_*, PSC_*, MOT_THST_HOVER
//  * Compass calibration: COMPASS_OFS/DIA/ODI/SCALE/MOT*
//  * Accel/gyro calibration: INS_ACC*/GYR* offsets & scales, CALTEMP, INS_TCAL*
//  * Level trim: AHRS_TRIM_*
//  * RC calibration: RCn_MIN/MAX/TRIM (REVERSED/DZ/OPTION are config, kept)
//  * Power module calibration: BATT_AMP_PERVLT, BATT_VOLT_MULT
//  * Baro ground pressure, STAT_* counters

#pragma once

#include <QList>
#include <QPair>
#include <QString>

namespace DefaultParameters {
using Entry = QPair<QString, float>;
const QList<Entry> &values();
}
