// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
import Foundation
import Security

/// Localized text: the key is the English string; translations live in Resources/<language>.lproj.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

struct Entity: Decodable, Identifiable, Equatable {
    let entity_id: String
    let state: String
    let attributes: Attributes
    var id: String { entity_id }
    struct Attributes: Decodable, Equatable {
        let friendly_name: String?
        let unit_of_measurement: String?
        let min: Double?
        let max: Double?
        let step: Double?
    }
    /// Buttons report "unknown" until pressed, which is normal: only "unavailable" means the device is unreachable.
    var available: Bool {
        state != "unavailable" && (state != "unknown" || entity_id.hasPrefix("button."))
    }
    var label: String { friendlyName + " [" + entity_id + "]" }
    var friendlyName: String { attributes.friendly_name ?? entity_id }
}

enum Role: String, CaseIterable, Identifiable {
    case status, remaining, temp, time, start, pause, stop, power
    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: return "Cooking status"
        case .remaining: return "Time remaining"
        case .temp: return "Set temperature"
        case .time: return "Set duration"
        case .start: return "Start / resume"
        case .pause: return "Pause"
        case .stop: return "Stop"
        case .power: return "Power (on/off)"
        }
    }
    var domain: String {
        switch self {
        case .status, .remaining: return "sensor."
        case .temp, .time: return "number."
        case .start, .pause, .stop: return "button."
        case .power: return "switch."
        }
    }
    /// Words that must appear in the entity id or name.
    var keywords: [String] {
        switch self {
        case .status: return ["status", "stato"]
        case .remaining: return ["remaining", "rimanente", "time_left"]
        case .temp: return ["temperature", "temperatura"]
        case .time: return ["time", "duration", "durata", "tempo"]
        case .start: return ["start", "avvia", "resume"]
        case .pause: return ["pause", "pausa"]
        case .stop: return ["stop", "arresta"]
        case .power: return ["alimentazione", "power"]
        }
    }
    var excluded: [String] {
        switch self {
        case .temp, .time: return ["warm", "keep", "mantieni", "current", "attuale"]
        case .status: return ["recipe", "ricetta", "error", "errore", "preheat", "firmware", "aggiornamento", "update"]
        case .power: return ["preriscaldamento", "preheat"]
        default: return []
        }
    }
}

enum AutoMap {
    static let deviceHints = ["airfryer", "air_fryer", "hd925", "hd9255", "hd928", "philips"]

    /// Auto-maps only the roles that have a single unambiguous candidate
    /// among the entities that appear to belong to the air fryer.
    static func map(_ entities: [Entity]) -> [String: String] {
        let mine = entities.filter { e in
            let text = (e.entity_id + " " + e.friendlyName).lowercased()
            return deviceHints.contains { text.contains($0) }
        }
        var result: [String: String] = [:]
        for role in Role.allCases {
            let matches = mine.filter { e in
                guard e.entity_id.hasPrefix(role.domain) else { return false }
                let text = (e.entity_id + " " + e.friendlyName).lowercased()
                return role.keywords.contains { text.contains($0) }
                    && !role.excluded.contains { text.contains($0) }
            }
            if matches.count == 1 { result[role.rawValue] = matches[0].entity_id }
        }
        return result
    }
}

func failure(_ text: String) -> NSError {
    NSError(domain: "AirfryerMac", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}

func validated(_ value: Double, entity: Entity) throws -> Double {
    guard let min = entity.attributes.min, let max = entity.attributes.max,
          value.isFinite, value >= min, value <= max else {
        throw failure(L("Value outside the limits reported by %@.", entity.id))
    }
    if let step = entity.attributes.step, step > 0 {
        let steps = (value - min) / step
        guard abs(steps - steps.rounded()) < 0.00001 else { throw failure(L("Invalid value: required step is %@.", "\(step)")) }
    }
    return value
}

/// Converts the minutes chosen by the user into the unit of the duration entity.
func durationValue(minutes: Double, unit: String?) throws -> Double {
    switch (unit ?? "").lowercased() {
    case "s", "sec", "seconds": return minutes * 60
    case "min", "minutes": return minutes
    default: throw failure(L("Unsupported duration unit: %@. Select the correct entity.", unit ?? L("none")))
    }
}

enum Vault {
    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "AirfryerMac.HomeAssistant",
         kSecAttrAccount as String: account]
    }
    static func read(_ account: String) -> String {
        var q = query(account)
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String, account: String) throws {
        let q = query(account)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(L("Keychain: error %lld.", Int64(status))) }
    }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Minimal client for the Home Assistant REST API.
final class HAClient {
    let base: URL
    private let token: String
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    init(address: String, token: String) throws {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: clean), ["http", "https"].contains(url.scheme ?? ""),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw failure(L("Enter a valid http:// or https:// URL, without credentials or parameters."))
        }
        guard !token.isEmpty else { throw failure(L("Enter a long-lived access token.")) }
        self.base = url
        self.token = token
    }

    private func send(_ path: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent("api/" + path), timeoutInterval: 15)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body = body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw failure(code == 401 ? L("Invalid or expired token.") : L("Home Assistant: HTTP %lld. Check the address and permissions.", Int64(code)))
        }
        return data
    }

    func states() async throws -> [Entity] {
        try JSONDecoder().decode([Entity].self, from: try await send("states", body: nil)).sorted { $0.id < $1.id }
    }
    func call(_ domain: String, _ service: String, _ body: [String: Any]) async throws {
        _ = try await send("services/\(domain)/\(service)", body: body)
    }
}

/// Quick programs: they only fill in temperature and duration, they never start anything.
struct Preset: Identifiable {
    let name: String, temperature: Double, minutes: Double
    var id: String { name }
    static let all = [
        Preset(name: "Fries", temperature: 200, minutes: 18),
        Preset(name: "Chicken", temperature: 180, minutes: 25),
        Preset(name: "Vegetables", temperature: 180, minutes: 12),
        Preset(name: "Reheat", temperature: 160, minutes: 6),
    ]
}
