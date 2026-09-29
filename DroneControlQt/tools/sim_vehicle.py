#!/usr/bin/env python3
"""ArduCopter-like MAVLink simulator of Turkay's quad for testing DroneControlQt.

Models the real vehicle:
  * Pixhawk running ArduCopter with the parameters in turkay_copter.param
    (Quad X, FRAME_CLASS=1 FRAME_TYPE=1, SERVO1..4 = Motor1..4, ARMING_CHECK=0)
  * Hubsan Zino Pro Plus body + motors on a T-Motor F55A Pro II 4-in-1 ESC (PWM 1000-2000)
  * 3S 2200 mAh 25C LiPo (open-circuit-voltage curve + internal resistance)

Behaviour follows the parameters: ANGLE_MAX, PILOT_SPEED_UP/DN, PILOT_ACCEL_Z,
PILOT_Y_RATE, THR_DZ, ATC_INPUT_TC, MOT_SPIN_ARM/MIN/MAX, MOT_THST_HOVER,
MOT_THST_EXPO, MOT_PWM_MIN/MAX, BATT_ARM_VOLT, BATT_LOW/CRT_VOLT, BATT_LOW/CRT_MAH,
BATT_CAPACITY, DISARM_DELAY, LAND_SPEED, RTL_ALT, WPNAV_SPEED, BARO1_GND_PRESS.

Sends HEARTBEAT, SYS_STATUS, BATTERY_STATUS, ATTITUDE, GPS_RAW_INT,
GLOBAL_POSITION_INT, VFR_HUD, SERVO_OUTPUT_RAW, SCALED_PRESSURE, SCALED_IMU,
EKF_STATUS_REPORT, STATUSTEXT; answers PARAM_*, COMMAND_LONG (arm/disarm, motor
test, mag cal, preflight cal, message intervals), SET_MODE and MANUAL_CONTROL.

Usage:  python3 sim_vehicle.py [gcs_host] [gcs_port]
        set the app's connection host to 127.0.0.1 when both run on one machine.
Requires: pip install pymavlink
"""
import math
import os
import random
import sys
import time

os.environ["MAVLINK20"] = "1"   # must be set before importing pymavlink

from pymavlink import mavutil                               # noqa: E402
from pymavlink.dialects.v20 import ardupilotmega as mav     # noqa: E402

gcs_host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
gcs_port = int(sys.argv[2]) if len(sys.argv) > 2 else 14550

# ---------------------------------------------------------------------------
# Parameters: load the vehicle's real parameter file

def load_params():
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, "turkay_copter.param"),
        os.path.join(here, "..", "..", "turkay_copter.param"),
    ]
    for path in candidates:
        if os.path.exists(path):
            out = {}
            with open(path) as fh:
                for line in fh:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.replace("\t", ",").split(",")
                    if len(parts) >= 2:
                        try:
                            out[parts[0].strip()] = float(parts[1])
                        except ValueError:
                            pass
            print(f"Loaded {len(out)} parameters from {os.path.normpath(path)}")
            return out
    print("turkay_copter.param not found - using built-in defaults")
    return {
        "ANGLE_MAX": 3000, "PILOT_SPEED_UP": 250, "PILOT_SPEED_DN": 0, "PILOT_ACCEL_Z": 250,
        "PILOT_Y_RATE": 202.5, "THR_DZ": 100, "ATC_INPUT_TC": 0.15, "ARMING_CHECK": 0,
        "MOT_SPIN_ARM": 0.1, "MOT_SPIN_MIN": 0.15, "MOT_SPIN_MAX": 0.95, "MOT_THST_HOVER": 0.35,
        "MOT_THST_EXPO": 0.58, "MOT_PWM_MIN": 1000, "MOT_PWM_MAX": 2000, "BATT_CAPACITY": 4000,
        "BATT_ARM_VOLT": 11, "BATT_LOW_VOLT": 10.8, "BATT_CRT_VOLT": 10.5, "BATT_LOW_MAH": 1000,
        "BATT_CRT_MAH": 500, "DISARM_DELAY": 10, "LAND_SPEED": 50, "RTL_ALT": 1500,
        "WPNAV_SPEED": 1000, "BARO1_GND_PRESS": 91894.84, "FRAME_CLASS": 1, "FRAME_TYPE": 1,
        "SYSID_THISMAV": 1, "FLTMODE1": 0,
    }


params = load_params()


def P(name, default=0.0):
    return params.get(name, default)


# ---------------------------------------------------------------------------
# Physical model constants (Zino Pro Plus airframe on F55A Pro II, 3S 2200 mAh 25C)

MASS_KG = 0.62                 # AUW with the 2200 mAh pack
G = 9.80665
MAX_THRUST_N = MASS_KG * G / max(0.15, P("MOT_THST_HOVER", 0.35))   # hover at MOT_THST_HOVER
DRAG_XY = 0.09                 # ~v^2 drag, ~12 m/s terminal at 30 deg tilt
DRAG_Z = 0.35
IDLE_CURRENT_A = 0.55          # Pixhawk + GPS + telemetry + ESC quiescent
MOTOR_MAX_CURRENT_A = 5.5      # per motor at 100 % throttle (Zino 1806-class motors on 3S)
CELLS = 3
BATTERY_MAH_REAL = 2200.0      # the pack that is actually fitted
PACK_RESISTANCE_OHM = 0.045    # 3S 25C pack incl. connector/ESC leads
BATTERY_START_SOC = 0.97       # starts nearly full
BATTERY_TEMP_C = 28.0

# OCV per cell vs state of charge (LiPo)
OCV_TABLE = [(0.00, 3.00), (0.05, 3.45), (0.10, 3.60), (0.20, 3.68), (0.30, 3.72), (0.40, 3.76),
             (0.50, 3.80), (0.60, 3.85), (0.70, 3.90), (0.80, 3.97), (0.90, 4.06), (1.00, 4.20)]


def ocv_cell(soc):
    soc = max(0.0, min(1.0, soc))
    for (s0, v0), (s1, v1) in zip(OCV_TABLE, OCV_TABLE[1:]):
        if soc <= s1:
            return v0 + (v1 - v0) * (soc - s0) / (s1 - s0)
    return OCV_TABLE[-1][1]


# ---------------------------------------------------------------------------
# Derived vehicle settings

ANGLE_MAX_DEG = P("ANGLE_MAX", 3000) / 100.0
SPEED_UP = P("PILOT_SPEED_UP", 250) / 100.0
SPEED_DN = (P("PILOT_SPEED_DN", 0) or P("PILOT_SPEED_UP", 250)) / 100.0
ACCEL_Z = P("PILOT_ACCEL_Z", 250) / 100.0
YAW_RATE = P("PILOT_Y_RATE", 202.5)
THR_DZ = P("THR_DZ", 100)
INPUT_TC = max(0.02, P("ATC_INPUT_TC", 0.15))
SPIN_ARM = P("MOT_SPIN_ARM", 0.1)
SPIN_MIN = P("MOT_SPIN_MIN", 0.15)
SPIN_MAX = P("MOT_SPIN_MAX", 0.95)
THST_HOVER = P("MOT_THST_HOVER", 0.35)
THST_EXPO = P("MOT_THST_EXPO", 0.58)
PWM_MIN = int(P("MOT_PWM_MIN", 1000))
PWM_MAX = int(P("MOT_PWM_MAX", 2000))
LAND_SPEED = P("LAND_SPEED", 50) / 100.0
LAND_ALT_LOW = P("LAND_ALT_LOW", 1000) / 100.0
WPNAV_SPEED_DN = P("WPNAV_SPEED_DN", 150) / 100.0


def land_rate():
    """Automatic landing: WPNAV_SPEED_DN above LAND_ALT_LOW, LAND_SPEED below it (Copter land_run_vertical_control)."""
    return -(LAND_SPEED if state["alt"] <= LAND_ALT_LOW else max(LAND_SPEED, WPNAV_SPEED_DN))
RTL_ALT = P("RTL_ALT", 1500) / 100.0
RTL_ALT_MAX = max(RTL_ALT, P("RTL_ALT_MAX", 10000) / 100.0)
RTL_LOIT_TIME = P("RTL_LOIT_TIME", 5000) / 1000.0
WPNAV_SPEED = P("WPNAV_SPEED", 1000) / 100.0
DISARM_DELAY = P("DISARM_DELAY", 10)
SYSID = int(P("SYSID_THISMAV", 1))
# Ground pressure from the baro calibration stored on the FC -> home altitude MSL
GND_PRESS_HPA = P("BARO1_GND_PRESS", 91894.84) / 100.0
HOME_ALT_MSL = 44330.0 * (1.0 - (GND_PRESS_HPA / 1013.25) ** 0.190295)
HOME_LAT, HOME_LON = 39.9334, 32.8597

if abs(P("BATT_CAPACITY", 0) - BATTERY_MAH_REAL) > 1:
    print(f"NOTE: BATT_CAPACITY on the FC is {P('BATT_CAPACITY'):.0f} mAh but the fitted pack is "
          f"{BATTERY_MAH_REAL:.0f} mAh - remaining % is computed with BATT_CAPACITY, like the real FC.")

MODE_NAMES = {0: "STABILIZE", 1: "ACRO", 2: "ALT_HOLD", 3: "AUTO", 4: "GUIDED", 5: "LOITER", 6: "RTL",
              7: "CIRCLE", 9: "LAND", 11: "DRIFT", 13: "SPORT", 15: "AUTOTUNE", 16: "POSHOLD", 17: "BRAKE",
              21: "SMART_RTL"}

# ---------------------------------------------------------------------------
# State

conn = mavutil.mavlink_connection(f"udpout:{gcs_host}:{gcs_port}", source_system=SYSID,
                                  source_component=1, input=False)
m = conn.mav

armed = False
mode = int(P("INITIAL_MODE", P("FLTMODE1", 0)))
landed_since = None          # time when landed with throttle low (auto-disarm timer)
motor_test_pwm = 0
motor_test_until = 0.0
magcal_started = 0.0
t0 = time.time()
last = {}
batt_low_reported = False
batt_crt_reported = False

manual = {"x": 0, "y": 0, "z": 0, "r": 0, "t": 0.0}   # last pilot input (MANUAL_CONTROL units, after RC calibration)
rc_pwm = {1: 1500, 2: 1500, 3: 1000, 4: 1500}           # last RC values (for RC_CHANNELS)
rc_seen = False                                          # ArduPilot: failsafe only after RC has ever been seen
RC_OVERRIDE_TIME = P("RC_OVERRIDE_TIME", 3.0)
FS_THR_ENABLE = int(P("FS_THR_ENABLE", 1))
radio_failsafe = False


def rc_norm(ch, pwm):
    """ArduPilot RC_Channel::pwm_to_angle_dz: -1..1 using RCn_MIN/MAX/TRIM/DZ/REVERSED."""
    mn, mx = P(f"RC{ch}_MIN", 1000), P(f"RC{ch}_MAX", 2000)
    trim, dz = P(f"RC{ch}_TRIM", 1500), P(f"RC{ch}_DZ", 0)
    if pwm > trim + dz:
        v = (pwm - (trim + dz)) / max(1.0, mx - (trim + dz))
    elif pwm < trim - dz:
        v = (pwm - (trim - dz)) / max(1.0, (trim - dz) - mn)
    else:
        v = 0.0
    v = max(-1.0, min(1.0, v))
    return -v if P(f"RC{ch}_REVERSED", 0) else v


def rc_range(ch, pwm):
    """ArduPilot RC_Channel::pwm_to_range: 0..1 (throttle) using RCn_MIN/MAX/DZ/REVERSED."""
    mn, mx, dz = P(f"RC{ch}_MIN", 1000), P(f"RC{ch}_MAX", 2000), P(f"RC{ch}_DZ", 0)
    if P(f"RC{ch}_REVERSED", 0):
        pwm = mn + mx - pwm
    v = (pwm - (mn + dz)) / max(1.0, mx - (mn + dz))
    return max(0.0, min(1.0, v))


def apply_rc(ch1, ch2, ch3, ch4):
    """Pilot input arrives as RC PWM (RC_CHANNELS_OVERRIDE, or MANUAL_CONTROL mapped to RC like
    ArduPilot does); calibration and reversal from the parameters are applied here."""
    global rc_seen
    rc_pwm.update({1: ch1, 2: ch2, 3: ch3, 4: ch4})
    roll = rc_norm(1, ch1)
    pitch_in = rc_norm(2, ch2)          # +1 = stick back / high PWM = nose up
    thr = rc_range(3, ch3)
    yaw = rc_norm(4, ch4)
    manual.update(x=int(-pitch_in * 1000), y=int(roll * 1000), z=int(thr * 1000), r=int(yaw * 1000), t=time.time())
    rc_seen = True


if P("RC2_REVERSED", 0):
    print("NOTE: RC2_REVERSED=1 on this vehicle: pitch input is reversed like on the real FC "
          "(RC override / MANUAL_CONTROL 'forward' pitches the nose UP). Check RC2_REVERSED if that is not intended.")

# Mission storage (seq 0 = home like ArduPilot) and the upload/download handshake
mission = []                 # list of dicts: seq, command, frame, lat, lon, alt, p1..p4
mission_rx = {"active": False, "count": 0, "items": [], "next": 0, "sysid": 255, "compid": 190}
nav = {"cur_seq": 0, "target": None, "target_alt": 0.0, "phase": "idle", "reached_t": 0.0,
       "guided_target": None, "guided_alt": 0.0, "guided_takeoff": False,
       "circle_center": None, "circle_angle": 0.0, "home": None,
       "auto_armed": False,   # Copter ap.auto_armed: throttle raised at least once since arming
       "airborne": False}     # has left the ground since arming (for landing-disarm)
WPNAV_RADIUS = P("WPNAV_RADIUS", 200) / 100.0
CIRCLE_RADIUS = P("CIRCLE_RADIUS", 1000) / 100.0
CIRCLE_RATE = P("CIRCLE_RATE", 20)

state = {
    "roll": 0.0, "pitch": 0.0, "heading": 0.0,        # deg
    "roll_rate": 0.0, "pitch_rate": 0.0, "yaw_rate": 0.0,   # deg/s
    "lat": HOME_LAT, "lon": HOME_LON,
    "alt": 0.0, "vz": 0.0,                            # m AGL, m/s up
    "vn": 0.0, "ve": 0.0,                             # m/s
    "hold_alt": 0.0,
    "thrust": 0.0,                                    # 0..1 collective demand
    "motors": [PWM_MIN] * 4,
    "rtl_phase": 0,
    "soc": BATTERY_START_SOC, "consumed_mah": 0.0, "current": 0.0, "voltage": 0.0,
    "load": 0.0,
}


def every(key, period):
    now = time.time()
    if now - last.get(key, 0) >= period:
        last[key] = now
        return True
    return False


def send_statustext(sev, text):
    print(f"  [{['EMERG', 'ALERT', 'CRIT', 'ERROR', 'WARN', 'NOTICE', 'INFO', 'DEBUG'][sev]}] {text}")
    m.statustext_send(sev, text.encode()[:50])


def send_param(name):
    names = sorted(params)
    m.param_value_send(name.encode(), params[name], mav.MAV_PARAM_TYPE_REAL32, len(names), names.index(name))


def recv():
    """recv_match that survives ICMP-induced resets (Windows WinError 10054)."""
    try:
        return conn.recv_match(blocking=False)
    except ConnectionResetError:
        return None


def param_name(msg):
    pid = msg.param_id
    if isinstance(pid, bytes):
        pid = pid.decode(errors="ignore")
    return pid.split("\0")[0]


# ---------------------------------------------------------------------------
# Motors / thrust

def thrust_to_throttle(t):
    """Inverse of ArduPilot's thrust linearisation (MOT_THST_EXPO)."""
    t = max(0.0, min(1.0, t))
    if THST_EXPO < 0.001:
        return t
    a = THST_EXPO
    return ((a - 1.0) + math.sqrt((1.0 - a) ** 2 + 4.0 * a * t)) / (2.0 * a)


def throttle_to_pwm(thr):
    """0..1 throttle -> PWM within MOT_SPIN_MIN..MOT_SPIN_MAX."""
    spin = SPIN_MIN + (SPIN_MAX - SPIN_MIN) * max(0.0, min(1.0, thr))
    return int(round(PWM_MIN + (PWM_MAX - PWM_MIN) * spin))


def stick_throttle_to_thrust(z):
    """Stabilize throttle: stick mid (with THR_DZ) = hover, ends = 0 / full."""
    mid = 500.0
    if abs(z - mid) <= THR_DZ:
        return THST_HOVER
    if z < mid:
        return THST_HOVER * (z / (mid - THR_DZ))
    return THST_HOVER + (1.0 - THST_HOVER) * ((z - mid - THR_DZ) / (mid - THR_DZ))


def climb_demand(z):
    """AltHold-type modes: stick -> climb rate (PILOT_SPEED_UP/DN, THR_DZ)."""
    mid = 500.0
    if abs(z - mid) <= THR_DZ:
        return 0.0
    if z > mid:
        return SPEED_UP * (z - mid - THR_DZ) / (mid - THR_DZ)
    return -SPEED_DN * (mid - THR_DZ - z) / (mid - THR_DZ)


def mix_motors(thrust, roll_err, pitch_err, yaw_cmd):
    """Quad X mixer. M1 FR CCW, M2 RL CCW, M3 FL CW, M4 RR CW (ArduPilot order)."""
    r = roll_err / ANGLE_MAX_DEG * 0.12
    p = pitch_err / ANGLE_MAX_DEG * 0.12
    y = yaw_cmd * 0.06
    mixes = [
        thrust - r + p + y,   # M1 front right
        thrust + r - p + y,   # M2 rear left
        thrust + r + p - y,   # M3 front left
        thrust - r - p - y,   # M4 rear right
    ]
    return [throttle_to_pwm(thrust_to_throttle(v)) for v in mixes]


# ---------------------------------------------------------------------------
# Dynamics

def body_velocity():
    h = math.radians(state["heading"])
    vf = state["vn"] * math.cos(h) + state["ve"] * math.sin(h)
    vr = -state["vn"] * math.sin(h) + state["ve"] * math.cos(h)
    return vf, vr


def rtl_step():
    """ArduCopter RTL: climb to max(current alt, RTL_ALT) (capped by RTL_ALT_MAX), fly home at
    WPNAV_SPEED, hover RTL_LOIT_TIME over home, then descend at LAND_SPEED and land."""
    st = state
    hlat, hlon = nav["home"] if nav["home"] else (HOME_LAT, HOME_LON)
    dn = (hlat - st["lat"]) * 111320.0
    de = (hlon - st["lon"]) * 111320.0 * math.cos(math.radians(st["lat"]))
    dist = math.hypot(dn, de)
    if st.get("rtl_alt") is None:                  # ModeRTL::compute_return_target()
        st["rtl_alt"] = min(RTL_ALT_MAX, max(RTL_ALT, st["alt"]))
        if dist < 2.0:                             # already over home: just descend and land
            st["rtl_alt"] = st["alt"]
    ralt = st["rtl_alt"]
    if st["rtl_phase"] == 0:                       # climb (position held)
        if st["alt"] >= ralt - 0.3 or dist < 2.0:
            st["rtl_phase"] = 1
        r, p, _ = fly_towards(st["lat"], st["lon"], 2.0) if dist >= 2.0 else fly_towards(hlat, hlon, 2.0)
        return r, p, max(0.0, min(SPEED_UP, (ralt - st["alt"]) * 1.0)), 0.0
    if st["rtl_phase"] == 1:                       # fly home at return altitude
        if dist < 1.5:
            st["rtl_phase"] = 2
            st["rtl_loiter_until"] = time.time() + RTL_LOIT_TIME
            send_statustext(6, "RTL: reached home, loitering")
        want = min(WPNAV_SPEED, dist * 0.8)
        wn, we = (dn / dist * want, de / dist * want) if dist > 0.1 else (0.0, 0.0)
        h = math.radians(st["heading"])
        ef = (wn - st["vn"]) * math.cos(h) + (we - st["ve"]) * math.sin(h)
        er = -(wn - st["vn"]) * math.sin(h) + (we - st["ve"]) * math.cos(h)
        vz = max(-SPEED_DN, min(SPEED_UP, (ralt - st["alt"])))
        lim = ANGLE_MAX_DEG
        return max(-lim, min(lim, er * 6.0)), max(-lim, min(lim, -ef * 6.0)), vz, yaw_towards(hlat, hlon)
    if st["rtl_phase"] == 2:                       # loiter over home (RTL_LOIT_TIME)
        r, p, _ = fly_towards(hlat, hlon, 2.0)
        if time.time() >= st["rtl_loiter_until"]:
            st["rtl_phase"] = 3
            send_statustext(6, "RTL: landing")
        return r, p, alt_rate_to(ralt), 0.0
    r, p, _ = fly_towards(hlat, hlon, 2.0)         # land, holding position over home
    return r, p, land_rate(), 0.0


def ne_offset(lat, lon):
    """North/east metres of (lat, lon) from the vehicle."""
    st = state
    dn = (lat - st["lat"]) * 111320.0
    de = (lon - st["lon"]) * 111320.0 * math.cos(math.radians(st["lat"]))
    return dn, de


def fly_towards(lat, lon, speed_limit):
    """Position controller: returns (roll, pitch) targets that fly to lat/lon."""
    st = state
    dn, de = ne_offset(lat, lon)
    dist = math.hypot(dn, de)
    want = min(speed_limit, dist * 0.7)
    wn, we = (dn / dist * want, de / dist * want) if dist > 0.05 else (0.0, 0.0)
    h = math.radians(st["heading"])
    ef = (wn - st["vn"]) * math.cos(h) + (we - st["ve"]) * math.sin(h)
    er = -(wn - st["vn"]) * math.sin(h) + (we - st["ve"]) * math.cos(h)
    lim = ANGLE_MAX_DEG
    return max(-lim, min(lim, er * 6.0)), max(-lim, min(lim, -ef * 6.0)), dist


def yaw_towards(lat, lon, min_dist=3.0):
    """Yaw-rate command turning the nose to (lat, lon) (WP_YAW_BEHAVIOR = look at next WP)."""
    dn, de = ne_offset(lat, lon)
    if math.hypot(dn, de) < min_dist:
        return 0.0
    want = math.degrees(math.atan2(de, dn)) % 360.0
    err = (want - state["heading"] + 540.0) % 360.0 - 180.0
    return max(-YAW_RATE, min(YAW_RATE, err * 2.5))


def alt_rate_to(alt_target):
    return max(-SPEED_DN, min(SPEED_UP, (alt_target - state["alt"]) * 1.0))


def mission_nav_items():
    return [it for it in mission if it["seq"] > 0]


def auto_step():
    """AUTO: run the uploaded mission. Returns (roll, pitch, vz_target, yaw_rate)."""
    st = state
    items = {it["seq"]: it for it in mission}
    if len(mission) < 2:
        return 0.0, 0.0, 0.0, 0.0
    if nav["cur_seq"] < 1:
        set_current_seq(1)
    it = items.get(nav["cur_seq"])
    if it is None:                                  # past the end: hold position (ArduPilot loiters)
        r, p, _ = fly_towards(nav["hold_lat"], nav["hold_lon"], 2.0) if nav.get("hold_lat") else (0.0, 0.0, 0.0)
        return r, p, alt_rate_to(nav["target_alt"]), 0.0
    cmd = it["command"]
    if cmd == mav.MAV_CMD_NAV_TAKEOFF:
        nav["target_alt"] = it["alt"]
        if st["alt"] >= it["alt"] - 0.5:
            reached_and_next(it)
        return 0.0, 0.0, alt_rate_to(it["alt"]), 0.0
    if cmd in (mav.MAV_CMD_NAV_WAYPOINT, mav.MAV_CMD_NAV_SPLINE_WAYPOINT, mav.MAV_CMD_NAV_LOITER_TIME,
               mav.MAV_CMD_NAV_LOITER_UNLIM):
        nav["target_alt"] = it["alt"] if it["alt"] > 0 else nav["target_alt"]
        r, p, dist = fly_towards(it["lat"], it["lon"], WPNAV_SPEED)
        yaw = yaw_towards(it["lat"], it["lon"])
        if dist < max(WPNAV_RADIUS, it["p2"] if it["p2"] > 0 else 0):
            if cmd == mav.MAV_CMD_NAV_LOITER_UNLIM:
                return r, p, alt_rate_to(nav["target_alt"]), 0.0
            if nav["reached_t"] == 0.0:
                nav["reached_t"] = time.time()
                m.mission_item_reached_send(it["seq"])
                send_statustext(6, f"Reached command #{it['seq']}")
            delay = it["p1"] if cmd in (mav.MAV_CMD_NAV_WAYPOINT, mav.MAV_CMD_NAV_LOITER_TIME) else 0.0
            if time.time() - nav["reached_t"] >= delay:
                nav["reached_t"] = 0.0
                advance_mission(it)
        return r, p, alt_rate_to(nav["target_alt"]), yaw
    if cmd == mav.MAV_CMD_NAV_RETURN_TO_LAUNCH:
        nav["phase"] = "rtl"
        return rtl_step()
    if cmd == mav.MAV_CMD_NAV_LAND:
        if it["lat"] != 0 or it["lon"] != 0:
            r, p, dist = fly_towards(it["lat"], it["lon"], WPNAV_SPEED)
            if dist > 1.0:
                return r, p, alt_rate_to(nav["target_alt"]), 0.0
        return 0.0, 0.0, land_rate(), 0.0
    # unsupported command: skip it
    advance_mission(it)
    return 0.0, 0.0, alt_rate_to(nav["target_alt"]), 0.0


def reached_and_next(it):
    m.mission_item_reached_send(it["seq"])
    send_statustext(6, f"Reached command #{it['seq']}")
    advance_mission(it)


def advance_mission(it):
    nxt = it["seq"] + 1
    seqs = [x["seq"] for x in mission]
    if nxt in seqs:
        set_current_seq(nxt)
    else:
        send_statustext(6, "Mission complete")
        nav["hold_lat"], nav["hold_lon"] = state["lat"], state["lon"]
        nav["cur_seq"] = nxt          # past the end -> hold


def set_current_seq(seq):
    nav["cur_seq"] = seq
    nav["reached_t"] = 0.0
    m.mission_current_send(seq)


def guided_step():
    """GUIDED: takeoff, then hold / fly to the last position target."""
    st = state
    if nav["guided_takeoff"]:
        if st["alt"] >= nav["guided_alt"] - 0.3:
            nav["guided_takeoff"] = False
            send_statustext(6, "Takeoff complete")
        return 0.0, 0.0, alt_rate_to(nav["guided_alt"]), 0.0
    if nav["guided_target"] is not None:
        lat, lon = nav["guided_target"]
        r, p, dist = fly_towards(lat, lon, WPNAV_SPEED)
        return r, p, alt_rate_to(nav["guided_alt"]), yaw_towards(lat, lon)
    # no target: hold position
    if nav.get("hold_lat"):
        r, p, _ = fly_towards(nav["hold_lat"], nav["hold_lon"], 2.0)
        return r, p, alt_rate_to(nav["target_alt"]), 0.0
    return 0.0, 0.0, 0.0, 0.0


def circle_step(dt):
    """CIRCLE: orbit the centre captured at mode entry (CIRCLE_RADIUS, CIRCLE_RATE)."""
    if nav["circle_center"] is None:
        # centre is CIRCLE_RADIUS ahead of the vehicle, like ArduPilot
        h = math.radians(state["heading"])
        clat = state["lat"] + CIRCLE_RADIUS * math.cos(h) / 111320.0
        clon = state["lon"] + CIRCLE_RADIUS * math.sin(h) / (111320.0 * math.cos(math.radians(state["lat"])))
        nav["circle_center"] = (clat, clon)
        nav["circle_angle"] = math.degrees(h) + 180.0
        nav["target_alt"] = state["alt"]
    nav["circle_angle"] += CIRCLE_RATE * dt
    a = math.radians(nav["circle_angle"])
    clat, clon = nav["circle_center"]
    tlat = clat + CIRCLE_RADIUS * math.cos(a) / 111320.0
    tlon = clon + CIRCLE_RADIUS * math.sin(a) / (111320.0 * math.cos(math.radians(clat)))
    r, p, _ = fly_towards(tlat, tlon, WPNAV_SPEED)
    # yaw towards the centre
    dn, de = ne_offset(clat, clon)
    want_hdg = math.degrees(math.atan2(de, dn)) % 360.0
    err = (want_hdg - state["heading"] + 540.0) % 360.0 - 180.0
    return r, p, alt_rate_to(nav["target_alt"]), max(-YAW_RATE, min(YAW_RATE, err * 2.0))


def radio_failsafe_check(now, fresh):
    """FS_THR_ENABLE: no pilot input for RC_OVERRIDE_TIME while armed -> Radio Failsafe (RTL / land / disarm)."""
    global radio_failsafe, armed, mode
    if not rc_seen or not FS_THR_ENABLE:
        return
    if armed and not fresh and not radio_failsafe:
        radio_failsafe = True
        if state["alt"] > 0.5 and mode not in (6, 9, 21, 3):
            send_statustext(2, "Radio Failsafe")
            print(f"RADIO FAILSAFE: no pilot input for {RC_OVERRIDE_TIME:.0f}s while flying -> RTL")
            mode = 6                                  # FS_THR_ENABLE=1 -> RTL
            enter_mode()
        elif state["alt"] <= 0.5:
            send_statustext(2, "Radio Failsafe - Disarming")
            armed = False
            nav["auto_armed"] = False
            nav["airborne"] = False
            print(f"DISARMED (radio failsafe): no RC_CHANNELS_OVERRIDE/MANUAL_CONTROL for {RC_OVERRIDE_TIME:.0f}s on the ground")
        else:
            send_statustext(2, "Radio Failsafe")
    elif radio_failsafe and fresh:
        radio_failsafe = False
        send_statustext(6, "Radio Failsafe Cleared")


def update_dynamics(dt):
    global armed, landed_since
    st = state
    now = time.time()
    fresh = now - manual["t"] < RC_OVERRIDE_TIME
    radio_failsafe_check(now, fresh)
    sx = manual["x"] / 1000.0 if fresh else 0.0     # pitch stick, +forward
    sy = manual["y"] / 1000.0 if fresh else 0.0     # roll stick, +right
    sz = manual["z"] if fresh else 0.0              # throttle 0..1000
    sr = manual["r"] / 1000.0 if fresh else 0.0     # yaw stick, +right
    on_ground = st["alt"] <= 0.001

    if now < motor_test_until:
        st["motors"] = [motor_test_pwm, PWM_MIN, PWM_MIN, PWM_MIN]
        return

    tgt_roll = tgt_pitch = 0.0
    yaw_rate_cmd = 0.0
    if not armed:
        st["motors"] = [PWM_MIN] * 4
        st["thrust"] = 0.0
    else:
        # ---- lateral / yaw command by mode ----
        tgt_roll = sy * ANGLE_MAX_DEG
        tgt_pitch = -sx * ANGLE_MAX_DEG       # stick forward = nose down = negative pitch
        yaw_rate_cmd = sr * YAW_RATE
        vz_target = None

        if mode in (5, 16, 17) and abs(sx) < 0.02 and abs(sy) < 0.02 and not on_ground:
            # Loiter / PosHold / Brake with centred sticks: hold the captured position
            if nav.get("hold_lat") is None:
                nav["hold_lat"], nav["hold_lon"] = st["lat"], st["lon"]
            tgt_roll, tgt_pitch, _ = fly_towards(nav["hold_lat"], nav["hold_lon"], 3.0)
        elif mode in (5, 16, 17):
            nav["hold_lat"] = None
        if mode == 9:                                        # LAND: descend, hold position with centred sticks
            vz_target = land_rate()
            if abs(sx) < 0.02 and abs(sy) < 0.02 and not on_ground:
                if nav.get("hold_lat") is None:
                    nav["hold_lat"], nav["hold_lon"] = st["lat"], st["lon"]
                tgt_roll, tgt_pitch, _ = fly_towards(nav["hold_lat"], nav["hold_lon"], 3.0)
            else:
                nav["hold_lat"] = None
        if mode in (6, 21):                                  # RTL / Smart RTL
            tgt_roll, tgt_pitch, vz_target, yaw_rate_cmd = rtl_step()
        if mode == 3:                                        # AUTO
            tgt_roll, tgt_pitch, vz_target, yaw_rate_cmd = auto_step()
        if mode == 4:                                        # GUIDED
            tgt_roll, tgt_pitch, vz_target, yaw_rate_cmd = guided_step()
        if mode == 7:                                        # CIRCLE
            tgt_roll, tgt_pitch, vz_target, yaw_rate_cmd = circle_step(dt)

        # ---- vertical command by mode ----
        if mode in (0, 1, 13):                               # Stabilize / Acro / Sport: direct throttle
            thrust = stick_throttle_to_thrust(sz)
        else:                                                # altitude-controlled modes
            if vz_target is None:
                vz_target = climb_demand(sz)
                if abs(vz_target) < 0.01 and not on_ground:
                    vz_target = max(-SPEED_DN, min(SPEED_UP, (st["hold_alt"] - st["alt"]) * 1.0))
                else:
                    st["hold_alt"] = st["alt"]
            acc = max(-ACCEL_Z, min(ACCEL_Z, (vz_target - st["vz"]) * 2.5))
            thrust = THST_HOVER * (1.0 + acc / G) + DRAG_Z * st["vz"] * abs(st["vz"]) / (MASS_KG * G) * THST_HOVER
            if on_ground:
                # Landed (land_complete): ArduCopter keeps the motors at ground idle (MOT_SPIN_MIN)
                # until a positive climb is demanded - pilot throttle above mid + deadzone, a
                # GUIDED/AUTO takeoff or the RTL climb. Otherwise it never "hovers" on the ground.
                if vz_target is None or vz_target <= 0.05 or mode in (9,):
                    thrust = 0.0
                else:
                    thrust = max(thrust, THST_HOVER * 1.08)      # break ground contact
                    auto_armed_set()
        thrust = max(0.0, min(1.0, thrust))
        if mode in (0, 1, 13) and thrust > 0.02:
            auto_armed_set()

        if on_ground and thrust < THST_HOVER * 0.95:
            # on the ground, not enough thrust to lift: motors idle (MOT_SPIN_ARM / MIN)
            st["thrust"] = 0.0
            if mode in (0, 1, 13) and thrust > 0.02:
                st["motors"] = mix_motors(thrust, 0.0, 0.0, sr)     # manual throttle: motors follow the stick
            else:
                spin = SPIN_MIN if nav["auto_armed"] else SPIN_ARM
                st["motors"] = [int(PWM_MIN + (PWM_MAX - PWM_MIN) * spin)] * 4
            tgt_roll = tgt_pitch = 0.0
            yaw_rate_cmd = 0.0
        else:
            st["thrust"] = thrust

    # ---- attitude: first order response (ATC_INPUT_TC) ----
    a = min(1.0, dt / INPUT_TC)
    old_roll, old_pitch = st["roll"], st["pitch"]
    st["roll"] += (tgt_roll - st["roll"]) * a
    st["pitch"] += (tgt_pitch - st["pitch"]) * a
    st["roll_rate"] = (st["roll"] - old_roll) / dt if dt > 0 else 0.0
    st["pitch_rate"] = (st["pitch"] - old_pitch) / dt if dt > 0 else 0.0
    st["yaw_rate"] += (yaw_rate_cmd - st["yaw_rate"]) * a
    if st["thrust"] > 0 or not on_ground:
        st["heading"] = (st["heading"] + st["yaw_rate"] * dt) % 360.0
    else:
        st["yaw_rate"] = 0.0

    # ---- forces ----
    if armed and st["thrust"] > 0:
        thrust_n = st["thrust"] * MAX_THRUST_N
        cr, cp = math.cos(math.radians(st["roll"])), math.cos(math.radians(st["pitch"]))
        az = thrust_n * cr * cp / MASS_KG - G - DRAG_Z * st["vz"] * abs(st["vz"]) / MASS_KG
        ax_body = -thrust_n * math.sin(math.radians(st["pitch"])) / MASS_KG   # nose down -> forward
        ay_body = thrust_n * math.sin(math.radians(st["roll"])) / MASS_KG     # roll right -> right
        h = math.radians(st["heading"])
        an = ax_body * math.cos(h) - ay_body * math.sin(h)
        ae = ax_body * math.sin(h) + ay_body * math.cos(h)
        spd = math.hypot(st["vn"], st["ve"])
        an -= DRAG_XY * spd * st["vn"] / MASS_KG
        ae -= DRAG_XY * spd * st["ve"] / MASS_KG
    else:
        az = -G if st["alt"] > 0 else 0.0
        an = -st["vn"] * 3.0
        ae = -st["ve"] * 3.0

    st["vz"] += az * dt
    st["alt"] += st["vz"] * dt
    if st["alt"] <= 0.0:
        st["alt"] = 0.0
        if st["vz"] < -2.0:
            send_statustext(4, "Hard landing")
        st["vz"] = 0.0
        st["vn"] *= max(0.0, 1.0 - 8.0 * dt)
        st["ve"] *= max(0.0, 1.0 - 8.0 * dt)
        st["roll"] *= max(0.0, 1.0 - 5.0 * dt)
        st["pitch"] *= max(0.0, 1.0 - 5.0 * dt)
    else:
        st["vn"] += an * dt
        st["ve"] += ae * dt
    st["lat"] += st["vn"] * dt / 111320.0
    st["lon"] += st["ve"] * dt / (111320.0 * math.cos(math.radians(st["lat"])))

    # ---- motors from thrust + attitude error ----
    if armed and st["thrust"] > 0:
        st["motors"] = mix_motors(st["thrust"], tgt_roll - st["roll"], tgt_pitch - st["pitch"], sr)
        if not on_ground:   # rate-loop corrections / gusts: real outputs jitter a few us around the mix
            st["motors"] = [max(PWM_MIN, min(PWM_MAX, int(round(pwm + random.gauss(0.0, 5.0))))) for pwm in st["motors"]]

    if armed and st["alt"] > 0.3:
        nav["airborne"] = True

    # ---- auto-disarm, as Copter::auto_disarm_check() ----
    # * landed with the throttle stick at zero for DISARM_DELAY seconds (any mode), or
    # * touched down after an automatic landing (LAND / RTL / AUTO land, GUIDED land): ~1 s.
    # Throttle at mid stick (MCC's centre in AltHold/Loiter) does NOT disarm - only stick zero does.
    throttle_zero = sz <= 25 or not fresh
    auto_landing = nav["airborne"] and (mode in (9, 6, 21) or (mode == 3 and nav["phase"] == "rtl"))
    if armed and st["alt"] <= 0.001 and st["thrust"] <= 0.0 and (throttle_zero or auto_landing):
        if landed_since is None:
            landed_since = now
        elif now - landed_since > (1.0 if auto_landing else DISARM_DELAY):
            armed = False
            landed_since = None
            nav["auto_armed"] = False
            nav["airborne"] = False
            send_statustext(6, "Disarming motors" if not auto_landing else "Landed, disarming motors")
            print("DISARMED (auto): " + ("landed after %s" % MODE_NAMES.get(mode, mode) if auto_landing
                                          else "throttle at zero on the ground for DISARM_DELAY=%.0fs" % DISARM_DELAY))
    else:
        landed_since = None


def auto_armed_set():
    """Copter 'auto_armed': set the first time the pilot/auto raises throttle after arming."""
    if not nav["auto_armed"]:
        nav["auto_armed"] = True


# ---------------------------------------------------------------------------
# Battery

def fc_remaining_mah():
    return P("BATT_CAPACITY", BATTERY_MAH_REAL) - state["consumed_mah"]


def fc_remaining_pct():
    cap = P("BATT_CAPACITY", BATTERY_MAH_REAL)
    return int(max(0, min(100, round(100.0 * fc_remaining_mah() / cap)))) if cap > 0 else 0


def update_battery(dt):
    global batt_low_reported, batt_crt_reported, mode
    st = state
    motor_current = 0.0
    for pwm in st["motors"]:
        frac = max(0.0, min(1.0, (pwm - PWM_MIN) / float(PWM_MAX - PWM_MIN)))
        motor_current += MOTOR_MAX_CURRENT_A * frac ** 1.7
    current = IDLE_CURRENT_A + motor_current
    st["current"] = current
    st["consumed_mah"] += current * dt / 3600.0 * 1000.0
    st["soc"] = max(0.0, BATTERY_START_SOC - st["consumed_mah"] / BATTERY_MAH_REAL)
    st["voltage"] = max(0.0, CELLS * ocv_cell(st["soc"]) - current * PACK_RESISTANCE_OHM)
    st["load"] = min(1.0, 0.25 + 0.5 * (motor_current / (4 * MOTOR_MAX_CURRENT_A)))

    # battery failsafe as the FC raises it: BATT_FS_LOW_ACT / BATT_FS_CRT_ACT (0 none, 1 Land, 2 RTL, 3 SmartRTL, 4 SmartRTL/Land, 5 Terminate)
    if armed:
        low_v = st["voltage"] < P("BATT_LOW_VOLT", 10.8)
        low_mah = P("BATT_LOW_MAH", 0) > 0 and fc_remaining_mah() < P("BATT_LOW_MAH", 0)
        crt_v = st["voltage"] < P("BATT_CRT_VOLT", 10.5)
        crt_mah = P("BATT_CRT_MAH", 0) > 0 and fc_remaining_mah() < P("BATT_CRT_MAH", 0)
        if (crt_v or crt_mah) and not batt_crt_reported:
            send_statustext(2, "Battery 1 is critical %.2fV used %.0f mAh" % (st["voltage"], st["consumed_mah"]))
            batt_crt_reported = True
            battery_failsafe_action(int(P("BATT_FS_CRT_ACT", 0)))
        elif (low_v or low_mah) and not batt_low_reported:
            send_statustext(4, "Battery 1 is low %.2fV used %.0f mAh" % (st["voltage"], st["consumed_mah"]))
            batt_low_reported = True
            battery_failsafe_action(int(P("BATT_FS_LOW_ACT", 0)))


def battery_failsafe_action(act):
    global mode
    new = {1: 9, 2: 6, 3: 21, 4: 21}.get(act)
    if new is None or state["alt"] <= 0.3 or mode in (9, 6, 21):
        return
    send_statustext(2, "Battery Failsafe - " + MODE_NAMES.get(new, str(new)))
    print(f"BATTERY FAILSAFE -> {MODE_NAMES.get(new, new)}")
    mode = new
    enter_mode()


def enter_mode():
    state["rtl_phase"] = 0
    state["rtl_alt"] = None
    state["hold_alt"] = state["alt"]
    nav["hold_lat"] = None
    nav["circle_center"] = None
    nav["guided_target"] = None
    nav["guided_takeoff"] = False
    nav["phase"] = "idle"
    nav["target_alt"] = state["alt"]
    if mode == 4:
        nav["hold_lat"], nav["hold_lon"] = state["lat"], state["lon"]
    print(f"MODE -> {MODE_NAMES.get(mode, mode)}")
    send_statustext(6, f"Flight mode = {MODE_NAMES.get(mode, mode)}")


def send_home():
    hlat, hlon = nav["home"] if nav["home"] else (HOME_LAT, HOME_LON)
    m.home_position_send(int(hlat * 1e7), int(hlon * 1e7), int(HOME_ALT_MSL * 1000), 0, 0, 0,
                         [1, 0, 0, 0], 0, 0, 0, int(time.time() * 1e6))


# ---------------------------------------------------------------------------
# Message handling

def handle(msg):
    global armed, mode, motor_test_pwm, motor_test_until, magcal_started
    t = msg.get_type()
    if t == "MANUAL_CONTROL":
        # ArduPilot converts MANUAL_CONTROL into RC overrides:
        #   roll = 1500 + y/2, pitch = 1500 - x/2, throttle = 1000 + z, yaw = 1500 + r/2
        apply_rc(1500 + msg.y / 2.0, 1500 - msg.x / 2.0, 1000 + msg.z, 1500 + msg.r / 2.0)
    elif t == "RC_CHANNELS_OVERRIDE":
        cur = dict(rc_pwm)
        vals = [msg.chan1_raw, msg.chan2_raw, msg.chan3_raw, msg.chan4_raw]
        for i, v in enumerate(vals, start=1):
            if v != 0 and v != 65535:          # 0 / UINT16_MAX = leave the channel alone
                cur[i] = v
        apply_rc(cur[1], cur[2], cur[3], cur[4])
    elif t == "REQUEST_DATA_STREAM":
        pass                                    # streams are always on in the simulator
    elif t == "PARAM_REQUEST_LIST":
        print("PARAM_REQUEST_LIST")
        for n in sorted(params):
            send_param(n)
    elif t == "PARAM_REQUEST_READ":
        name = param_name(msg)
        if name in params:
            send_param(name)
    elif t == "PARAM_SET":
        name = param_name(msg)
        params[name] = msg.param_value
        print(f"PARAM_SET {name} = {msg.param_value}")
        send_param(name)
    elif t == "SET_MODE":
        new_mode = msg.custom_mode
        if new_mode != mode:
            if new_mode == 3 and len(mission) < 2:
                send_statustext(3, "Mode change to AUTO failed: no mission")
                return
            mode = new_mode
            enter_mode()
    elif t == "MISSION_COUNT":
        mission_rx.update(active=True, count=msg.count, items=[], next=0,
                          sysid=msg.get_srcSystem(), compid=msg.get_srcComponent())
        print(f"MISSION upload: {msg.count} items")
        if msg.count == 0:
            mission.clear()
            m.mission_ack_send(mission_rx["sysid"], mission_rx["compid"], mav.MAV_MISSION_ACCEPTED, mav.MAV_MISSION_TYPE_MISSION)
            mission_rx["active"] = False
        else:
            m.mission_request_int_send(mission_rx["sysid"], mission_rx["compid"], 0, mav.MAV_MISSION_TYPE_MISSION)
    elif t in ("MISSION_ITEM_INT", "MISSION_ITEM"):
        if not mission_rx["active"] or msg.seq != mission_rx["next"]:
            return
        scale = 1e7 if t == "MISSION_ITEM_INT" else 1.0
        mission_rx["items"].append({"seq": msg.seq, "command": msg.command, "frame": msg.frame,
                                    "lat": msg.x / scale, "lon": msg.y / scale, "alt": float(msg.z),
                                    "p1": msg.param1, "p2": msg.param2, "p3": msg.param3, "p4": msg.param4})
        mission_rx["next"] += 1
        if mission_rx["next"] < mission_rx["count"]:
            m.mission_request_int_send(mission_rx["sysid"], mission_rx["compid"], mission_rx["next"], mav.MAV_MISSION_TYPE_MISSION)
        else:
            mission[:] = mission_rx["items"]
            mission_rx["active"] = False
            m.mission_ack_send(mission_rx["sysid"], mission_rx["compid"], mav.MAV_MISSION_ACCEPTED, mav.MAV_MISSION_TYPE_MISSION)
            nav["cur_seq"] = 0
            print(f"MISSION stored: {len(mission)} items: " + ", ".join(f"#{it['seq']} cmd{it['command']}" for it in mission))
            send_statustext(6, f"Mission: {len(mission) - 1} commands received")
    elif t == "MISSION_REQUEST_LIST":
        m.mission_count_send(msg.get_srcSystem(), msg.get_srcComponent(), len(mission), mav.MAV_MISSION_TYPE_MISSION)
    elif t in ("MISSION_REQUEST_INT", "MISSION_REQUEST"):
        for it in mission:
            if it["seq"] == msg.seq:
                m.mission_item_int_send(msg.get_srcSystem(), msg.get_srcComponent(), it["seq"], it["frame"], it["command"],
                                        1 if it["seq"] == nav["cur_seq"] else 0, 1, it["p1"], it["p2"], it["p3"], it["p4"],
                                        int(it["lat"] * 1e7), int(it["lon"] * 1e7), it["alt"], mav.MAV_MISSION_TYPE_MISSION)
                break
    elif t == "MISSION_ACK":
        pass
    elif t == "MISSION_CLEAR_ALL":
        mission.clear()
        nav["cur_seq"] = 0
        m.mission_ack_send(msg.get_srcSystem(), msg.get_srcComponent(), mav.MAV_MISSION_ACCEPTED, mav.MAV_MISSION_TYPE_MISSION)
        send_statustext(6, "Mission cleared")
    elif t == "MISSION_SET_CURRENT":
        set_current_seq(msg.seq)
    elif t == "SET_POSITION_TARGET_GLOBAL_INT":
        if mode == 4:
            nav["guided_target"] = (msg.lat_int / 1e7, msg.lon_int / 1e7)
            nav["guided_alt"] = msg.alt if msg.alt > 0 else max(nav["guided_alt"], state["alt"])
            nav["guided_takeoff"] = False
            print(f"GUIDED goto {nav['guided_target']} alt {nav['guided_alt']:.1f}")
        else:
            send_statustext(4, "Position target ignored: not in GUIDED")
    elif t == "COMMAND_LONG":
        cmd = msg.command
        result = mav.MAV_RESULT_ACCEPTED
        if cmd == mav.MAV_CMD_COMPONENT_ARM_DISARM:
            want = msg.param1 > 0.5
            forced = msg.param2 == 21196
            if want and not armed:
                if state["voltage"] < P("BATT_ARM_VOLT", 11.0) and not forced:
                    send_statustext(3, "PreArm: Battery 1 below minimum arming voltage")
                    result = mav.MAV_RESULT_FAILED
                elif mode in (6, 9, 21) and not forced:
                    send_statustext(3, "Arm: Mode not armable")
                    result = mav.MAV_RESULT_FAILED
                else:
                    armed = True
                    landed_since = None
                    nav["auto_armed"] = False
                    nav["airborne"] = state["alt"] > 0.3
                    if state["alt"] <= 0.3:
                        nav["home"] = (state["lat"], state["lon"])   # home is (re)set when arming on the ground
                        send_home()
                    else:
                        send_statustext(4, "Armed in the air (forced)")
                    nav["hold_lat"] = None
                    nav["guided_target"] = None
                    nav["guided_takeoff"] = False
                    send_statustext(6, "Arming motors")
                    print("ARMED" + (" (forced)" if forced else "") + f" in {MODE_NAMES.get(mode, mode)}")
            elif not want and armed:
                if state["alt"] > 0.5 and not forced:
                    send_statustext(3, "Disarm: vehicle is flying")
                    result = mav.MAV_RESULT_FAILED
                else:
                    armed = False
                    landed_since = None
                    nav["auto_armed"] = False
                    nav["airborne"] = False
                    send_statustext(6, "Disarming motors")
                    print("DISARMED (GCS command)" + (" while FLYING at %.0f m - forced, vehicle falls" % state["alt"]
                                                     if state["alt"] > 0.5 else ""))
        elif cmd == mav.MAV_CMD_DO_MOTOR_TEST:
            if armed:
                result = mav.MAV_RESULT_FAILED
            else:
                motor_test_pwm = int(msg.param3)
                motor_test_until = time.time() + msg.param4
                print(f"MOTOR_TEST seq={int(msg.param1)} pwm={motor_test_pwm} timeout={msg.param4}")
        elif cmd == mav.MAV_CMD_DO_START_MAG_CAL:
            magcal_started = time.time()
            send_statustext(6, "Compass calibration started")
        elif cmd == mav.MAV_CMD_DO_CANCEL_MAG_CAL:
            magcal_started = 0
        elif cmd == mav.MAV_CMD_DO_ACCEPT_MAG_CAL:
            send_statustext(6, "Compass calibration accepted")
        elif cmd == mav.MAV_CMD_PREFLIGHT_CALIBRATION:
            if msg.param1:
                send_statustext(6, "Calibrating gyros")
            if msg.param3:
                state["alt"] = 0.0
                send_statustext(6, "Barometer calibrated")
        elif cmd == mav.MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN:
            send_statustext(6, "Rebooting (simulated)")
        elif cmd == mav.MAV_CMD_DO_SET_MODE:
            new_mode = int(msg.param2)
            if int(msg.param1) & mav.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED and new_mode != mode:
                if new_mode == 3 and len(mission) < 2:
                    send_statustext(3, "Mode change to AUTO failed: no mission")
                    result = mav.MAV_RESULT_FAILED
                else:
                    mode = new_mode
                    enter_mode()
        elif cmd == mav.MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES:
            m.autopilot_version_send(0x1FFFF, 0x04060300, 0, 0, 0, bytes(8), bytes(8), bytes(8), 0x0021, 0x001A, 0)
        elif cmd == mav.MAV_CMD_NAV_TAKEOFF:
            if mode != 4 or not armed:
                send_statustext(3, "Takeoff: must be armed and in GUIDED")
                result = mav.MAV_RESULT_FAILED
            else:
                nav["guided_alt"] = msg.param7
                nav["guided_takeoff"] = True
                nav["guided_target"] = None
                nav["hold_lat"], nav["hold_lon"] = state["lat"], state["lon"]
                nav["target_alt"] = msg.param7
                send_statustext(6, f"Takeoff to {msg.param7:.1f} m")
        elif cmd == mav.MAV_CMD_MISSION_START:
            if len(mission) < 2:
                result = mav.MAV_RESULT_FAILED
                send_statustext(3, "Mission start: no mission")
            else:
                mode = 3
                enter_mode()
                set_current_seq(1)
        elif cmd in (mav.MAV_CMD_REQUEST_MESSAGE, mav.MAV_CMD_GET_HOME_POSITION):
            if cmd == mav.MAV_CMD_GET_HOME_POSITION or int(msg.param1) == mav.MAVLINK_MSG_ID_HOME_POSITION:
                send_home()
        m.command_ack_send(cmd, result)


# ---------------------------------------------------------------------------
# Main loop

print(f"Simulator sending to {gcs_host}:{gcs_port}; listening on the reply port")
print(f"Frame Quad X, hover thrust {THST_HOVER:.2f}, max tilt {ANGLE_MAX_DEG:.0f} deg, "
      f"climb {SPEED_UP:.1f} m/s, yaw {YAW_RATE:.0f} deg/s, home alt {HOME_ALT_MSL:.0f} m MSL, "
      f"battery {CELLS}S {BATTERY_MAH_REAL:.0f} mAh")
update_battery(0.0)
send_statustext(6, "ArduCopter V4.6.3 (sim)")
send_statustext(6, "Pixhawk1 0021001A 32385110 30313633")
send_statustext(6, "Frame: QUAD/X")
send_statustext(6, "GPS 1: detected as u-blox")
send_statustext(6, "EKF3 IMU0 initialised")

last_dyn = time.time()
while True:
    now = time.time()
    tt = now - t0
    dt = min(0.1, now - last_dyn)
    last_dyn = now
    update_dynamics(dt)
    update_battery(dt)

    msg = recv()
    while msg is not None:
        handle(msg)
        msg = recv()

    st = state
    base_mode = mav.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
    if armed or now < motor_test_until:
        base_mode |= mav.MAV_MODE_FLAG_SAFETY_ARMED

    if every("hb", 1.0):
        m.heartbeat_send(mav.MAV_TYPE_QUADROTOR, mav.MAV_AUTOPILOT_ARDUPILOTMEGA, base_mode, mode,
                         mav.MAV_STATE_ACTIVE if armed else mav.MAV_STATE_STANDBY)
    if every("sys", 0.5):
        sensors = 0x1FFFF
        m.sys_status_send(sensors, sensors, sensors, int(st["load"] * 1000), int(st["voltage"] * 1000),
                          int(st["current"] * 100), fc_remaining_pct(), 0, 0, 0, 0, 0, 0)
        cells = [int(st["voltage"] / CELLS * 1000)] * CELLS + [65535] * 7
        m.battery_status_send(0, mav.MAV_BATTERY_FUNCTION_ALL, mav.MAV_BATTERY_TYPE_LIPO,
                              int(BATTERY_TEMP_C * 100), cells, int(st["current"] * 100),
                              int(st["consumed_mah"]), int(st["consumed_mah"] * st["voltage"] / 1000.0 * 36),
                              fc_remaining_pct())
    if every("att", 0.1):
        m.attitude_send(int(tt * 1000), math.radians(st["roll"]), math.radians(st["pitch"]),
                        math.radians(st["heading"]), math.radians(st["roll_rate"]),
                        math.radians(st["pitch_rate"]), math.radians(st["yaw_rate"]))
    if every("gps", 0.2):
        lat = int(st["lat"] * 1e7)
        lon = int(st["lon"] * 1e7)
        alt_msl = HOME_ALT_MSL + st["alt"]
        gs = math.hypot(st["vn"], st["ve"])
        cog = math.degrees(math.atan2(st["ve"], st["vn"])) % 360.0 if gs > 0.2 else st["heading"]
        m.gps_raw_int_send(int(now * 1e6), 3, lat, lon, int(alt_msl * 1000), 95, 150, int(gs * 100),
                           int(cog * 100), 14, int((alt_msl - 20) * 1000), 1200, 1800, 300, 500000, 0)
        m.global_position_int_send(int(tt * 1000), lat, lon, int(alt_msl * 1000), int(st["alt"] * 1000),
                                   int(st["vn"] * 100), int(st["ve"] * 100), int(-st["vz"] * 100),
                                   int(st["heading"] * 100))
        m.vfr_hud_send(gs, gs, int(st["heading"]), int(st["thrust"] * 100), alt_msl, st["vz"])
    if every("servo", 0.1):
        s = st["motors"]
        m.servo_output_raw_send(int(tt * 1e6), 0, s[0], s[1], s[2], s[3], 0, 0, 0, 0)
    if every("press", 0.5):
        press = 1013.25 * (1.0 - (HOME_ALT_MSL + st["alt"]) / 44330.0) ** 5.255
        m.scaled_pressure_send(int(tt * 1000), press, 0.0, int(BATTERY_TEMP_C * 100 + 700), 0)
    if every("imu", 0.1):
        cr, sr_ = math.cos(math.radians(st["roll"])), math.sin(math.radians(st["roll"]))
        cp, sp = math.cos(math.radians(st["pitch"])), math.sin(math.radians(st["pitch"]))
        m.scaled_imu_send(int(tt * 1000), int(1000 * sp), int(-1000 * sr_ * cp), int(-1000 * cr * cp),
                          int(math.radians(st["roll_rate"]) * 1000), int(math.radians(st["pitch_rate"]) * 1000),
                          int(math.radians(st["yaw_rate"]) * 1000), 100, 0, -400, int(BATTERY_TEMP_C * 100 + 700))
    if every("rc", 0.25):
        m.rc_channels_send(int(tt * 1000), 4 if rc_seen else 0, int(rc_pwm[1]), int(rc_pwm[2]), int(rc_pwm[3]), int(rc_pwm[4]),
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255 if rc_seen else 0)
    if every("mcur", 1.0):
        m.mission_current_send(nav["cur_seq"])
    if every("home", 2.0):        # ArduPilot streams HOME_POSITION once home is set (first GPS fix)
        send_home()
    if every("ekf", 0.5):
        m.ekf_status_report_send((1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5), 0.12, 0.08, 0.10, 0.05, 0.02, 0.1)
    if every("status_print", 2.0) and armed:
        print(f"{MODE_NAMES.get(mode, mode):9s} alt {st['alt']:5.1f} m  vz {st['vz']:+4.1f}  "
              f"roll {st['roll']:+5.1f} pitch {st['pitch']:+5.1f} hdg {st['heading']:5.1f}  "
              f"gs {math.hypot(st['vn'], st['ve']):4.1f} m/s  {st['voltage']:.2f} V {st['current']:4.1f} A "
              f"{st['consumed_mah']:.0f} mAh  motors {st['motors']}  "
              f"rc x{manual['x']:+5d} y{manual['y']:+5d} z{manual['z']:4d} r{manual['r']:+5d} "
              f"{'landed' if st['alt'] <= 0.001 else 'flying'}"
              f"{'' if time.time() - manual['t'] < RC_OVERRIDE_TIME else ' NO-RC'}")
    if magcal_started and every("magcal", 0.5):
        pct = min(100, int((now - magcal_started) / 8 * 100))
        mask = [0xFF if b * 8 + 8 <= pct * 80 // 100 else 0 for b in range(10)]
        m.mag_cal_progress_send(0, 1, 2 if pct < 50 else 3, 1, pct, mask, 0.2, -0.5, 0.8)
        if pct >= 100:
            m.mag_cal_report_send(0, 1, 4, 0, 6.5, -4.6, 149.7, -85.5, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.9, 0, 0, 1.0)
            magcal_started = 0
            send_statustext(6, "Compass calibration done")
    time.sleep(0.01)
