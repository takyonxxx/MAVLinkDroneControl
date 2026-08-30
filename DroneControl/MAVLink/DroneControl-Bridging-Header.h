//
//  DroneControl-Bridging-Header.h
//  DroneControl
//
//  Bridging header to expose MAVLink C library to Swift
//

#ifndef DroneControl_Bridging_Header_h
#define DroneControl_Bridging_Header_h

// ArduPilot'a ozgu mesajlar (EKF_STATUS_REPORT vb.) icin ardupilotmega
// lehcesi kullanilir; common lehcesini kendi icinde zaten icerir.
#include "ardupilotmega/mavlink.h"

#endif /* DroneControl_Bridging_Header_h */
