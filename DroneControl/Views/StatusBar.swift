//
//  StatusBar.swift
//  DroneControl
//

import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Connection
            HStack(spacing: 5) {
                Circle()
                    .fill(mavlinkManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(mavlinkManager.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Armed
            HStack(spacing: 5) {
                Image(systemName: mavlinkManager.isArmed ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(mavlinkManager.isArmed ? .orange : .gray)
                Text(mavlinkManager.isArmed ? "ARMED" : "DISARMED")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(mavlinkManager.isArmed ? .orange : .gray)
            }
            
            Spacer()
            
            // Mode
            Text(mavlinkManager.droneState.flightMode.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(mavlinkManager.droneState.flightMode.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(mavlinkManager.droneState.flightMode.color.opacity(0.2))
                .cornerRadius(6)
        }
        .padding(.vertical, 7)
    }
}
