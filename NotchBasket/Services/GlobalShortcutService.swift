import Carbon.HIToolbox
import Foundation

enum GlobalShortcutKind {
    case toggleGame
    case escapeGame

    fileprivate var keyCode: UInt32 {
        switch self {
        case .toggleGame: UInt32(kVK_ANSI_B)
        case .escapeGame: UInt32(kVK_Escape)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .toggleGame: UInt32(controlKey | optionKey)
        case .escapeGame: 0
        }
    }

    fileprivate var identifier: UInt32 {
        switch self {
        case .toggleGame: 1
        case .escapeGame: 2
        }
    }
}

private let notchBasketHotKeySignature: OSType = 0x4E_42_41_53 // "NBAS"

private func notchBasketHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
    return service.handle(event: event)
}

final class GlobalShortcutService {
    private let shortcut: GlobalShortcutKind
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    init(shortcut: GlobalShortcutKind = .toggleGame) {
        self.shortcut = shortcut
    }

    @discardableResult
    func register(handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            notchBasketHotKeyHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            self.handler = nil
            return false
        }

        let hotKeyID = EventHotKeyID(
            signature: notchBasketHotKeySignature,
            id: shortcut.identifier
        )
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        handler = nil
    }

    fileprivate func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard
            status == noErr,
            hotKeyID.signature == notchBasketHotKeySignature,
            hotKeyID.id == shortcut.identifier
        else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [weak self] in
            self?.handler?()
        }
        return noErr
    }

    deinit {
        unregister()
    }
}
