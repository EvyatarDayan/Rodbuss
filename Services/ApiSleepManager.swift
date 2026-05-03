//
//  ApiSleepManager.swift
//  Rödbuss
//
//  Stops API activity after a configurable awake window.
//

import Foundation
import Combine

enum ApiSleepError: Error, LocalizedError {
    case sleeping

    var errorDescription: String? {
        "Rödbuss went to sleep."
    }
}

@MainActor
final class ApiSleepManager: ObservableObject {
    static let shared = ApiSleepManager()

    private let sleepTimeKey = "apiSleepMinutes"
    private static let defaultSleepMinutes = 10

    @Published private(set) var isSleeping: Bool = false
    @Published private(set) var sleepAfterMinutes: Int = defaultSleepMinutes

    private var sleepTask: Task<Void, Never>?

    private init() {
        let saved = UserDefaults.standard.integer(forKey: sleepTimeKey)
        sleepAfterMinutes = (1...60).contains(saved) ? saved : Self.defaultSleepMinutes
        startCycle()
    }

    func startCycle() {
        guard !isSleeping else { return }
        scheduleSleepTask()
    }

    func wakeUp() {
        isSleeping = false
        scheduleSleepTask()
    }

    func updateSleepAfterMinutes(_ minutes: Int) {
        let clamped = min(60, max(1, minutes))
        sleepAfterMinutes = clamped
        UserDefaults.standard.set(clamped, forKey: sleepTimeKey)
        if !isSleeping {
            scheduleSleepTask()
        }
    }

    static func isApiAllowed() async -> Bool {
        await MainActor.run { !shared.isSleeping }
    }

    private func scheduleSleepTask() {
        sleepTask?.cancel()
        let seconds = TimeInterval(sleepAfterMinutes * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isSleeping = true
                self?.sleepTask = nil
            }
        }
    }
}
