#!/usr/bin/env python3
"""Tiny ArduCopter-like MAVLink simulator for testing DroneControlQt without hardware.

Sends HEARTBEAT, SYS_STATUS, ATTITUDE, GPS_RAW_INT, GLOBAL_POSITION_INT, VFR_HUD,
SERVO_OUTPUT_RAW, SCALED_PRESSURE, SCALED_IMU, EKF_STATUS_REPORT and STATUSTEXT
to the GCS, answers PARAM_REQUEST_LIST / PARAM_REQUEST_READ / PARAM_SET,
COMMAND_LONG (ACKs, arm/disarm, motor test, mag cal with progress/report) and
SET_MODE, and prints MANUAL_CONTROL it receives.

Usage:  python3 sim_vehicle.py [gcs_host] [gcs_port]
        then set the app's connection host to 127.0.0.1 (or run on the same machine).

Requires: pip install pymavlink
"""
import math
import os
import sys
import time

os.environ["MAVLINK20"] = "1"   # must be set before importing pymavlink

from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as mav

gcs_host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
gcs_port = int(sys.argv[2]) if len(sys.argv) > 2 else 14550

# The GCS binds 14550 and sends to us on 14551; we send to the GCS on 14550
conn = mavutil.mavlink_connection(f"udpout:{gcs_host}:{gcs_port}", source_system=1, source_component=1,
                                  input=False)
m = conn.mav

params = {
    "ARMING_CHECK": 1.0, "MOT_PWM_MIN": 1000.0, "MOT_PWM_MAX": 2000.0, "LOIT_SPEED": 1250.0,
    "RC1_MIN": 1000.0, "RC1_MAX": 2000.0, "SERVO1_FUNCTION": 33.0, "SERVO2_FUNCTION": 34.0,
    "GPS_TYPE": 1.0, "COMPASS_USE": 1.0, "EK3_ENABLE": 1.0, "INS_GYRO_FILTER": 20.0,
    "BATT_MONITOR": 4.0, "WPNAV_SPEED": 1000.0, "FS_THR_ENABLE": 1.0, "SR0_EXTRA1": 4.0,
    "RNGFND1_TYPE": 0.0, "BRD_SAFETYENABLE": 0.0, "FRAME_CLASS": 1.0, "ATC_RAT_RLL_P": 0.135,
    "PSC_POSXY_P": 1.0, "AUTOTUNE_AXES": 7.0, "THR_DZ": 100.0, "PILOT_SPEED_UP": 250.0,
}

armed = False
mode = 0
motor_test_pwm = 0
motor_test_until = 0.0
magcal_started = 0.0
magcal_accept_pending = False
t0 = time.time()
last = {}


def every(key, period):
    now = time.time()
    if now - last.get(key, 0) >= period:
        last[key] = now
        return True
    return False


def send_statustext(sev, text):
    m.statustext_send(sev, text.encode()[:50])


def send_param(name, index):
    m.param_value_send(name.encode(), params[name], mav.MAV_PARAM_TYPE_REAL32, len(params), index)


def handle(msg):
    global armed, mode, motor_test_pwm, motor_test_until, magcal_started, magcal_accept_pending
    t = msg.get_type()
    if t == "MANUAL_CONTROL":
        if every("mc_print", 1.0):
            print(f"MANUAL_CONTROL x={msg.x} y={msg.y} z={msg.z} r={msg.r}")
    elif t == "PARAM_REQUEST_LIST":
        print("PARAM_REQUEST_LIST")
        for i, n in enumerate(sorted(params)):
            send_param(n, i)
    elif t == "PARAM_REQUEST_READ":
        name = msg.param_id.split("\0")[0] if isinstance(msg.param_id, str) else msg.param_id.decode().split("\0")[0]
        if name in params:
            send_param(name, sorted(params).index(name))
    elif t == "PARAM_SET":
        name = msg.param_id.split("\0")[0] if isinstance(msg.param_id, str) else msg.param_id.decode().split("\0")[0]
        params[name] = msg.param_value
        print(f"PARAM_SET {name} = {msg.param_value}")
        send_param(name, sorted(params).index(name) if name in sorted(params) else 65535)
    elif t == "SET_MODE":
        mode = msg.custom_mode
        print(f"SET_MODE {mode}")
        send_statustext(6, f"Mode set to {mode}")
    elif t == "COMMAND_LONG":
        cmd = msg.command
        result = mav.MAV_RESULT_ACCEPTED
        if cmd == mav.MAV_CMD_COMPONENT_ARM_DISARM:
            want = msg.param1 > 0.5
            if want and params["ARMING_CHECK"] != 0 and msg.param2 != 21196:
                send_statustext(3, "PreArm: Compass not calibrated")
                result = mav.MAV_RESULT_FAILED
            else:
                armed = want
                send_statustext(6, "Arming motors" if armed else "Disarming motors")
        elif cmd == mav.MAV_CMD_DO_MOTOR_TEST:
            motor_test_pwm = int(msg.param3)
            motor_test_until = time.time() + msg.param4
            print(f"MOTOR_TEST seq={int(msg.param1)} pwm={motor_test_pwm} timeout={msg.param4}")
        elif cmd == mav.MAV_CMD_DO_START_MAG_CAL:
            magcal_started = time.time()
            magcal_accept_pending = False
            send_statustext(6, "Compass calibration started")
        elif cmd == mav.MAV_CMD_DO_CANCEL_MAG_CAL:
            magcal_started = 0
        elif cmd == mav.MAV_CMD_DO_ACCEPT_MAG_CAL:
            send_statustext(6, "Compass calibration accepted")
        elif cmd == mav.MAV_CMD_PREFLIGHT_CALIBRATION:
            send_statustext(6, "Calibrating gyros" if msg.param1 else "Baro calibrated")
        elif cmd == mav.MAV_CMD_SET_MESSAGE_INTERVAL:
            pass
        m.command_ack_send(cmd, result)


print(f"Simulator sending to {gcs_host}:{gcs_port}; listening on the reply port")
send_statustext(6, "ArduCopter V4.6.3 (sim)")
send_statustext(6, "GPS 1: detected as u-blox")

while True:
    now = time.time()
    tt = now - t0
    msg = conn.recv_match(blocking=False)
    while msg is not None:
        handle(msg)
        msg = conn.recv_match(blocking=False)

    base_mode = mav.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
    in_test = now < motor_test_until
    if armed or in_test:
        base_mode |= mav.MAV_MODE_FLAG_SAFETY_ARMED

    if every("hb", 1.0):
        m.heartbeat_send(mav.MAV_TYPE_QUADROTOR, mav.MAV_AUTOPILOT_ARDUPILOTMEGA, base_mode, mode,
                         mav.MAV_STATE_ACTIVE if armed else mav.MAV_STATE_STANDBY)
    if every("sys", 0.5):
        m.sys_status_send(0x1FFFF, 0x1FFFF, 0x1FFFF, 300, 12350 - int(tt) % 100, 850, 78, 0, 0, 0, 0, 0, 0)
    if every("att", 0.1):
        m.attitude_send(int(tt * 1000), math.radians(12 * math.sin(tt)), math.radians(6 * math.cos(tt * 0.7)),
                        math.radians((tt * 10) % 360), 0.0, 0.0, 0.0)
    if every("gps", 0.2):
        lat = int((39.9334 + 0.0002 * math.sin(tt / 10)) * 1e7)
        lon = int((32.8597 + 0.0002 * math.cos(tt / 10)) * 1e7)
        m.gps_raw_int_send(int(now * 1e6), 3, lat, lon, 900000, 95, 150, 250, 18000, 14, 880000, 1200, 1800, 300, 500000, 0)
        m.global_position_int_send(int(tt * 1000), lat, lon, 900000, 12000, 100, 50, 0, int((tt * 10) % 360 * 100))
        m.vfr_hud_send(2.5, 2.5, int((tt * 10) % 360), 45, 900.0, 0.3)
    if every("servo", 0.1):
        if in_test:
            s = [motor_test_pwm, 1000, 1000, 1000]
        elif armed:
            s = [1500 + int(80 * math.sin(tt * 3 + i)) for i in range(4)]
        else:
            s = [1000, 1000, 1000, 1000]
        m.servo_output_raw_send(int(tt * 1e6), 0, s[0], s[1], s[2], s[3], 1500, 1500, 1100, 1900,
                                0, 0, 0, 0, 0, 0, 0, 0)
    if every("press", 0.5):
        m.scaled_pressure_send(int(tt * 1000), 905.3, 0.0, 2350, 0)
    if every("imu", 0.1):
        m.scaled_imu_send(int(tt * 1000), 0, 0, -1000, 0, 0, 0, 100, 0, -400, 0)
    if every("ekf", 0.5):
        m.ekf_status_report_send((1 << 4) | (1 << 0) | (1 << 2), 0.12, 0.08, 0.10, 0.05, 0.02, 0.1)
    if every("txt", 7.0):
        send_statustext(4, f"Test warning at t={int(tt)}s")
    if magcal_started and every("magcal", 0.5):
        pct = min(100, int((now - magcal_started) / 2.5 * 100))
        mask = [0xFF if b * 8 + 8 <= pct * 80 // 100 else 0 for b in range(10)]
        m.mag_cal_progress_send(0, 1, 2 if pct < 50 else 3, 1, pct, mask, 0.2, -0.5, 0.8)
        if pct >= 100:
            m.mag_cal_report_send(0, 1, 4, 0, 6.5, 12.3, -45.1, 88.2, 1.01, 0.99, 1.0, 0.01, 0.0, 0.02, 0.9, 0, 0, 1.0)
            magcal_started = 0
            send_statustext(6, "Compass calibration done")
    time.sleep(0.01)
