import Foundation
import Observation
import TCCore

@MainActor @Observable
final class Job: Identifiable {
    enum State { case queued, running, paused }
    let id = UUID()
    let title: String
    var state = State.queued
    var progress = TransferProgress()
    var startedAt: Date?
    let control = OperationControl()

    @ObservationIgnored let work: @Sendable (OperationControl, @escaping @Sendable (TransferProgress) -> Void) -> OperationReport
    @ObservationIgnored let onFinish: (OperationReport) -> Void

    init(title: String,
         work: @escaping @Sendable (OperationControl, @escaping @Sendable (TransferProgress) -> Void) -> OperationReport,
         onFinish: @escaping (OperationReport) -> Void) {
        self.title = title; self.work = work; self.onFinish = onFinish
    }

    var bytesPerSecond: Double {
        guard let s = startedAt else { return 0 }
        let t = Date().timeIntervalSince(s)
        return t > 0.3 ? Double(progress.bytesDone) / t : 0
    }

    var detail: String {
        switch state {
        case .queued: return "ve frontě"
        case .paused: return "pozastaveno"
        case .running:
            var parts = [progress.current]
            let v = bytesPerSecond
            if v > 0 {
                parts.append(Fmt.human(Int64(v)) + "/s")
                let left = Double(progress.bytesTotal - progress.bytesDone) / v
                if left.isFinite, left > 1 { parts.append("zbývá " + Self.format(left)) }
            }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private static func format(_ s: Double) -> String {
        let n = Int(s.rounded())
        return n >= 3600 ? "\(n / 3600) h \(n % 3600 / 60) min" : (n >= 60 ? "\(n / 60) min \(n % 60) s" : "\(n) s")
    }
}

/// Sekvenční fronta souborových operací; úlohy běží na pozadí jedna po druhé.
@MainActor @Observable
final class JobManager {
    private(set) var jobs: [Job] = []

    var isBusy: Bool { !jobs.isEmpty }

    func enqueue(title: String,
                 work: @escaping @Sendable (OperationControl, @escaping @Sendable (TransferProgress) -> Void) -> OperationReport,
                 onFinish: @escaping (OperationReport) -> Void) {
        jobs.append(Job(title: title, work: work, onFinish: onFinish))
        startNextIfIdle()
    }

    func togglePause(_ job: Job) {
        guard job.state != .queued else { return }
        if job.control.isPaused { job.control.resume(); job.state = .running } else { job.control.pause(); job.state = .paused }
    }

    func cancel(_ job: Job) {
        job.control.cancel()
        if job.state == .queued { jobs.removeAll { $0.id == job.id } }
    }

    private func startNextIfIdle() {
        guard !jobs.contains(where: { $0.state != .queued }), let job = jobs.first else { return }
        job.state = .running
        job.startedAt = Date()
        let work = job.work, control = job.control
        Task {
            let report = await Task.detached {
                work(control) { p in DispatchQueue.main.async { MainActor.assumeIsolated { job.progress = p } } }
            }.value
            self.jobs.removeAll { $0.id == job.id }
            job.onFinish(report)
            self.startNextIfIdle()
        }
    }
}
