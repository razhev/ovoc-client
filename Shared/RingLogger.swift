import Foundation
import os

/// Файловый лог в App Group + дублирование в os.Logger.
///
/// Файловый канал — основной способ отладки: отладчик Xcode ломает
/// Go-код Cloak (golang/go#57651 — под отладчиком всё работает ~5 fps
/// и выглядит зависшим), поэтому подключать отладчик к расширению нельзя,
/// а печатать в консоль расширение не может. Файлы с телефона забирает
/// `make logs`.
final class RingLogger {
    /// Один логгер на процесс, у каждого процесса свой файл: расширение пишет
    /// tunnel.log, приложение — app.log (двум процессам нельзя дописывать
    /// и ротировать один и тот же файл).
    static let shared: RingLogger = {
        let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
        return RingLogger(
            fileURL: isExtension ? SharedPaths.logFileURL : SharedPaths.appLogFileURL,
            maxBytes: 256 * 1024,
            category: isExtension ? "tunnel" : "app"
        )
    }()

    private let fileURL: URL?
    private let maxBytes: Int
    private let osLog: Logger
    private let queue = DispatchQueue(label: "com.razhev.ovocclient.ringlogger")
    private var heartbeatTimer: DispatchSourceTimer?

    /// Добавка к строке heartbeat (расширение подставляет счётчики пакетов):
    /// по ней видно, что туннель жив и сколько через него прошло.
    var heartbeatExtra: (() -> String)?

    init(fileURL: URL?, maxBytes: Int, category: String) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.osLog = Logger(subsystem: "com.razhev.ovocclient", category: category)
    }

    func log(_ message: String) {
        // .notice, а не .info: info-сообщения не сохраняются в хранилище логов
        // и скрыты в Console.app по умолчанию.
        osLog.notice("\(message, privacy: .public)")
        let line = "\(Self.timestamp()) \(message)\n"
        queue.async { self.append(line) }
    }

    /// Разовая строка с потреблением памяти; label — что только что произошло.
    func logMemory(_ label: String) {
        log("memory \(label): \(Self.memoryFootprintMB()) MB")
    }

    /// Раз в 30 сек пишет потребление памяти: у расширения жёсткий лимит
    /// ~50 МБ (процесс просто убивается системой), по этим строкам видно
    /// приближение к нему.
    func startMemoryHeartbeat() {
        guard heartbeatTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let extra = self.heartbeatExtra.map { ", " + $0() } ?? ""
            self.log("heartbeat: memory=\(Self.memoryFootprintMB()) MB\(extra)")
        }
        timer.resume()
        heartbeatTimer = timer
    }

    // MARK: - Файл

    private func append(_ line: String) {
        guard let url = fileURL, let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        rotateIfNeeded(url: url)
    }

    /// Ротация усечением: когда файл превышает лимит, оставляем вторую половину.
    /// Примитивно, зато без второго файла и лишней памяти.
    private func rotateIfNeeded(url: URL) {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        let tail = data.suffix(maxBytes / 2)
        try? tail.write(to: url, options: .atomic)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    /// phys_footprint — та же метрика, по которой iOS решает убить расширение.
    private static func memoryFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / (1024 * 1024))
    }
}
