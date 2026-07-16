import Foundation
import os

private let log = Logger.tinyGreen("Morse")

final class Morse {
    private(set) var isPlaying: Bool = false
    private(set) var currentPhase: Bool = false
    private var timer: Timer?
    private var index: Int = 0

    private enum MorseUnit {
        case dot, dash
        var onUnits: Int { self == .dash ? 3 : 1 }
    }

    static func buildSequence() -> [Bool] {
        let letters: [[MorseUnit]] = [
            [.dash],
            [.dot, .dot],
            [.dash, .dot],
            [.dash, .dot, .dash, .dash],
            [.dash, .dash, .dot],
            [.dot, .dash, .dot],
            [.dot],
            [.dot],
            [.dash, .dot]
        ]
        var seq: [Bool] = []
        for (li, letter) in letters.enumerated() {
            for (di, unit) in letter.enumerated() {
                seq.append(contentsOf: Array(repeating: true, count: unit.onUnits))
                if di < letter.count - 1 {
                    seq.append(false)
                }
            }
            if li < letters.count - 1 {
                seq.append(contentsOf: [false, false, false])
            }
        }
        return seq
    }

    private static let cachedSequence: [Bool] = buildSequence()

    func trigger() {
        guard !isPlaying else { return }
        isPlaying = true
        index = 0
        currentPhase = false
        let total = Self.cachedSequence.count
        log.info("Easter Egg 시작 — \(total, privacy: .public) units (약 \(total / 5, privacy: .public)초)")
        broadcast()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let seq = Self.cachedSequence
        guard index < seq.count else {
            stop()
            return
        }
        currentPhase = seq[index]
        index += 1
        broadcast()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isPlaying else { return }
        isPlaying = false
        currentPhase = false
        log.info("Easter Egg 종료")
        broadcast()
    }

    private func broadcast() {
        NotificationCenter.default.post(
            name: .tinyGreenEasterEggChanged,
            object: nil,
            userInfo: [
                Notification.easterEggActiveKey: isPlaying,
                Notification.easterEggPhaseKey: currentPhase
            ]
        )
    }
}
