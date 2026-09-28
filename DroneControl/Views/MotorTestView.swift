//
//  MotorTestView.swift
//  DroneControl
//
//  Quad X motor test - MAV_CMD_DO_MOTOR_TEST ile her motoru ayri ayri
//  1000-2000 us PWM arasinda calistirir.
//
//  Fiziksel baglanti (Pixhawk PWM cikisi -> motor):
//    PWM1 -> M1 on sag  (CCW)
//    PWM2 -> M2 arka sol (CCW)
//    PWM3 -> M3 on sol  (CW)
//    PWM4 -> M4 arka sag (CW)
//
//  ArduCopter motor testinde param1 motor cikis numarasi DEGIL, test sirasidir
//  (A=1 on sag, B=2 arka sag, C=3 arka sol, D=4 on sol - saat yonunde).
//  Bu yuzden M1->1, M4->2, M2->3, M3->4 esleme yapilir.
//

import SwiftUI
import Combine

// MARK: - Motor tanimi
struct QuadMotor: Identifiable {
    let id: Int             // M numarasi (MOT_x)
    let position: String    // fiziksel konum
    let pwmChannel: Int     // Pixhawk PWM cikisi (SERVOn)
    let testSeq: UInt8      // ArduCopter motor test sirasi (param1)
    let rotation: String    // donus yonu
    
    static let quadX: [QuadMotor] = [
        QuadMotor(id: 1, position: "Front Right", pwmChannel: 1, testSeq: 1, rotation: "CCW"),
        QuadMotor(id: 2, position: "Rear Left",   pwmChannel: 2, testSeq: 3, rotation: "CCW"),
        QuadMotor(id: 3, position: "Front Left",  pwmChannel: 3, testSeq: 4, rotation: "CW"),
        QuadMotor(id: 4, position: "Rear Right",  pwmChannel: 4, testSeq: 2, rotation: "CW")
    ]
    
    static func motor(_ id: Int) -> QuadMotor {
        quadX.first { $0.id == id }!
    }
}

// MARK: - Motor Test View
struct MotorTestView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    // Her motor icin slider degeri (us)
    @State private var pwmValues: [Int: Double] = [1: 1000, 2: 1000, 3: 1000, 4: 1000]
    // Su anda calisan motor (ArduCopter ayni anda tek motor test eder)
    @State private var runningMotor: Int? = nil
    // Keepalive: FC tarafinda timeout kisa tutulur, komut periyodik yenilenir.
    // Uygulama kapanir/baglanti koparsa motor en gec keepaliveTimeout sonra durur.
    private let keepaliveInterval: TimeInterval = 1.0
    private let keepaliveTimeout: Float = 3.0
    @State private var keepaliveTimer: Timer? = nil
    
    // Motor testi sirasinda ArduCopter kendi icinde ARM eder ve heartbeat "armed" gosterir;
    // bu bizim baslattigimiz test ise engel degildir (isArmedByPilot bunu ayirt eder).
    private var canTest: Bool {
        mavlinkManager.isConnected && !mavlinkManager.isArmedByPilot
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                safetyCard
                
                if !mavlinkManager.isConnected {
                    warningBanner("Not connected", color: .red)
                } else if mavlinkManager.isArmedByPilot {
                    warningBanner("Vehicle is ARMED - disarm before motor test", color: .red)
                } else if mavlinkManager.motorTestActive {
                    warningBanner("Motor test active - FC reports ARMED during test, this is normal", color: .orange)
                }
                
                // Quad X yerlesimi: ust satir on, alt satir arka
                HStack(spacing: 12) {
                    motorCard(.motor(3))   // on sol
                    motorCard(.motor(1))   // on sag
                }
                HStack(spacing: 12) {
                    motorCard(.motor(2))   // arka sol
                    motorCard(.motor(4))   // arka sag
                }
                
                mappingCard
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.18),
                    Color(red: 0.09, green: 0.13, blue: 0.24)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onDisappear { stopAll() }
        .onChange(of: mavlinkManager.isConnected) { connected in
            if !connected { stopAll(sendCommand: false) }
        }
    }
    
    // MARK: - Safety
    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Motor Test")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if runningMotor != nil {
                    Text("RUNNING M\(runningMotor!)")
                        .font(.caption).bold()
                        .foregroundColor(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(6)
                }
            }
            
            stopAllButton
            
            HStack {
                Text("Last ACK:")
                    .font(.caption)
                    .foregroundColor(.gray)
                if let ok = mavlinkManager.motorTestAckAccepted {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(ok ? .green : .red)
                    Text(mavlinkManager.motorTestAckText)
                        .font(.caption)
                        .foregroundColor(ok ? .green : .red)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Text("keepalive \(Int(keepaliveInterval))s / timeout \(Int(keepaliveTimeout))s")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    private func warningBanner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline).bold()
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(color.opacity(0.6))
            .cornerRadius(8)
    }
    
    // MARK: - Motor card
    private func motorCard(_ motor: QuadMotor) -> some View {
        let isRunning = runningMotor == motor.id
        let feedback = mavlinkManager.servoValues[motor.pwmChannel] ?? 0
        let binding = Binding<Double>(
            get: { pwmValues[motor.id] ?? 1000 },
            set: { newValue in
                pwmValues[motor.id] = newValue
                // Motor calisiyorsa slider hareketi aninda gonderilir
                if isRunning { sendTest(motor) }
            }
        )
        
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("M\(motor.id)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(motor.position)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PWM\(motor.pwmChannel)")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                    Text(motor.rotation)
                        .font(.caption2).bold()
                        .foregroundColor(motor.rotation == "CW" ? .orange : .green)
                }
            }
            
            // Hedef deger
            Text("\(Int(pwmValues[motor.id] ?? 1000))")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(isRunning ? .orange : .white)
            
            Slider(value: binding, in: 1000...2000, step: 10)
                .accentColor(isRunning ? .orange : .cyan)
                .disabled(!canTest)
            
            HStack(spacing: 6) {
                miniPreset("1000", 1000, motor)
                miniPreset("1100", 1100, motor)
                miniPreset("1300", 1300, motor)
                miniPreset("1500", 1500, motor)
            }
            
            // FC'den okunan gercek cikis (SERVO_OUTPUT_RAW)
            HStack {
                Text("Output:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(feedback > 0 ? "\(feedback) us" : "--")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(feedback > 1050 ? .orange : .gray)
                Spacer()
            }
            
            Button(action: {
                if isRunning {
                    stopAll()
                } else {
                    start(motor)
                }
            }) {
                HStack {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    Text(isRunning ? "Stop" : "Run")
                }
                .font(.subheadline).bold()
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isRunning ? Color.red : (canTest ? Color.cyan : Color.gray))
                .cornerRadius(8)
            }
            .disabled(!canTest)
        }
        .padding()
        .background(Color.black.opacity(isRunning ? 0.5 : 0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isRunning ? Color.orange : Color.clear, lineWidth: 2)
        )
        .cornerRadius(12)
    }
    
    private func miniPreset(_ title: String, _ value: Double, _ motor: QuadMotor) -> some View {
        Button(action: {
            pwmValues[motor.id] = value
            if runningMotor == motor.id { sendTest(motor) }
        }) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.25))
                .cornerRadius(6)
        }
        .disabled(!canTest)
    }
    
    // MARK: - Stop all
    private var stopAllButton: some View {
        Button(action: { stopAll() }) {
            HStack {
                Image(systemName: "hand.raised.fill")
                Text("STOP ALL MOTORS")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .cornerRadius(12)
        }
        .disabled(!mavlinkManager.isConnected)
    }
    
    // MARK: - Mapping info
    private var mappingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quad X wiring")
                .font(.caption).bold()
                .foregroundColor(.white)
            ForEach(QuadMotor.quadX) { m in
                HStack {
                    Text("PWM\(m.pwmChannel)")
                        .frame(width: 44, alignment: .leading)
                    Text("M\(m.id)")
                        .frame(width: 28, alignment: .leading)
                    Text(m.position)
                        .frame(width: 90, alignment: .leading)
                    Text(m.rotation)
                        .frame(width: 34, alignment: .leading)
                    Text("test seq \(m.testSeq)")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    // MARK: - Control logic
    private func start(_ motor: QuadMotor) {
        guard canTest else { return }
        // Baska motor calisiyorsa once onu durdur
        if let current = runningMotor, current != motor.id {
            mavlinkManager.stopMotorTest(motorSeq: QuadMotor.motor(current).testSeq)
        }
        runningMotor = motor.id
        sendTest(motor)
        
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: keepaliveInterval, repeats: true) { _ in
            guard let id = runningMotor else { return }
            sendTest(QuadMotor.motor(id))
        }
    }
    
    private func sendTest(_ motor: QuadMotor) {
        let pwm = UInt16(max(1000, min(2000, pwmValues[motor.id] ?? 1000)))
        mavlinkManager.motorTest(motorSeq: motor.testSeq, pwm: pwm, timeoutSec: keepaliveTimeout)
    }
    
    private func stopAll(sendCommand: Bool = true) {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        let seq = runningMotor.map { QuadMotor.motor($0).testSeq } ?? 1
        runningMotor = nil
        if sendCommand && mavlinkManager.isConnected {
            mavlinkManager.stopMotorTest(motorSeq: seq)
        }
    }
}

#Preview {
    MotorTestView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
