//
//  DroneControl-Bridging-Header.h
//  DroneControl
//
//  Bridging header to expose MAVLink C library to Swift
//

#ifndef DroneControl_Bridging_Header_h
#define DroneControl_Bridging_Header_h

// Import MAVLink protocol definitions
// Use the ardupilotmega dialect which includes common + ArduPilot specific messages
#define MAVLINK_USE_MESSAGE_INFO
#define MAVLINK_MAX_DIALECT_PAYLOAD_SIZE 255

// Updated path for MAVLink v2.0 structure
#import "ardupilotmega/mavlink.h"

#endif /* DroneControl_Bridging_Header_h */
