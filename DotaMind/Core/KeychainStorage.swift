// KeychainStorage.swift
import Foundation
import Security

// Простая обёртка над Keychain для хранения строк по ключу.
// Keychain API потокобезопасен и не требует главного потока, поэтому
// этот тип не изолируем @MainActor — его можно вызывать из фоновых задач.
// ANDROID: DataStore + Android Keystore (или EncryptedSharedPreferences).
final class KeychainStorage: @unchecked Sendable {
    static let shared = KeychainStorage()
    private init() {}

    enum Key: String {
        case steamID64 = "steam_id_64"
    }

    // Сохранение строки в Keychain (перезапись, если уже существовала).
    func setString(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "DotaMind",
            kSecAttrAccount as String: key.rawValue
        ]
        // Удаляем старую запись (если была)
        SecItemDelete(baseQuery as CFDictionary)

        // Добавляем новую с явной политикой доступности
        var add = baseQuery
        add[kSecValueData as String] = data
        // После первой разблокировки доступно, не бэкапится (ThisDeviceOnly).
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    // Чтение строки из Keychain.
    func getString(for key: Key) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "DotaMind",
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return str
    }

    // Удаление записи из Keychain (идемпотентно).
    func remove(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "DotaMind",
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
