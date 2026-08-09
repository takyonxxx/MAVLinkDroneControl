#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RC Config Tool PRO - Pixhawk / ArduCopter Yer Istasyonu Araci
--------------------------------------------------------------
- Koyu profesyonel tema
- Telemetri: yapay ufuk (attitude indicator), HSI/pusula, batarya, GPS
- RC Kanallari: ham PWM + FC'nin yorumladigi normalize deger (-100..+100)
  (REVERSED/MIN/TRIM/MAX/DZ parametreleri hesaba katilir)
- Motorlar: SERVO cikis PWM'leri canli + guvenlik onayli Motor Test
- RC Ayarlari: REVERSED/MIN/TRIM/MAX/DZ goruntule + SET
- Anahtarlar/Modlar: FLTMODE1-6 ve RCx_OPTION
- Parametreler: arama filtreli tam liste, oku/yaz
- Log: ayri sekmede siyah zemin / yesil metin terminal gorunumu

Gereksinim: pymavlink  (pip install pymavlink)
Calistirma: python3 rc_config_tool.py
"""

import math
import queue
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

from pymavlink import mavutil

DEFAULT_CONN = "udp:0.0.0.0:14550"
NUM_RC_CHANNELS = 16
NUM_MOTORS = 8

# ---------------------------------------------------------------------------
# Tema
# ---------------------------------------------------------------------------
C_BG       = "#16181d"   # ana zemin
C_PANEL    = "#1e222a"   # panel zemini
C_PANEL2   = "#252a34"   # giris kutulari
C_BORDER   = "#333a47"
C_TEXT     = "#d7dde6"
C_DIM      = "#8a93a3"
C_ACCENT   = "#4fc3f7"   # mavi
C_GOOD     = "#53d769"   # yesil
C_WARN     = "#ffb547"   # turuncu
C_BAD      = "#ff5c57"   # kirmizi
C_BAR_BG   = "#2a2f3a"
C_LOG_BG   = "#0a0d0a"
C_LOG_FG   = "#39ff6a"

FONT       = ("Helvetica", 12)
FONT_B     = ("Helvetica", 12, "bold")
FONT_BIG   = ("Helvetica", 16, "bold")
FONT_MONO  = ("Menlo", 11)

COPTER_MODES = {
    0: "Stabilize", 1: "Acro", 2: "AltHold", 3: "Auto", 4: "Guided",
    5: "Loiter", 6: "RTL", 7: "Circle", 9: "Land", 11: "Drift",
    13: "Sport", 14: "Flip", 15: "AutoTune", 16: "PosHold", 17: "Brake",
    18: "Throw", 19: "Avoid_ADSB", 20: "Guided_NoGPS", 21: "Smart_RTL",
    22: "FlowHold", 23: "Follow", 24: "ZigZag", 25: "SystemID",
    26: "Heli_Autorotate", 27: "Auto RTL",
}

RC_OPTIONS = {
    0: "Bos (Do Nothing)", 2: "Flip", 3: "Simple Mode", 4: "RTL",
    5: "Save Trim", 7: "Save WP", 9: "Camera Trigger", 11: "Fence",
    13: "Super Simple", 16: "Auto", 17: "AutoTune", 18: "Land",
    19: "Gripper", 21: "Parachute Enable", 22: "Parachute Release",
    23: "Parachute 3Pos", 29: "Landing Gear", 30: "Lost Copter Sound",
    31: "Motor Emergency Stop", 32: "Motor Interlock", 33: "Brake",
    37: "Throw", 39: "PrecLoiter", 41: "ArmDisarm", 42: "SmartRTL",
    46: "RC Override Enable", 55: "Guided", 56: "Loiter", 57: "Follow",
    58: "Clear Waypoints", 62: "Compass Learn", 65: "GPS Disable",
    68: "Stabilize", 69: "PosHold", 70: "AltHold", 71: "FlowHold",
    72: "Circle", 73: "Drift", 76: "Standby", 81: "Disarm",
    84: "AirMode", 102: "Camera Mode Toggle", 153: "ArmDisarm (4.2+)",
    154: "ArmDisarm + AirMode", 158: "Optflow Calibration",
}

RC_FIELDS = ["REVERSED", "MIN", "TRIM", "MAX", "DZ"]
CH_NAMES = {1: "Roll", 2: "Pitch", 3: "Throttle", 4: "Yaw"}


def opt_label(v):
    v = int(v)
    return f"{v}: {RC_OPTIONS.get(v, 'Bilinmeyen/Diger')}"


def mode_label(v):
    v = int(v)
    return f"{v}: {COPTER_MODES.get(v, 'Bilinmeyen')}"


# ---------------------------------------------------------------------------
# MAVLink istemcisi
# ---------------------------------------------------------------------------
class MavlinkClient:
    def __init__(self, ui_queue):
        self.ui_queue = ui_queue
        self.conn = None
        self.running = False
        self.params = {}
        self.lock = threading.Lock()

    def connect(self, conn_str):
        self.disconnect()
        try:
            self.conn = mavutil.mavlink_connection(conn_str, source_system=254)
        except Exception as e:
            self.ui_queue.put(("log", f"Baglanti hatasi: {e}"))
            return
        self.running = True
        threading.Thread(target=self._reader, daemon=True).start()
        self.ui_queue.put(("log", f"Baglandi: {conn_str} - heartbeat bekleniyor..."))

    def disconnect(self):
        self.running = False
        if self.conn:
            try:
                self.conn.close()
            except Exception:
                pass
            self.conn = None
            self.ui_queue.put(("conn", False))

    def _reader(self):
        got_hb = False
        while self.running and self.conn:
            try:
                msg = self.conn.recv_match(blocking=True, timeout=1.0)
            except Exception:
                continue
            if msg is None:
                continue
            t = msg.get_type()

            if t == "HEARTBEAT" and msg.get_srcComponent() in (0, 1):
                if not got_hb:
                    got_hb = True
                    self.ui_queue.put(("log", "Heartbeat alindi - arac bagli."))
                    self.ui_queue.put(("conn", True))
                    self._request_streams()
                armed = bool(msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
                self.ui_queue.put(("heartbeat", {
                    "mode": mavutil.mode_string_v10(msg), "armed": armed}))

            elif t == "RC_CHANNELS":
                vals = [getattr(msg, f"chan{i}_raw", 0) for i in range(1, NUM_RC_CHANNELS + 1)]
                self.ui_queue.put(("rc", vals))

            elif t == "SERVO_OUTPUT_RAW":
                vals = [getattr(msg, f"servo{i}_raw", 0) for i in range(1, NUM_MOTORS + 1)]
                self.ui_queue.put(("servo", vals))

            elif t == "SYS_STATUS":
                self.ui_queue.put(("battery", {
                    "voltage": msg.voltage_battery / 1000.0 if msg.voltage_battery != 0xFFFF else None,
                    "current": msg.current_battery / 100.0 if msg.current_battery != -1 else None,
                    "remaining": msg.battery_remaining if msg.battery_remaining != -1 else None}))

            elif t == "ATTITUDE":
                self.ui_queue.put(("attitude", {
                    "roll": math.degrees(msg.roll),
                    "pitch": math.degrees(msg.pitch),
                    "yaw": (math.degrees(msg.yaw) + 360.0) % 360.0}))

            elif t == "VFR_HUD":
                self.ui_queue.put(("vfr", {"alt": msg.alt, "climb": msg.climb,
                                           "throttle": msg.throttle,
                                           "groundspeed": msg.groundspeed,
                                           "heading": msg.heading}))

            elif t == "GPS_RAW_INT":
                self.ui_queue.put(("gps", {"fix": msg.fix_type,
                                           "sats": msg.satellites_visible}))

            elif t == "PARAM_VALUE":
                with self.lock:
                    self.params[msg.param_id] = msg.param_value
                self.ui_queue.put(("param", {"name": msg.param_id,
                                             "value": msg.param_value}))

            elif t == "STATUSTEXT":
                self.ui_queue.put(("log", f"AP: {msg.text}"))

            elif t == "COMMAND_ACK":
                res = "KABUL" if msg.result == 0 else f"RED (kod {msg.result})"
                self.ui_queue.put(("log", f"Komut yaniti: cmd={msg.command} -> {res}"))

    def _request_streams(self):
        try:
            self.conn.mav.request_data_stream_send(
                self.conn.target_system, self.conn.target_component,
                mavutil.mavlink.MAV_DATA_STREAM_ALL, 5, 1)
        except Exception:
            pass

    def request_param(self, name):
        if not self.conn:
            return
        try:
            self.conn.mav.param_request_read_send(
                self.conn.target_system, self.conn.target_component,
                name.encode("ascii"), -1)
        except Exception as e:
            self.ui_queue.put(("log", f"Param istegi hatasi ({name}): {e}"))

    def request_all_params(self):
        if not self.conn:
            return
        try:
            self.conn.mav.param_request_list_send(
                self.conn.target_system, self.conn.target_component)
            self.ui_queue.put(("log", "Tum parametreler istendi..."))
        except Exception as e:
            self.ui_queue.put(("log", f"Param listesi hatasi: {e}"))

    def set_param(self, name, value):
        if not self.conn:
            self.ui_queue.put(("log", "Bagli degil - parametre yazilamadi."))
            return
        try:
            self.conn.mav.param_set_send(
                self.conn.target_system, self.conn.target_component,
                name.encode("ascii"), float(value),
                mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            self.ui_queue.put(("log", f"SET {name} = {value}"))
            threading.Timer(0.5, lambda: self.request_param(name)).start()
        except Exception as e:
            self.ui_queue.put(("log", f"Param yazma hatasi ({name}): {e}"))

    def motor_test(self, motor, throttle_pct, duration_s):
        if not self.conn:
            self.ui_queue.put(("log", "Bagli degil - motor test gonderilemedi."))
            return
        try:
            self.conn.mav.command_long_send(
                self.conn.target_system, self.conn.target_component,
                mavutil.mavlink.MAV_CMD_DO_MOTOR_TEST, 0,
                float(motor),          # param1: motor no (1..)
                0.0,                   # param2: throttle tipi (0 = yuzde)
                float(throttle_pct),   # param3: gaz yuzdesi
                float(duration_s),     # param4: sure (s)
                0.0, 0.0, 0.0)
            self.ui_queue.put(("log",
                f"MOTOR TEST: M{motor} %{throttle_pct} {duration_s}s gonderildi."))
        except Exception as e:
            self.ui_queue.put(("log", f"Motor test hatasi: {e}"))

    def motor_test_all_stop(self):
        for m in range(1, NUM_MOTORS + 1):
            self.motor_test(m, 0, 0)

    def arm_disarm(self, arm):
        if not self.conn:
            self.ui_queue.put(("log", "Bagli degil - arm/disarm gonderilemedi."))
            return
        try:
            self.conn.mav.command_long_send(
                self.conn.target_system, self.conn.target_component,
                mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
                1.0 if arm else 0.0,   # param1: 1=arm 0=disarm
                0.0,                   # param2: 0=normal (zorlama yok)
                0.0, 0.0, 0.0, 0.0, 0.0)
            self.ui_queue.put(("log", "ARM komutu gonderildi." if arm
                              else "DISARM komutu gonderildi."))
        except Exception as e:
            self.ui_queue.put(("log", f"Arm/disarm hatasi: {e}"))


# ---------------------------------------------------------------------------
# Ozel gosterge bilesenleri
# ---------------------------------------------------------------------------
class AttitudeIndicator(tk.Canvas):
    """Yapay ufuk gostergesi."""
    SIZE = 240

    def __init__(self, master):
        super().__init__(master, width=self.SIZE, height=self.SIZE,
                         bg=C_PANEL, highlightthickness=0)
        self.roll = 0.0
        self.pitch = 0.0
        self._draw()

    def update_att(self, roll, pitch):
        self.roll, self.pitch = roll, pitch
        self._draw()

    def _draw(self):
        self.delete("all")
        s = self.SIZE
        cx = cy = s / 2
        r = s / 2 - 8
        ppd = r / 45.0                      # piksel / derece (pitch)
        a = math.radians(-self.roll)
        ca, sa = math.cos(a), math.sin(a)
        off = self.pitch * ppd

        def rot(x, y):
            # dunya -> ekran: once pitch kaydir, sonra roll dondur
            y = y + off
            return cx + x * ca - y * sa, cy + x * sa + y * ca

        # gok / yer
        big = s * 2
        sky = [*rot(-big, -big), *rot(big, -big), *rot(big, 0), *rot(-big, 0)]
        gnd = [*rot(-big, 0), *rot(big, 0), *rot(big, big), *rot(-big, big)]
        self.create_polygon(sky, fill="#2c6db3", outline="")
        self.create_polygon(gnd, fill="#7a4a1f", outline="")
        self.create_line(*rot(-big, 0), *rot(big, 0), fill="white", width=2)

        # pitch merdiveni
        for deg in range(-40, 41, 10):
            if deg == 0:
                continue
            w = 34 if deg % 20 == 0 else 18
            x1, y1 = rot(-w, -deg * ppd)
            x2, y2 = rot(w, -deg * ppd)
            self.create_line(x1, y1, x2, y2, fill="white", width=1)
            if deg % 20 == 0:
                tx, ty = rot(w + 16, -deg * ppd)
                self.create_text(tx, ty, text=str(abs(deg)),
                                 fill="white", font=("Helvetica", 9))

        # kose maskesi + cerceve
        self.create_oval(cx - r - 40, cy - r - 40, cx + r + 40, cy + r + 40,
                         outline=C_PANEL, width=42)
        self.create_oval(cx - r, cy - r, cx + r, cy + r,
                         outline=C_BORDER, width=2)

        # roll skalasi
        for deg in (-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60):
            b = math.radians(deg - self.roll - 90)
            l = 10 if deg % 30 == 0 else 6
            x1 = cx + (r - l) * math.cos(b)
            y1 = cy + (r - l) * math.sin(b)
            x2 = cx + r * math.cos(b)
            y2 = cy + r * math.sin(b)
            self.create_line(x1, y1, x2, y2, fill="white", width=2)
        self.create_polygon(cx, cy - r + 4, cx - 7, cy - r + 16, cx + 7, cy - r + 16,
                            fill=C_WARN, outline="")

        # sabit ucak sembolu
        self.create_line(cx - 46, cy, cx - 14, cy, fill=C_WARN, width=3)
        self.create_line(cx + 14, cy, cx + 46, cy, fill=C_WARN, width=3)
        self.create_oval(cx - 4, cy - 4, cx + 4, cy + 4,
                         outline=C_WARN, width=3)

        self.create_text(10, s - 12, anchor="w", fill=C_TEXT, font=FONT_MONO,
                         text=f"R {self.roll:+05.1f}")
        self.create_text(s - 10, s - 12, anchor="e", fill=C_TEXT, font=FONT_MONO,
                         text=f"P {self.pitch:+05.1f}")


class HSIIndicator(tk.Canvas):
    """Pusula gulu / HSI."""
    SIZE = 240

    def __init__(self, master):
        super().__init__(master, width=self.SIZE, height=self.SIZE,
                         bg=C_PANEL, highlightthickness=0)
        self.heading = 0.0
        self.gs = 0.0
        self._draw()

    def update_hsi(self, heading, groundspeed):
        self.heading = heading
        self.gs = groundspeed
        self._draw()

    def _draw(self):
        self.delete("all")
        s = self.SIZE
        cx = cy = s / 2
        r = s / 2 - 10
        self.create_oval(cx - r, cy - r, cx + r, cy + r,
                         outline=C_BORDER, width=2, fill="#1a1e26")

        for deg in range(0, 360, 5):
            b = math.radians(deg - self.heading - 90)
            major = (deg % 30 == 0)
            l = 12 if major else 6
            x1 = cx + (r - l) * math.cos(b)
            y1 = cy + (r - l) * math.sin(b)
            x2 = cx + (r - 2) * math.cos(b)
            y2 = cy + (r - 2) * math.sin(b)
            self.create_line(x1, y1, x2, y2, fill=C_TEXT if major else C_DIM,
                             width=2 if major else 1)
            if major:
                labels = {0: "N", 90: "E", 180: "S", 270: "W"}
                txt = labels.get(deg, str(deg // 10))
                tx = cx + (r - 26) * math.cos(b)
                ty = cy + (r - 26) * math.sin(b)
                col = C_BAD if txt == "N" else C_TEXT
                self.create_text(tx, ty, text=txt, fill=col,
                                 font=("Helvetica", 11, "bold"))

        # sabit isaretci + ucak sembolu
        self.create_line(cx, cy - r + 2, cx, cy - r + 18, fill=C_WARN, width=3)
        self.create_polygon(cx, cy - 16, cx - 8, cy + 12, cx, cy + 5,
                            cx + 8, cy + 12, fill=C_ACCENT, outline="")

        # heading kutusu
        self.create_rectangle(cx - 30, 2, cx + 30, 22, fill=C_PANEL2,
                              outline=C_BORDER)
        self.create_text(cx, 12, text=f"{self.heading:03.0f}",
                         fill=C_GOOD, font=("Menlo", 13, "bold"))
        self.create_text(10, s - 12, anchor="w", fill=C_TEXT, font=FONT_MONO,
                         text=f"GS {self.gs:4.1f} m/s")


class HBar(tk.Canvas):
    """Yatay cubuk: raw modunda 1000-2000, center modunda -100..+100."""
    def __init__(self, master, width=360, height=16, mode="raw"):
        super().__init__(master, width=width, height=height,
                         bg=C_PANEL, highlightthickness=0)
        self.w, self.h, self.mode = width, height, mode
        self.set(0)

    def set(self, value, active=True):
        self.delete("all")
        w, h = self.w, self.h
        self.create_rectangle(0, 0, w, h, fill=C_BAR_BG, outline=C_BORDER)
        if self.mode == "raw":
            if value and value > 0:
                frac = min(max((value - 1000) / 1000.0, 0.0), 1.0)
                self.create_rectangle(1, 1, 1 + frac * (w - 2), h - 1,
                                      fill=C_ACCENT if active else C_DIM, outline="")
        else:  # center: -100..+100
            mid = w / 2
            if value is not None:
                frac = min(max(value / 100.0, -1.0), 1.0)
                col = C_GOOD if abs(frac) < 0.9 else C_WARN
                if frac >= 0:
                    self.create_rectangle(mid, 2, mid + frac * (mid - 2), h - 2,
                                          fill=col, outline="")
                else:
                    self.create_rectangle(mid + frac * (mid - 2), 2, mid, h - 2,
                                          fill=col, outline="")
            self.create_line(mid, 0, mid, h, fill=C_TEXT)


# ---------------------------------------------------------------------------
# Ana uygulama
# ---------------------------------------------------------------------------
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("RC Config Tool PRO - Pixhawk / ArduCopter")
        self.geometry("1120x800")
        self.configure(bg=C_BG)
        self._style()

        self.ui_queue = queue.Queue()
        self.mav = MavlinkClient(self.ui_queue)

        self.rc_bars, self.rc_raw_lbl = [], []
        self.rc_ibars, self.rc_int_lbl = [], []
        self.motor_bars, self.motor_lbl = [], []
        self.rc_param_vars = {}
        self.fltmode_vars, self.option_vars = {}, {}
        self.param_rows = {}
        self.all_params = {}
        self.armed = False
        self.rc_last = [0] * NUM_RC_CHANNELS
        self.detect_active = None      # tespit edilen fonksiyon adi
        self.detect_base = None        # baslangic PWM degerleri
        self.detect_dev = None         # maksimum sapmalar

        self._build_ui()
        self.after(50, self._poll_queue)

    # -- stil --------------------------------------------------------------
    def _style(self):
        st = ttk.Style(self)
        st.theme_use("clam")
        st.configure(".", background=C_BG, foreground=C_TEXT,
                     fieldbackground=C_PANEL2, bordercolor=C_BORDER,
                     lightcolor=C_PANEL, darkcolor=C_PANEL, font=FONT)
        st.configure("TFrame", background=C_BG)
        st.configure("Panel.TFrame", background=C_PANEL)
        st.configure("TLabel", background=C_BG, foreground=C_TEXT)
        st.configure("Panel.TLabel", background=C_PANEL, foreground=C_TEXT)
        st.configure("Dim.TLabel", background=C_PANEL, foreground=C_DIM)
        st.configure("Head.TLabel", background=C_PANEL, foreground=C_ACCENT,
                     font=FONT_B)
        st.configure("TNotebook", background=C_BG, borderwidth=0)
        st.configure("TNotebook.Tab", background=C_PANEL, foreground=C_DIM,
                     padding=(14, 7), font=FONT_B)
        st.map("TNotebook.Tab",
               background=[("selected", C_PANEL2)],
               foreground=[("selected", C_ACCENT)])
        st.configure("TButton", background=C_PANEL2, foreground=C_TEXT,
                     bordercolor=C_BORDER, focusthickness=0, padding=(10, 5))
        st.map("TButton", background=[("active", C_BORDER)])
        st.configure("Danger.TButton", background="#5a2320", foreground="#ffd9d7")
        st.map("Danger.TButton", background=[("active", "#7a2e2a")])
        st.configure("TEntry", foreground=C_TEXT, insertcolor=C_TEXT)
        st.configure("TCombobox", foreground=C_TEXT, arrowcolor=C_TEXT)
        st.configure("Treeview", background=C_PANEL, fieldbackground=C_PANEL,
                     foreground=C_TEXT, rowheight=24, bordercolor=C_BORDER)
        st.configure("Treeview.Heading", background=C_PANEL2,
                     foreground=C_ACCENT, font=FONT_B)
        st.map("Treeview", background=[("selected", "#2f4a63")])
        st.configure("TLabelframe", background=C_PANEL, bordercolor=C_BORDER)
        st.configure("TLabelframe.Label", background=C_PANEL,
                     foreground=C_ACCENT, font=FONT_B)
        self.option_add("*TCombobox*Listbox.background", C_PANEL2)
        self.option_add("*TCombobox*Listbox.foreground", C_TEXT)

    # -- UI ----------------------------------------------------------------
    def _build_ui(self):
        top = ttk.Frame(self, padding=8)
        top.pack(fill="x")
        ttk.Label(top, text="Baglanti:").pack(side="left")
        self.conn_var = tk.StringVar(value=DEFAULT_CONN)
        ttk.Entry(top, textvariable=self.conn_var, width=26).pack(side="left", padx=6)
        ttk.Button(top, text="Baglan", command=self._connect).pack(side="left")
        ttk.Button(top, text="Kes", command=self.mav.disconnect).pack(side="left", padx=4)

        self.link_var = tk.StringVar(value="BAGLI DEGIL")
        self.link_lbl = tk.Label(top, textvariable=self.link_var, bg=C_BG,
                                 fg=C_BAD, font=FONT_B)
        self.link_lbl.pack(side="left", padx=16)

        self.status_var = tk.StringVar(value="-")
        tk.Label(top, textvariable=self.status_var, bg=C_BG, fg=C_GOOD,
                 font=FONT_BIG).pack(side="right")

        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        tabs = {}
        for key, txt in [("tel", "Telemetri"), ("rc", "RC Kanallari"),
                         ("mot", "Motorlar"), ("map", "Atama (RCMAP)"),
                         ("rcset", "RC Ayarlari"),
                         ("sw", "Anahtarlar / Modlar"), ("par", "Parametreler"),
                         ("log", "Log")]:
            f = ttk.Frame(nb, style="Panel.TFrame")
            nb.add(f, text=txt)
            tabs[key] = f
        self.tabs = tabs

        self._tab_telemetry(tabs["tel"])
        self._tab_rc(tabs["rc"])
        self._tab_motors(tabs["mot"])
        self._tab_rcmap(tabs["map"])
        self._tab_rcset(tabs["rcset"])
        self._tab_switches(tabs["sw"])
        self._tab_params(tabs["par"])
        self._tab_log(tabs["log"])

    # -- Telemetri ---------------------------------------------------------
    def _tab_telemetry(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=14)
        f.pack(fill="both", expand=True)

        gauges = ttk.Frame(f, style="Panel.TFrame")
        gauges.pack(side="top", pady=6)
        g1 = ttk.LabelFrame(gauges, text="Yapay Ufuk", padding=8)
        g1.pack(side="left", padx=12)
        self.att_ind = AttitudeIndicator(g1)
        self.att_ind.pack()
        g2 = ttk.LabelFrame(gauges, text="HSI / Pusula", padding=8)
        g2.pack(side="left", padx=12)
        self.hsi = HSIIndicator(g2)
        self.hsi.pack()

        info = ttk.Frame(f, style="Panel.TFrame")
        info.pack(side="top", pady=12)
        self.tel_vars = {}
        cells = [("MOD", "mode"), ("ARM", "armed"), ("BATARYA", "battery"),
                 ("GPS", "gps"), ("IRTIFA", "alt"), ("TIRMANMA", "climb"),
                 ("GAZ", "thr"), ("YAW", "yaw")]
        for i, (label, key) in enumerate(cells):
            cell = tk.Frame(info, bg=C_PANEL2, highlightbackground=C_BORDER,
                            highlightthickness=1, padx=16, pady=8)
            cell.grid(row=i // 4, column=i % 4, padx=8, pady=8, sticky="nsew")
            tk.Label(cell, text=label, bg=C_PANEL2, fg=C_DIM,
                     font=("Helvetica", 10, "bold")).pack(anchor="w")
            v = tk.StringVar(value="-")
            self.tel_vars[key] = v
            tk.Label(cell, textvariable=v, bg=C_PANEL2, fg=C_TEXT,
                     font=("Menlo", 15, "bold")).pack(anchor="w")

        # ARM / DISARM butonu - cihazdaki gercek durumu gosterir
        armf = ttk.Frame(f, style="Panel.TFrame")
        armf.pack(side="top", pady=8)
        self.arm_btn = tk.Button(armf, text="DISARMED  (ARM icin tikla)",
                                 font=("Helvetica", 15, "bold"),
                                 bg="#233326", fg=C_GOOD,
                                 activebackground="#2e4433",
                                 activeforeground=C_GOOD,
                                 relief="flat", padx=28, pady=10,
                                 highlightbackground=C_PANEL,
                                 command=self._toggle_arm)
        self.arm_btn.pack()
        ttk.Label(f, style="Dim.TLabel", text=(
            "Buton cihazdan gelen gercek arm durumunu gosterir; komut FC "
            "tarafindan reddedilirse (PreArm) durum degismez, sebep Log'a duser."
        )).pack(side="top")

    # -- RC Kanallari ------------------------------------------------------
    def _tab_rc(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=10)
        f.pack(fill="both", expand=True)
        ttk.Label(f, style="Dim.TLabel", text=(
            "HAM: alicidan gelen PWM.  YORUM: FC'nin REVERSED/MIN/TRIM/MAX/DZ "
            "ile yorumladigi deger (-100..+100). Baglaninca RC parametreleri "
            "otomatik okunur; okunana kadar YORUM sutunu '-' gosterir.")).pack(
            anchor="w", pady=(0, 8))

        hdr = ttk.Frame(f, style="Panel.TFrame")
        hdr.pack(fill="x")
        ttk.Label(hdr, text="Kanal", style="Head.TLabel", width=14).pack(side="left")
        ttk.Label(hdr, text="Ham PWM", style="Head.TLabel", width=27).pack(side="left")
        ttk.Label(hdr, text="", style="Head.TLabel", width=6).pack(side="left")
        ttk.Label(hdr, text="Yorumlanmis (-100..+100)", style="Head.TLabel",
                  width=27).pack(side="left")

        for ch in range(1, NUM_RC_CHANNELS + 1):
            row = ttk.Frame(f, style="Panel.TFrame")
            row.pack(fill="x", pady=2)
            name = f"CH{ch}"
            if ch in CH_NAMES:
                name += f" {CH_NAMES[ch]}"
            ttk.Label(row, text=name, style="Panel.TLabel", width=14).pack(side="left")
            b = HBar(row, width=300, mode="raw")
            b.pack(side="left", padx=4)
            rl = tk.StringVar(value="-")
            ttk.Label(row, textvariable=rl, style="Panel.TLabel", width=6).pack(side="left")
            ib = HBar(row, width=300, mode="center")
            ib.pack(side="left", padx=4)
            il = tk.StringVar(value="-")
            ttk.Label(row, textvariable=il, style="Panel.TLabel", width=7).pack(side="left")
            self.rc_bars.append(b)
            self.rc_raw_lbl.append(rl)
            self.rc_ibars.append(ib)
            self.rc_int_lbl.append(il)

    def _interp(self, ch, pwm):
        """FC'nin kanali nasil yorumladigini hesapla: -100..+100 (None=veri yok)."""
        if not pwm:
            return None
        p = self.all_params
        rev = p.get(f"RC{ch}_REVERSED")
        mn = p.get(f"RC{ch}_MIN")
        tr = p.get(f"RC{ch}_TRIM")
        mx = p.get(f"RC{ch}_MAX")
        dz = p.get(f"RC{ch}_DZ", 0) or 0
        if None in (rev, mn, tr, mx) or mx <= mn:
            return None
        if abs(pwm - tr) <= dz:
            v = 0.0
        elif pwm >= tr:
            span = (mx - tr) - dz
            v = 0.0 if span <= 0 else (pwm - tr - dz) / span
        else:
            span = (tr - mn) - dz
            v = 0.0 if span <= 0 else (pwm - tr + dz) / span
        if int(rev) == 1:
            v = -v
        return max(-1.0, min(1.0, v)) * 100.0

    # -- Motorlar ----------------------------------------------------------
    def _tab_motors(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=10)
        f.pack(fill="both", expand=True)

        lf = ttk.LabelFrame(f, text="Motor / Servo Cikis PWM (canli)", padding=8)
        lf.pack(fill="x", pady=4)
        for m in range(1, NUM_MOTORS + 1):
            row = ttk.Frame(lf, style="Panel.TFrame")
            row.pack(fill="x", pady=2)
            ttk.Label(row, text=f"M{m} (SERVO{m})", style="Panel.TLabel",
                      width=14).pack(side="left")
            b = HBar(row, width=520, mode="raw")
            b.pack(side="left", padx=6)
            v = tk.StringVar(value="-")
            ttk.Label(row, textvariable=v, style="Panel.TLabel", width=6).pack(side="left")
            self.motor_bars.append(b)
            self.motor_lbl.append(v)

        tf = ttk.LabelFrame(f, text="Motor Test (PERVANELER SOKULU OLMALI)", padding=10)
        tf.pack(fill="x", pady=10)
        tk.Label(tf, text="UYARI: Motor testi motorlari fiziksel olarak dondurur. "
                          "Pervaneleri sokmeden KULLANMAYIN.",
                 bg=C_PANEL, fg=C_BAD, font=FONT_B).pack(anchor="w", pady=(0, 8))

        ctl = ttk.Frame(tf, style="Panel.TFrame")
        ctl.pack(fill="x")
        ttk.Label(ctl, text="Gaz %:", style="Panel.TLabel").pack(side="left")
        self.mt_thr = tk.StringVar(value="8")
        ttk.Entry(ctl, textvariable=self.mt_thr, width=5).pack(side="left", padx=4)
        ttk.Label(ctl, text="Sure (s):", style="Panel.TLabel").pack(side="left")
        self.mt_dur = tk.StringVar(value="2")
        ttk.Entry(ctl, textvariable=self.mt_dur, width=5).pack(side="left", padx=4)

        btns = ttk.Frame(tf, style="Panel.TFrame")
        btns.pack(fill="x", pady=8)
        for m in range(1, NUM_MOTORS + 1):
            ttk.Button(btns, text=f"Test M{m}",
                       command=lambda mm=m: self._motor_test(mm)).pack(side="left", padx=3)
        ttk.Button(btns, text="TUMUNU DURDUR", style="Danger.TButton",
                   command=self.mav.motor_test_all_stop).pack(side="left", padx=14)

        ttk.Label(f, style="Dim.TLabel", text=(
            "Not: ArduPilot motor testinde numaralandirma A/B/C/D sirasiyladir "
            "(QUAD/X: A=on-sag, B=arka-sag, C=arka-sol, D=on-sol; motor cikis "
            "numarasindan farklidir). Test icin arac disarm ve batarya bagli "
            "olmalidir.")).pack(anchor="w", pady=6)

    def _motor_test(self, m):
        try:
            thr = float(self.mt_thr.get())
            dur = float(self.mt_dur.get())
        except ValueError:
            self._log("Gaz/sure degeri gecersiz.")
            return
        if thr > 30:
            if not messagebox.askyesno("Yuksek Gaz",
                    f"%{thr:.0f} gaz yuksek bir deger. Devam edilsin mi?"):
                return
        if not messagebox.askyesno("Motor Test Onayi",
                f"M{m} motoru %{thr:.0f} gazla {dur:.0f} saniye donecek.\n\n"
                "PERVANELER SOKULU MU?"):
            return
        self.mav.motor_test(m, thr, dur)

    # -- Atama (RCMAP) -----------------------------------------------------
    def _tab_rcmap(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=12)
        f.pack(fill="both", expand=True)

        ttk.Button(f, text="Atama Parametrelerini Oku",
                   command=self._read_rcmap_params).pack(anchor="w", pady=(0, 4))

        self.detect_banner = tk.Label(f, text="", bg=C_PANEL, fg=C_WARN,
                                      font=FONT_B, anchor="w")
        self.detect_banner.pack(fill="x", pady=(0, 6))

        # --- Ana kumanda eksenleri (RCMAP) ---
        lf1 = ttk.LabelFrame(f, text="Ana Eksen Atamalari (RCMAP_x = hangi RC "
                                     "kanali bu fonksiyonu kontrol eder)", padding=10)
        lf1.pack(fill="x", pady=4)
        ttk.Label(lf1, style="Dim.TLabel", text=(
            "TESPIT ET: butona basin, 3 saniye icinde ilgili stick'i uclara "
            "hareket ettirin - en cok hareket eden kanal otomatik bulunur. "
            "Sonra SET ile yazin. RCMAP degisikligi REBOOT gerektirir!"
        )).grid(row=0, column=0, columnspan=5, sticky="w", pady=(0, 8))

        self.rcmap_vars = {}
        self.detect_btns = {}
        funcs = [("ROLL", "Sag stick sag-sol"),
                 ("PITCH", "Sag stick ileri-geri"),
                 ("THROTTLE", "Sol stick yukari-asagi"),
                 ("YAW", "Sol stick sag-sol")]
        for i, (fn, desc) in enumerate(funcs, start=1):
            ttk.Label(lf1, text=f"RCMAP_{fn}", style="Panel.TLabel",
                      width=16).grid(row=i, column=0, sticky="w", pady=3)
            ttk.Label(lf1, text=desc, style="Dim.TLabel",
                      width=22).grid(row=i, column=1, sticky="w")
            v = tk.StringVar(value="-")
            self.rcmap_vars[fn] = v
            ttk.Entry(lf1, textvariable=v, width=6).grid(row=i, column=2, padx=4)
            db = ttk.Button(lf1, text="TESPIT ET",
                            command=lambda ff=fn: self._start_detect(ff))
            db.grid(row=i, column=3, padx=4)
            self.detect_btns[fn] = db
            ttk.Button(lf1, text="SET",
                       command=lambda ff=fn: self._set_rcmap(ff)
                       ).grid(row=i, column=4, padx=4)

        self.detect_status = tk.StringVar(value="")

        # --- Ucus modu kanali ---
        lf2 = ttk.LabelFrame(f, text="Ucus Modu Anahtari - hangi kanal, hangi "
                                     "PWM araligi hangi modu secer", padding=10)
        lf2.pack(fill="x", pady=8)

        row = ttk.Frame(lf2, style="Panel.TFrame")
        row.pack(fill="x")
        ttk.Label(row, text="Mod kanali (FLTMODE_CH):",
                  style="Panel.TLabel").pack(side="left")
        self.map_fltch_var = tk.StringVar(value="-")
        ttk.Entry(row, textvariable=self.map_fltch_var, width=5).pack(side="left", padx=4)
        ttk.Button(row, text="TESPIT ET",
                   command=lambda: self._start_detect("FLTMODE_CH")).pack(side="left", padx=4)
        ttk.Button(row, text="SET", command=self._set_map_fltch).pack(side="left", padx=4)
        self.mode_live = tk.StringVar(value="Aktif dilim: -")
        tk.Label(row, textvariable=self.mode_live, bg=C_PANEL, fg=C_GOOD,
                 font=FONT_B).pack(side="left", padx=16)

        # PWM dilim tablosu
        self.mode_slot_labels = []
        grid = ttk.Frame(lf2, style="Panel.TFrame")
        grid.pack(fill="x", pady=(8, 0))
        ranges = ["<= 1230", "1231-1360", "1361-1490",
                  "1491-1620", "1621-1749", ">= 1750"]
        for i in range(6):
            cell = tk.Frame(grid, bg=C_PANEL2, highlightbackground=C_BORDER,
                            highlightthickness=1, padx=10, pady=6)
            cell.grid(row=0, column=i, padx=4, sticky="nsew")
            tk.Label(cell, text=f"FLTMODE{i+1}", bg=C_PANEL2, fg=C_DIM,
                     font=("Helvetica", 10, "bold")).pack()
            tk.Label(cell, text=ranges[i], bg=C_PANEL2, fg=C_DIM,
                     font=("Helvetica", 10)).pack()
            lbl = tk.Label(cell, text="-", bg=C_PANEL2, fg=C_TEXT,
                           font=("Helvetica", 11, "bold"))
            lbl.pack()
            self.mode_slot_labels.append((cell, lbl))

        ttk.Label(lf2, style="Dim.TLabel", text=(
            "FS-i6X notu: 3 konumlu SWC anahtari yalnizca 3 dilime dusar "
            "(genelde FLTMODE1/4/6). 6 mod icin i6X'te iki anahtari MIX ile tek "
            "kanala bindirmek gerekir. Mod adlarini 'Anahtarlar / Modlar' "
            "sekmesinden atayin; bu tablo canli olarak hangi dilimin secili "
            "oldugunu gosterir.")).pack(anchor="w", pady=(8, 0))

        ttk.Label(f, style="Dim.TLabel", text=(
            "AUX butonlari (SWA/SWB/SWD vb.): once kumandada Functions > Aux "
            "channels menusunden anahtari bos bir kanala (CH5-CH10) atayin, "
            "sonra 'Anahtarlar / Modlar' sekmesinde o kanalin RCx_OPTION'ina "
            "istediginiz fonksiyonu (RTL, ArmDisarm, AutoTune...) secin."
        )).pack(anchor="w", pady=8)

    def _read_rcmap_params(self):
        for fn in ("ROLL", "PITCH", "THROTTLE", "YAW"):
            self.mav.request_param(f"RCMAP_{fn}")
        self.mav.request_param("FLTMODE_CH")
        for i in range(1, 7):
            self.mav.request_param(f"FLTMODE{i}")
        self._log("RCMAP ve FLTMODE parametreleri istendi.")

    def _set_rcmap(self, fn):
        try:
            val = float(int(self.rcmap_vars[fn].get().strip()))
        except Exception:
            self._log(f"RCMAP_{fn}: gecersiz kanal numarasi.")
            return
        if not 1 <= val <= NUM_RC_CHANNELS:
            self._log(f"RCMAP_{fn}: kanal 1-{NUM_RC_CHANNELS} araliginda olmali.")
            return
        others = {f: self.rcmap_vars[f].get().strip()
                  for f in self.rcmap_vars if f != fn}
        if str(int(val)) in others.values():
            if not messagebox.askyesno("Cakisma",
                    f"Kanal {int(val)} baska bir eksene de atanmis gorunuyor. "
                    "Yine de yazilsin mi?"):
                return
        if messagebox.askyesno("Onay",
                f"RCMAP_{fn} = {int(val)} yazilacak.\n\n"
                "Degisikligin etkin olmasi icin FC REBOOT gerekir. Devam?"):
            self.mav.set_param(f"RCMAP_{fn}", val)

    def _set_map_fltch(self):
        try:
            val = float(int(self.map_fltch_var.get().strip()))
        except Exception:
            self._log("FLTMODE_CH: gecersiz deger.")
            return
        self.mav.set_param("FLTMODE_CH", val)

    # -- kanal tespiti -----------------------------------------------------
    def _start_detect(self, fn):
        if self.detect_active:
            return
        self.detect_active = fn
        self.detect_base = list(self.rc_last)
        self.detect_dev = [0] * NUM_RC_CHANNELS
        pretty = "Mod anahtari" if fn == "FLTMODE_CH" else f"RCMAP_{fn}"
        self.detect_banner.configure(fg=C_ACCENT)
        self.detect_banner.configure(
            text=f">> {pretty}: SIMDI ilgili stick/anahtari 3 saniye boyunca "
                 "uclara hareket ettirin...")
        for b in self.detect_btns.values():
            b.state(["disabled"])
        self.after(3000, self._finish_detect)

    def _finish_detect(self):
        fn = self.detect_active
        self.detect_active = None
        for b in self.detect_btns.values():
            b.state(["!disabled"])
        if not fn or self.detect_dev is None:
            return
        pretty = "Mod anahtari" if fn == "FLTMODE_CH" else f"RCMAP_{fn}"
        best = max(range(NUM_RC_CHANNELS), key=lambda i: self.detect_dev[i])
        dev = self.detect_dev[best]
        if dev < 60:
            hint = ""
            if fn == "FLTMODE_CH":
                hint = (" Ipucu: anahtar kumandada hicbir kanala atanmamis "
                        "olabilir - i6X'te Functions > Aux channels ekranindan "
                        "SWC'yi bir kanala (orn. Channel 5) atayin.")
            self.detect_banner.configure(fg=C_WARN)
            self.detect_banner.configure(
                text=f"{pretty}: hareket algilanmadi (maks sapma {dev} PWM)."
                     + hint)
            return
        ch = best + 1
        if fn == "FLTMODE_CH":
            self.map_fltch_var.set(str(ch))
        else:
            self.rcmap_vars[fn].set(str(ch))
        self.detect_banner.configure(fg=C_GOOD)
        self.detect_banner.configure(
            text=f"{pretty}: CH{ch} tespit edildi (sapma {dev} PWM). "
                 "SET ile yazabilirsiniz.")
        self.detect_base = self.detect_dev = None

    # -- RC Ayarlari -------------------------------------------------------
    def _tab_rcset(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=10)
        f.pack(fill="both", expand=True)
        bar = ttk.Frame(f, style="Panel.TFrame")
        bar.pack(fill="x", pady=4)
        ttk.Button(bar, text="RC Parametrelerini Oku",
                   command=self._read_rc_params).pack(side="left")
        ttk.Label(bar, style="Dim.TLabel", text=(
            "  REVERSED: 0=Normal 1=Ters | Ters cevirme ham PWM'i degistirmez, "
            "FC'nin yorumunu degistirir (RC Kanallari sekmesindeki YORUM sutunu)."
        )).pack(side="left")

        hdr = ttk.Frame(f, style="Panel.TFrame")
        hdr.pack(fill="x", pady=(6, 0))
        ttk.Label(hdr, text="Kanal", style="Head.TLabel", width=8).pack(side="left")
        for fld in RC_FIELDS:
            ttk.Label(hdr, text=fld, style="Head.TLabel", width=11).pack(side="left")

        for ch in range(1, NUM_RC_CHANNELS + 1):
            row = ttk.Frame(f, style="Panel.TFrame")
            row.pack(fill="x", pady=1)
            ttk.Label(row, text=f"RC{ch}", style="Panel.TLabel", width=8).pack(side="left")
            for fld in RC_FIELDS:
                v = tk.StringVar(value="-")
                self.rc_param_vars[(ch, fld)] = v
                ttk.Entry(row, textvariable=v, width=10).pack(side="left", padx=2)
            ttk.Button(row, text="SET",
                       command=lambda c=ch: self._set_rc_params(c)).pack(side="left", padx=8)

    # -- Anahtarlar / Modlar ----------------------------------------------
    def _tab_switches(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=12)
        f.pack(fill="both", expand=True)
        ttk.Button(f, text="Anahtar/Mod Parametrelerini Oku",
                   command=self._read_switch_params).grid(row=0, column=0,
                                                          columnspan=2, sticky="w", pady=6)

        lf1 = ttk.LabelFrame(f, text="Ucus Modu Anahtari (FLTMODE1-6)", padding=10)
        lf1.grid(row=1, column=0, sticky="nw", padx=6, pady=6)
        mode_values = [mode_label(k) for k in sorted(COPTER_MODES)]
        for i in range(1, 7):
            ttk.Label(lf1, text=f"FLTMODE{i}", style="Panel.TLabel"
                      ).grid(row=i, column=0, sticky="w", pady=3)
            v = tk.StringVar(value="-")
            self.fltmode_vars[i] = v
            ttk.Combobox(lf1, textvariable=v, values=mode_values,
                         width=22).grid(row=i, column=1, padx=6)
            ttk.Button(lf1, text="SET",
                       command=lambda n=i: self._set_fltmode(n)).grid(row=i, column=2)
        ttk.Label(lf1, text="FLTMODE_CH", style="Panel.TLabel"
                  ).grid(row=7, column=0, sticky="w", pady=3)
        self.fltmode_ch_var = tk.StringVar(value="-")
        ttk.Entry(lf1, textvariable=self.fltmode_ch_var, width=6
                  ).grid(row=7, column=1, sticky="w", padx=6)
        ttk.Button(lf1, text="SET", command=self._set_fltmode_ch).grid(row=7, column=2)

        lf2 = ttk.LabelFrame(f, text="AUX Anahtar Fonksiyonlari (RCx_OPTION)", padding=10)
        lf2.grid(row=1, column=1, sticky="nw", padx=6, pady=6)
        opt_values = [opt_label(k) for k in sorted(RC_OPTIONS)]
        for r, ch in enumerate(range(5, NUM_RC_CHANNELS + 1)):
            ttk.Label(lf2, text=f"RC{ch}_OPTION", style="Panel.TLabel"
                      ).grid(row=r, column=0, sticky="w", pady=2)
            v = tk.StringVar(value="-")
            self.option_vars[ch] = v
            ttk.Combobox(lf2, textvariable=v, values=opt_values,
                         width=26).grid(row=r, column=1, padx=6)
            ttk.Button(lf2, text="SET",
                       command=lambda c=ch: self._set_option(c)).grid(row=r, column=2)

    # -- Parametreler ------------------------------------------------------
    def _tab_params(self, root):
        f = ttk.Frame(root, style="Panel.TFrame", padding=10)
        f.pack(fill="both", expand=True)
        bar = ttk.Frame(f, style="Panel.TFrame")
        bar.pack(fill="x", pady=4)
        ttk.Label(bar, text="Ara / Ad:", style="Panel.TLabel").pack(side="left")
        self.search_var = tk.StringVar()
        e = ttk.Entry(bar, textvariable=self.search_var, width=22)
        e.pack(side="left", padx=4)
        e.bind("<KeyRelease>", lambda _e: self._filter_params())
        ttk.Button(bar, text="Oku", command=self._read_one_param).pack(side="left")
        ttk.Label(bar, text="  Deger:", style="Panel.TLabel").pack(side="left")
        self.setval_var = tk.StringVar()
        ttk.Entry(bar, textvariable=self.setval_var, width=12).pack(side="left", padx=4)
        ttk.Button(bar, text="Yaz (SET)", command=self._write_one_param).pack(side="left")
        ttk.Button(bar, text="TUMUNU OKU",
                   command=self.mav.request_all_params).pack(side="right")

        cols = ("name", "value")
        self.tree = ttk.Treeview(f, columns=cols, show="headings")
        self.tree.heading("name", text="Parametre")
        self.tree.heading("value", text="Deger")
        self.tree.column("name", width=320)
        self.tree.column("value", width=180)
        ys = ttk.Scrollbar(f, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=ys.set)
        self.tree.pack(side="left", fill="both", expand=True, pady=4)
        ys.pack(side="right", fill="y")
        self.tree.bind("<Double-1>", self._on_tree_dblclick)

    # -- Log ---------------------------------------------------------------
    def _tab_log(self, root):
        f = tk.Frame(root, bg=C_LOG_BG)
        f.pack(fill="both", expand=True, padx=8, pady=8)
        bar = tk.Frame(f, bg=C_LOG_BG)
        bar.pack(fill="x")
        tk.Button(bar, text="Temizle", command=self._clear_log,
                  bg=C_PANEL2, fg=C_TEXT, relief="flat",
                  highlightbackground=C_LOG_BG).pack(side="right", padx=4, pady=4)
        body = tk.Frame(f, bg=C_LOG_BG)
        body.pack(fill="both", expand=True)
        self.log_text = tk.Text(body, bg=C_LOG_BG, fg=C_LOG_FG,
                                insertbackground=C_LOG_FG,
                                font=("Menlo", 12), relief="flat", wrap="none")
        lys = tk.Scrollbar(body, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=lys.set, state="disabled")
        self.log_text.pack(side="left", fill="both", expand=True)
        lys.pack(side="right", fill="y")

    def _clear_log(self):
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")

    # -- eylemler ----------------------------------------------------------
    def _connect(self):
        self.mav.connect(self.conn_var.get().strip())

    def _toggle_arm(self):
        if self.armed:
            if messagebox.askyesno("DISARM Onayi",
                    "Arac DISARM edilecek. Havadaysa motorlar DURUR!\n\n"
                    "Devam edilsin mi?"):
                self.mav.arm_disarm(False)
        else:
            if messagebox.askyesno("ARM Onayi",
                    "Arac ARM edilecek - motorlar donmeye baslayabilir.\n\n"
                    "Cevre guvenli mi? Devam edilsin mi?"):
                self.mav.arm_disarm(True)

    def _read_rc_params(self):
        for ch in range(1, NUM_RC_CHANNELS + 1):
            for fld in RC_FIELDS:
                self.mav.request_param(f"RC{ch}_{fld}")
        self._log("RC1-16 parametreleri istendi.")

    def _set_rc_params(self, ch):
        if not messagebox.askyesno("Onay",
                f"RC{ch} parametreleri yazilacak. Arac DISARM mi?"):
            return
        for fld in RC_FIELDS:
            raw = self.rc_param_vars[(ch, fld)].get().strip()
            if raw in ("", "-"):
                continue
            try:
                val = float(raw)
            except ValueError:
                self._log(f"RC{ch}_{fld}: gecersiz deger '{raw}', atlandi.")
                continue
            self.mav.set_param(f"RC{ch}_{fld}", val)

    def _read_switch_params(self):
        for i in range(1, 7):
            self.mav.request_param(f"FLTMODE{i}")
        self.mav.request_param("FLTMODE_CH")
        for ch in range(5, NUM_RC_CHANNELS + 1):
            self.mav.request_param(f"RC{ch}_OPTION")
        self._log("FLTMODE ve RCx_OPTION parametreleri istendi.")

    @staticmethod
    def _leading_int(s):
        s = s.strip()
        if ":" in s:
            s = s.split(":", 1)[0]
        return float(int(s))

    def _set_fltmode(self, n):
        try:
            self.mav.set_param(f"FLTMODE{n}",
                               self._leading_int(self.fltmode_vars[n].get()))
        except Exception:
            self._log(f"FLTMODE{n}: gecersiz secim.")

    def _set_fltmode_ch(self):
        try:
            self.mav.set_param("FLTMODE_CH", float(self.fltmode_ch_var.get().strip()))
        except Exception:
            self._log("FLTMODE_CH: gecersiz deger.")

    def _set_option(self, ch):
        try:
            self.mav.set_param(f"RC{ch}_OPTION",
                               self._leading_int(self.option_vars[ch].get()))
        except Exception:
            self._log(f"RC{ch}_OPTION: gecersiz secim.")

    def _read_one_param(self):
        name = self.search_var.get().strip().upper()
        if name:
            self.mav.request_param(name)

    def _write_one_param(self):
        name = self.search_var.get().strip().upper()
        raw = self.setval_var.get().strip()
        if not name or not raw:
            return
        try:
            val = float(raw)
        except ValueError:
            self._log(f"Gecersiz deger: {raw}")
            return
        if messagebox.askyesno("Onay", f"{name} = {val} yazilsin mi?"):
            self.mav.set_param(name, val)

    def _on_tree_dblclick(self, _ev):
        sel = self.tree.selection()
        if sel:
            name, value = self.tree.item(sel[0], "values")
            self.search_var.set(name)
            self.setval_var.set(value)

    def _filter_params(self):
        flt = self.search_var.get().strip().upper()
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.param_rows.clear()
        for name in sorted(self.all_params):
            if flt and flt not in name:
                continue
            sval = f"{self.all_params[name]:.4f}".rstrip("0").rstrip(".")
            self.param_rows[name] = self.tree.insert("", "end", values=(name, sval))

    # -- kuyruk ------------------------------------------------------------
    def _poll_queue(self):
        try:
            while True:
                kind, data = self.ui_queue.get_nowait()
                self._handle(kind, data)
        except queue.Empty:
            pass
        self.after(50, self._poll_queue)

    def _handle(self, kind, data):
        if kind == "log":
            self._log(data)
        elif kind == "conn":
            if data:
                self.link_var.set("BAGLI")
                self.link_lbl.configure(fg=C_GOOD)
                self._read_rc_params()          # yorum sutunu icin otomatik oku
                self._read_rcmap_params()       # atama sekmesi icin otomatik oku
            else:
                self.link_var.set("BAGLI DEGIL")
                self.link_lbl.configure(fg=C_BAD)
        elif kind == "heartbeat":
            self.armed = data["armed"]
            arm = "ARMED" if self.armed else "DISARMED"
            self.status_var.set(f"{data['mode']}  |  {arm}")
            self.tel_vars["mode"].set(data["mode"])
            self.tel_vars["armed"].set(arm)
            if self.armed:
                self.arm_btn.configure(text="ARMED  (DISARM icin tikla)",
                                       bg="#4a1f1c", fg=C_BAD,
                                       activebackground="#5e2823",
                                       activeforeground=C_BAD)
            else:
                self.arm_btn.configure(text="DISARMED  (ARM icin tikla)",
                                       bg="#233326", fg=C_GOOD,
                                       activebackground="#2e4433",
                                       activeforeground=C_GOOD)
        elif kind == "rc":
            self.rc_last = data
            for i, v in enumerate(data):
                self.rc_bars[i].set(v)
                self.rc_raw_lbl[i].set(str(v) if v else "-")
                iv = self._interp(i + 1, v)
                self.rc_ibars[i].set(iv)
                self.rc_int_lbl[i].set(f"{iv:+.0f}" if iv is not None else "-")
            # kanal tespiti aktifse sapmalari topla
            if self.detect_active and self.detect_base:
                for i, v in enumerate(data):
                    if v and self.detect_base[i]:
                        d = abs(v - self.detect_base[i])
                        if d > self.detect_dev[i]:
                            self.detect_dev[i] = d
            self._update_mode_slot()
        elif kind == "servo":
            for i, v in enumerate(data):
                if i < len(self.motor_bars):
                    self.motor_bars[i].set(v)
                    self.motor_lbl[i].set(str(v) if v else "-")
        elif kind == "battery":
            parts = []
            if data["voltage"] is not None:
                parts.append(f"{data['voltage']:.2f}V")
            if data["current"] is not None:
                parts.append(f"{data['current']:.1f}A")
            if data["remaining"] is not None:
                parts.append(f"%{data['remaining']}")
            self.tel_vars["battery"].set(" ".join(parts) or "-")
        elif kind == "attitude":
            self.att_ind.update_att(data["roll"], data["pitch"])
            self.tel_vars["yaw"].set(f"{data['yaw']:.0f} deg")
        elif kind == "vfr":
            self.tel_vars["alt"].set(f"{data['alt']:.1f} m")
            self.tel_vars["climb"].set(f"{data['climb']:+.1f} m/s")
            self.tel_vars["thr"].set(f"%{data['throttle']}")
            self.hsi.update_hsi(data["heading"], data["groundspeed"])
        elif kind == "gps":
            fixes = {0: "Yok", 1: "Yok", 2: "2D", 3: "3D", 4: "DGPS",
                     5: "RTK Flt", 6: "RTK Fix"}
            self.tel_vars["gps"].set(
                f"{fixes.get(data['fix'], data['fix'])} / {data['sats']} uydu")
        elif kind == "param":
            self._apply_param(data["name"], data["value"])

    def _apply_param(self, name, value):
        self.all_params[name] = value
        sval = f"{value:.4f}".rstrip("0").rstrip(".")
        flt = self.search_var.get().strip().upper() if hasattr(self, "search_var") else ""
        if name in self.param_rows:
            self.tree.item(self.param_rows[name], values=(name, sval))
        elif not flt or flt in name:
            self.param_rows[name] = self.tree.insert("", "end", values=(name, sval))

        if name.startswith("RCMAP_"):
            fn = name[6:]
            if fn in getattr(self, "rcmap_vars", {}):
                self.rcmap_vars[fn].set(str(int(value)))
        elif name.startswith("RC") and "_" in name:
            head, fld = name.split("_", 1)
            try:
                ch = int(head[2:])
            except ValueError:
                return
            if fld == "OPTION" and ch in self.option_vars:
                self.option_vars[ch].set(opt_label(value))
            elif (ch, fld) in self.rc_param_vars:
                self.rc_param_vars[(ch, fld)].set(sval)
        elif name.startswith("FLTMODE"):
            if name == "FLTMODE_CH":
                self.fltmode_ch_var.set(sval)
                if hasattr(self, "map_fltch_var"):
                    self.map_fltch_var.set(str(int(value)))
            else:
                try:
                    n = int(name[7:])
                    if n in self.fltmode_vars:
                        self.fltmode_vars[n].set(mode_label(value))
                    if hasattr(self, "mode_slot_labels") and 1 <= n <= 6:
                        _, lbl = self.mode_slot_labels[n - 1]
                        lbl.configure(text=COPTER_MODES.get(int(value), "?"))
                except ValueError:
                    pass

    def _update_mode_slot(self):
        """Mod kanalinin PWM'ine gore aktif FLTMODE dilimini vurgula."""
        ch = self.all_params.get("FLTMODE_CH")
        if ch is None:
            return
        ch = int(ch)
        if not 1 <= ch <= NUM_RC_CHANNELS:
            return
        pwm = self.rc_last[ch - 1]
        if not pwm:
            return
        if pwm <= 1230:
            slot = 1
        elif pwm <= 1360:
            slot = 2
        elif pwm <= 1490:
            slot = 3
        elif pwm <= 1620:
            slot = 4
        elif pwm <= 1749:
            slot = 5
        else:
            slot = 6
        mname = COPTER_MODES.get(int(self.all_params.get(f"FLTMODE{slot}", -1)), "?")
        self.mode_live.set(f"CH{ch} = {pwm}  ->  Aktif dilim: FLTMODE{slot} ({mname})")
        for i, (cell, lbl) in enumerate(self.mode_slot_labels, start=1):
            mv = self.all_params.get(f"FLTMODE{i}")
            lbl.configure(text=COPTER_MODES.get(int(mv), "?") if mv is not None else "-")
            if i == slot:
                cell.configure(bg="#1f3a2a", highlightbackground=C_GOOD)
                for w in cell.winfo_children():
                    w.configure(bg="#1f3a2a")
            else:
                cell.configure(bg=C_PANEL2, highlightbackground=C_BORDER)
                for w in cell.winfo_children():
                    w.configure(bg=C_PANEL2)

    def _log(self, text):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", time.strftime("[%H:%M:%S] ") + str(text) + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def destroy(self):
        self.mav.disconnect()
        super().destroy()


if __name__ == "__main__":
    App().mainloop()
