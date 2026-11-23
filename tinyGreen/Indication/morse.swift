import Foundation
import os

private let log = Logger.tinyGreen("Morse")

/// 한국어 모드 Shift+Caps → 메뉴바 + 키보드 LED 가 모스 부호로 "tinygreen" 점멸.
/// 약 71 단위 × 200ms = ~14.2초. 진행 중 추가 트리거는 무시 (재시작 없음).
/// 진행 중에도 일반 키 입력 / 한영 전환 / Shift Lock 동작은 평소대로.
/// LED 와 메뉴바 인디케이터의 평소 동작은 ~14.2초간 잠시 멈춤 — Easter Egg 가 점유.
///
/// About 글의 "작은 초록빛과 함께" 와 한 몸 — 빛이 자기 이름을 모스로 말하는 일.
final class Morse {
    private(set) var isPlaying: Bool = false
    private(set) var currentPhase: Bool = false
    private var timer: Timer?
    private var index: Int = 0

    /// 모스 부호의 한 단위 — dot (1 ON unit) 또는 dash (3 ON units).
    /// String 대신 enum 으로 typo 컴파일 시 catch.
    private enum MorseUnit {
        case dot, dash
        var onUnits: Int { self == .dash ? 3 : 1 }
    }

    /// 모스 부호 — tinygreen
    /// 단점=1단위 ON, 장점=3단위 ON, 점 사이=1단위 OFF, 글자 사이=3단위 OFF (단위 = 200ms)
    /// t=- i=.. n=-. y=-.-- g=--. r=.-. e=. e=. n=-.
    /// internal — 유닛 테스트가 시퀀스를 역디코드해 모스 문자열 회귀를 잡는다.
    static func buildSequence() -> [Bool] {
        let letters: [[MorseUnit]] = [
            [.dash],                          // t
            [.dot, .dot],                     // i
            [.dash, .dot],                    // n
            [.dash, .dot, .dash, .dash],      // y
            [.dash, .dash, .dot],             // g
            [.dot, .dash, .dot],              // r
            [.dot],                           // e
            [.dot],                           // e
            [.dash, .dot]                     // n
        ]
        var seq: [Bool] = []
        for (li, letter) in letters.enumerated() {
            for (di, unit) in letter.enumerated() {
                seq.append(contentsOf: Array(repeating: true, count: unit.onUnits))
                if di < letter.count - 1 {
                    seq.append(false)  // 점 사이 1단위 OFF
                }
            }
            if li < letters.count - 1 {
                seq.append(contentsOf: [false, false, false])  // 글자 사이 3단위 OFF
            }
        }
        return seq
    }

    private static let cachedSequence: [Bool] = buildSequence()

    /// 한국어 모드 Shift+Caps 트리거. 진행 중이면 무시.
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
        // .common — default 모드 타이머는 메뉴 트래킹·모달 중 멈춰 모스 진행이 얼어붙는다.
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

    /// 정상 종료 (시퀀스 끝) 또는 외부 reset (앱 종료 시).
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
