//
//  AttitudeIndicator.swift
//  DroneControl
//

import SwiftUI

struct AttitudeIndicator: View {
    let roll: Float
    let pitch: Float
    let heading: Float
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                // Background circle
                Circle()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.15))
                    .frame(width: size, height: size)
                
                // Horizon
                ZStack {
                    // Sky (blue)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.4, blue: 0.8),
                                    Color(red: 0.4, green: 0.6, blue: 0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 2, height: size)
                        .offset(y: -size / 2)
                    
                    // Ground (brown)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.3, blue: 0.2),
                                    Color(red: 0.3, green: 0.2, blue: 0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 2, height: size)
                        .offset(y: size / 2)
                    
                    // Horizon line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: size * 2, height: 3)
                    
                    // Pitch ladder
                    PitchLadder(size: size)
                }
                .frame(width: size, height: size)
                .offset(y: CGFloat(pitch) * size / 60.0)
                .rotationEffect(.degrees(Double(-roll)))
                .clipShape(Circle())
                
                // Center reference mark (aircraft symbol)
                ZStack {
                    // Horizontal bars
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: size * 0.15, height: 3)
                        
                        Spacer()
                            .frame(width: size * 0.1)
                        
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: size * 0.15, height: 3)
                    }
                    
                    // Center dot
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                    
                    // Vertical line
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 3, height: size * 0.08)
                        .offset(y: size * 0.04)
                }
                
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: size, height: size)
                
                // Roll indicator arc
                RollIndicator(roll: roll, size: size)
                
                // Compass rose (cardinal marks)
                CompassRose(heading: heading, size: size)
                
                // Heading compass at top
                VStack(spacing: 4) {
                    // Cardinal direction
                    Text(cardinalDirection(heading))
                        .font(.system(size: size * 0.06, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.2, green: 0.4, blue: 0.8))
                        )
                    
                    // Numeric heading
                    Text("\(Int(heading))°")
                        .font(.system(size: size * 0.08, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.cyan, lineWidth: 1.5)
                                )
                        )
                }
                .offset(y: -size * 0.58)
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    
    private func cardinalDirection(_ heading: Float) -> String {
        let h = Int(heading)
        switch h {
        case 337...360, 0..<23: return "N"
        case 23..<68: return "NE"
        case 68..<113: return "E"
        case 113..<158: return "SE"
        case 158..<203: return "S"
        case 203..<248: return "SW"
        case 248..<293: return "W"
        case 293..<337: return "NW"
        default: return "N"
        }
    }
}

struct PitchLadder: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            ForEach([-20, -10, 10, 20], id: \.self) { pitch in
                PitchLine(angle: pitch, size: size)
            }
        }
    }
}

struct PitchLine: View {
    let angle: Int
    let size: CGFloat
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(abs(angle))")
                .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            Rectangle()
                .fill(Color.white)
                .frame(width: size * 0.3, height: 2)
            
            Text("\(abs(angle))")
                .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
        .offset(y: CGFloat(-angle) * size / 60.0)
    }
}

struct RollIndicator: View {
    let roll: Float
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Roll marks
            ForEach([0, 10, 20, 30, 45, 60], id: \.self) { angle in
                // Positive side
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: angle == 0 || angle == 30 || angle == 60 ? size * 0.08 : size * 0.05)
                    .offset(y: -size * 0.46)
                    .rotationEffect(.degrees(Double(angle)))
                
                // Negative side
                if angle != 0 {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: angle == 30 || angle == 60 ? size * 0.08 : size * 0.05)
                        .offset(y: -size * 0.46)
                        .rotationEffect(.degrees(Double(-angle)))
                }
            }
            
            // Roll pointer (yellow triangle)
            Path { path in
                let w = size * 0.04
                let h = size * 0.06
                path.move(to: CGPoint(x: 0, y: -size * 0.5))
                path.addLine(to: CGPoint(x: -w, y: -size * 0.5 + h))
                path.addLine(to: CGPoint(x: w, y: -size * 0.5 + h))
                path.closeSubpath()
            }
            .fill(Color.yellow)
            .rotationEffect(.degrees(Double(-roll)))
        }
    }
}

struct CompassRose: View {
    let heading: Float
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Cardinal directions
            ForEach([("N", 0), ("E", 90), ("S", 180), ("W", 270)], id: \.1) { direction, angle in
                VStack(spacing: 2) {
                    Text(direction)
                        .font(.system(size: size * 0.05, weight: .bold))
                        .foregroundColor(direction == "N" ? .red : .white)
                    
                    Rectangle()
                        .fill(direction == "N" ? Color.red : Color.white)
                        .frame(width: 2, height: size * 0.04)
                }
                .offset(y: -size * 0.54)
                .rotationEffect(.degrees(Double(angle) - Double(heading)))
            }
            
            // Intercardinal directions
            ForEach([("NE", 45), ("SE", 135), ("SW", 225), ("NW", 315)], id: \.1) { direction, angle in
                VStack(spacing: 1) {
                    Text(direction)
                        .font(.system(size: size * 0.04, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 1, height: size * 0.03)
                }
                .offset(y: -size * 0.54)
                .rotationEffect(.degrees(Double(angle) - Double(heading)))
            }
        }
    }
}

// Compact version for smaller spaces
struct CompactAttitudeIndicator: View {
    let roll: Float
    let pitch: Float
    let heading: Float
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                Circle()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.15))
                
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.2, green: 0.4, blue: 0.8))
                        .frame(width: size * 2, height: size)
                        .offset(y: -size / 2)
                    
                    Rectangle()
                        .fill(Color(red: 0.4, green: 0.3, blue: 0.2))
                        .frame(width: size * 2, height: size)
                        .offset(y: size / 2)
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: size * 2, height: 2)
                }
                .offset(y: CGFloat(pitch) * size / 80.0)
                .rotationEffect(.degrees(Double(-roll)))
                .clipShape(Circle())
                
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: size * 0.2, height: 2)
                    
                    Spacer()
                        .frame(width: size * 0.15)
                    
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: size * 0.2, height: 2)
                }
                
                Circle()
                    .stroke(Color.white, lineWidth: 1)
                
                // Heading display
                Text("\(Int(heading))°")
                    .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.cyan, lineWidth: 1)
                            )
                    )
                    .offset(y: -size * 0.52)
            }
            .frame(width: size, height: size)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AttitudeIndicator(roll: 15, pitch: -10, heading: 245)
            .frame(width: 300, height: 300)
        
        CompactAttitudeIndicator(roll: -8, pitch: 5, heading: 120)
            .frame(width: 120, height: 120)
    }
    .padding()
    .background(Color.black)
}
