//
//  TranslateHotkeyMonitor.swift
//  IOW
//
//  設定された翻訳ショートカット（既定 ⌘G）を監視する。
//  発火時は合成 Cmd+C で選択テキストを取り、コールバックへ渡す。
//  可能ならユーザーのトリガーキーは吞む（defaultTap）。listenOnly 時は通す。
//

import AppKit
import Carbon.HIToolbox

/// 翻訳ホットキーを監視してコールバックする。
///
/// - Important: キー監視には Input Monitoring（`CGPreflightListenEventAccess`）が必須。
///   `tapCreate` が非 nil でも ListenEvent 未許可ならイベントは届かない（幽霊タップ）。
/// - Note: CGEvent コールバックは C コンテキストから呼ばれるため、本クラスは MainActor に載せない。
nonisolated final class TranslateHotkeyMonitor: @unchecked Sendable {

    /// 翻訳対象テキストが確定したときに呼ぶ（メインスレッド）。
    private let onTranslate: @MainActor @Sendable (String) -> Void

    /// ショートカット割り当てを読む先。設定変更を再起動なしで反映するため、
    /// 判定のたびに `load()` する。
    private let configStore: AppConfigStore

    /// インストール中のイベントタップ。
    private var eventTap: CFMachPort?

    /// メイン RunLoop に登録したタップ用ソース。
    private var runLoopSource: CFRunLoopSource?

    /// 吞んだ keyDown に続く keyUp も吞むための、直前にマッチした割り当て。
    private var swallowKeyUpFor: HotkeyBinding?

    /// `true` のときイベントを改変（吞む）できる。listenOnly フォールバックでは `false`。
    private var canSwallowEvents = false

    /// 合成 Cmd+C 中は再入・誤検知を避けるためホットキー判定を止める。
    /// コールバックスレッドと MainActor の Task の両方から触るためロックする。
    private let captureLock = NSLock()
    private var _isCapturingSelection = false

    private var isCapturingSelection: Bool {
        get {
            captureLock.lock()
            defer { captureLock.unlock() }
            return _isCapturingSelection
        }
        set {
            captureLock.lock()
            _isCapturingSelection = newValue
            captureLock.unlock()
        }
    }

    /// 診断用: コールバックにイベントが一度でも届いたか。
    private var didReceiveAnyEvent = false

    /// - Parameters:
    ///   - onTranslate: 選択テキストを得たときに呼ぶ。
    ///   - configStore: ショートカット割り当てを読む先。既定は UserDefaults。
    init(
        onTranslate: @escaping @MainActor @Sendable (String) -> Void,
        configStore: AppConfigStore = AppConfigStore()
    ) {
        self.onTranslate = onTranslate
        self.configStore = configStore
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    /// イベントタップをインストールして監視を開始する。
    ///
    /// - Returns: Input Monitoring 許可済みかつタップ作成に成功したとき `true`。
    @discardableResult
    func start() -> Bool {
        stop()

        let listenOK = EventTapPermission.canListenEvents
        if !listenOK {
            _ = EventTapPermission.requestListenEventAccess()
        }

        guard EventTapPermission.canListenEvents else {
            return false
        }

        if installTap(options: .defaultTap) {
            canSwallowEvents = true
            return true
        }

        if installTap(options: .listenOnly) {
            canSwallowEvents = false
            return true
        }

        return false
    }

    /// 指定オプションでタップを作成し、メイン RunLoop に載せる。
    private func installTap(options: CGEventTapOptions) -> Bool {
        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: eventsOfInterest,
            callback: Self.eventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    /// イベントタップを外す。
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        swallowKeyUpFor = nil
        canSwallowEvents = false
        isCapturingSelection = false
        didReceiveAnyEvent = false
    }

    /// 監視が動作中かどうか。
    var isRunning: Bool {
        eventTap != nil
    }

    // MARK: - CGEvent callback

    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<TranslateHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if !didReceiveAnyEvent {
            didReceiveAnyEvent = true
        }

        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyUp {
            if canSwallowEvents, let pending = swallowKeyUpFor,
               pending.matches(keyCode: keyCode, flags: flags) {
                swallowKeyUpFor = nil
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if isCapturingSelection {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }

        let config = configStore.load()

        if config.translateShortcut.matches(keyCode: keyCode, flags: flags) {
            if canSwallowEvents {
                swallowKeyUpFor = config.translateShortcut
            }
            beginSelectionCapture()
            return canSwallowEvents ? nil : Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    /// 合成 Cmd+C で選択を取り、`onTranslate` へ渡す。
    private func beginSelectionCapture() {
        isCapturingSelection = true
        Task { @MainActor [weak self] in
            let text = await SelectionTextCapture.copySelectedText()
            self?.isCapturingSelection = false
            guard let text else {
                return
            }
            self?.onTranslate(text)
        }
    }
}
