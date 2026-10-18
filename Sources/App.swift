// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
import SwiftUI
import AppKit
import UserNotifications

/// Optional header picture chosen by the user (kept locally, never part of the repository).
enum HeaderImage {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirfryerMac/header-image.png")
    }
    static func load() -> NSImage? { NSImage(contentsOf: url) }

    /// Lets the user pick an image, downsizes it to 256 px and stores it as PNG.
    @MainActor static func choose() -> NSImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url, let image = NSImage(contentsOf: source), image.size.width > 0 else { return nil }
        let side: CGFloat = 256
        let ratio = min(side / image.size.width, side / image.size.height)
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? png.write(to: url)) != nil else { return nil }
        return load()
    }
    static func reset() { try? FileManager.default.removeItem(at: url) }
}

@MainActor final class Controller: ObservableObject {
    static let shared = Controller()

    @Published var address = UserDefaults.standard.string(forKey: "address") ?? "http://localhost:8123"
    @Published var token = ""
    @Published var entities: [Entity] = []
    @Published var mapping = UserDefaults.standard.dictionary(forKey: "mapping") as? [String: String] ?? [:]
    @Published var message = L("Configure the Home Assistant connection.")
    @Published var busy = false
    @Published var connected = false
    @Published var updated: Date?
    @Published var temperature = 180.0
    @Published var minutes = 15.0
    @Published var headerImage: NSImage? = HeaderImage.load()
    private var client: HAClient?
    private var started = false
    private var wasCooking = false

    func entity(_ role: Role) -> Entity? { entities.first { $0.id == mapping[role.rawValue] } }
    func usable(_ role: Role) -> Bool { connected && !busy && entity(role)?.available == true }
    func value(_ role: Role) -> String {
        guard connected, let e = entity(role), e.available else { return "—" }
        return e.state + (e.attributes.unit_of_measurement.map { " " + $0 } ?? "")
    }
    var cooking: Bool {
        guard let s = entity(.status)?.state.lowercased() else { return false }
        return ["cook", "heat", "prehea", "run"].contains { s.contains($0) }
    }

    var temperatureRange: ClosedRange<Double> {
        let e = entity(.temp)
        return (e?.attributes.min ?? 40)...(e?.attributes.max ?? 200)
    }
    var minutesRange: ClosedRange<Double> {
        let e = entity(.time)
        let k = (e?.attributes.unit_of_measurement ?? "min").lowercased().hasPrefix("s") ? 60.0 : 1.0
        return ((e?.attributes.min ?? 1) / k)...((e?.attributes.max ?? 60) / k)
    }
    var statusText: String {
        guard connected, let e = entity(.status), e.available else { return L("Unavailable") }
        switch e.state.lowercased() {
        case "standby", "idle", "off": return L("Standby")
        case "cooking": return L("Cooking")
        case "preheating", "preheat": return L("Preheating")
        case "paused", "pause": return L("Paused")
        case "finished", "done", "ready": return L("Cooking finished")
        default: return e.state.prefix(1).uppercased() + e.state.dropFirst()
        }
    }
    var remainingText: String {
        guard connected, let e = entity(.remaining), e.available, let v = Double(e.state) else { return "--:--" }
        let seconds = Int((e.attributes.unit_of_measurement ?? "s").lowercased().hasPrefix("m") ? v * 60 : v)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var setpointText: String? {
        guard connected, let e = entity(.temp), e.available, let v = Double(e.state), v > 0 else { return nil }
        return L("Set to %lld °C", Int64(v))
    }
    var menuTitle: String {
        guard connected, cooking, let r = entity(.remaining), r.available else { return "" }
        return " " + r.state + (r.attributes.unit_of_measurement.map { " " + $0 } ?? "")
    }
    func bind(_ role: Role) -> Binding<String> {
        Binding(get: { self.mapping[role.rawValue] ?? "" }, set: {
            self.mapping[role.rawValue] = $0
            UserDefaults.standard.set(self.mapping, forKey: "mapping")
        })
    }

    /// Connects and polls from app launch, so the end-of-cooking
    /// notification also arrives while the panel is closed.
    func start() {
        guard !started else { return }
        started = true
        Task {
            await connect()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await refresh()
            }
        }
    }

    private func fetch() async throws {
        guard let client = client else { throw failure(L("Connect Home Assistant first.")) }
        entities = try await client.states()
        connected = true
        updated = Date()
        if mapping.isEmpty || Role.allCases.contains(where: { mapping[$0.rawValue] == nil }) {
            let auto = AutoMap.map(entities)
            for (k, v) in auto where mapping[k] == nil { mapping[k] = v }
            UserDefaults.standard.set(mapping, forKey: "mapping")
        }
        let now = cooking
        if wasCooking && !now { notifyDone() }
        wasCooking = now
    }

    private func notifyDone() {
        let content = UNMutableNotificationContent()
        content.title = "Airfryer"
        content.body = L("Cooking has finished.")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func connect() async {
        guard !busy else { return }
        busy = true
        connected = false
        defer { busy = false }
        do {
            let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let credential = typed.isEmpty ? Vault.read(clean) : typed
            client = try HAClient(address: clean, token: credential)
            try await fetch()
            try Vault.save(credential, account: clean)
            UserDefaults.standard.set(clean, forKey: "address")
            address = clean
            token = ""
            let missing = Role.allCases.filter { mapping[$0.rawValue] == nil }
            message = missing.isEmpty
                ? L("Connected. Air fryer entities were matched automatically.")
                : L("Connected. %lld entities are missing: pick those of your air fryer in Settings.", Int64(missing.count))
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch { connected = false; message = error.localizedDescription }
    }

    func refresh() async {
        guard client != nil, !busy else { return }
        busy = true
        defer { busy = false }
        do { try await fetch() }
        catch { connected = false; message = error.localizedDescription }
    }

    func press(_ role: Role) async {
        guard usable(role), let client = client, let id = mapping[role.rawValue], id.hasPrefix("button.") else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.call("button", "press", ["entity_id": id])
            message = L("Command sent. Check the status reported by the air fryer.")
            try await fetch()
        } catch { connected = false; message = error.localizedDescription + " " + L("The command may already have been received: check before repeating it.") }
    }

    var isOn: Bool { entity(.power)?.state == "on" }

    func setPower(_ on: Bool) async {
        guard usable(.power), let client = client, let id = mapping[Role.power.rawValue], id.hasPrefix("switch.") else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.call("switch", on ? "turn_on" : "turn_off", ["entity_id": id])
            message = on ? L("Power on requested.") : L("Power off requested.")
            try await fetch()
        } catch { connected = false; message = error.localizedDescription + " " + L("Check the status before repeating the command.") }
    }

    func apply() async {
        guard usable(.temp), usable(.time), let client = client, let temp = entity(.temp), let time = entity(.time) else { return }
        busy = true
        defer { busy = false }
        var wroteTemperature = false
        do {
            guard temp.attributes.unit_of_measurement == "°C" else { throw failure(L("Select a temperature entity in °C.")) }
            let t = try validated(temperature, entity: temp)
            let d = try validated(try durationValue(minutes: minutes, unit: time.attributes.unit_of_measurement), entity: time)
            try await client.call("number", "set_value", ["entity_id": temp.id, "value": t])
            wroteTemperature = true
            try await client.call("number", "set_value", ["entity_id": time.id, "value": d])
            message = L("Settings sent. Press Start to begin.")
            try await fetch()
        } catch {
            message = (wroteTemperature ? L("Temperature sent; check the duration.") + " " : "") + error.localizedDescription
        }
    }
}

struct Panel: View {
    @ObservedObject var model: Controller
    @State private var showSettings = false
    @State private var confirmStart = false

    var body: some View {
        VStack(spacing: 18) {
            header
            if showSettings || !model.connected { settings } else { main }
            Text(model.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
        }
        .padding(22)
        .frame(width: 380)
        .alert("Start the air fryer?", isPresented: $confirmStart) {
            Button("Start") { Task { await model.press(.start) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Make sure the basket is inserted and nothing blocks the air intake. Stay nearby.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.headerImage ?? NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: model.headerImage == nil ? 0 : 7))
            Text(verbatim: "Airfryer").font(.title3.bold())
            Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 8, height: 8)
            Spacer()
            Button { Task { await model.setPower(!model.isOn) } } label: {
                Image(systemName: "power").foregroundStyle(model.isOn ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless).disabled(!model.usable(.power))
            .help(model.isOn ? LocalizedStringKey("Turn the air fryer off") : LocalizedStringKey("Turn the air fryer on"))
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(model.busy || !model.connected).help("Refresh")
            Button { showSettings.toggle() } label: { Image(systemName: showSettings ? "xmark" : "gearshape") }
                .buttonStyle(.borderless).help("Settings")
        }
    }

    private var main: some View {
        VStack(spacing: 18) {
            statusCard
            HStack(spacing: 12) {
                stepper(title: "Temperature", value: $model.temperature, unit: "°C", range: model.temperatureRange, step: 5)
                stepper(title: "Duration", value: $model.minutes, unit: "min", range: model.minutesRange, step: 1)
            }
            HStack(spacing: 8) {
                ForEach(Preset.all) { p in
                    Button(LocalizedStringKey(p.name)) { model.temperature = p.temperature; model.minutes = p.minutes }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Button { Task { await model.apply() } } label: {
                Text("Set \(Int(model.temperature)) °C · \(Int(model.minutes)) min").frame(maxWidth: .infinity)
            }
            .controlSize(.large).buttonStyle(.bordered)
            .disabled(!model.usable(.temp) || !model.usable(.time))
            HStack(spacing: 10) {
                Button { confirmStart = true } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(.orange).disabled(!model.usable(.start))
                Button { Task { await model.press(.pause) } } label: {
                    Image(systemName: "pause.fill").frame(width: 28)
                }
                .controlSize(.large).disabled(!model.usable(.pause)).help("Pause")
                Button { Task { await model.press(.stop) } } label: {
                    Image(systemName: "stop.fill").frame(width: 28)
                }
                .controlSize(.large).tint(.red).disabled(!model.usable(.stop)).help("Stop")
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 4) {
            Text(model.statusText).font(.headline).foregroundStyle(model.cooking ? Color.orange : Color.secondary)
            Text(model.remainingText).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
            if let t = model.setpointText { Text(t).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
    }

    private func stepper(title: LocalizedStringKey, value: Binding<Double>, unit: LocalizedStringKey, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered).controlSize(.large)
                VStack(spacing: 0) {
                    Text("\(Int(value.wrappedValue))").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 56)
                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.connected {
                Text("Connect Home Assistant: create a long-lived access token (profile → Security) and paste it here.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextField("Home Assistant address", text: $model.address).textFieldStyle(.roundedBorder)
            SecureField("Token (empty = use the saved one)", text: $model.token).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save and connect") { Task { await model.connect() } }.buttonStyle(.borderedProminent).disabled(model.busy)
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            HStack {
                Button("Choose header image…") { if let image = HeaderImage.choose() { model.headerImage = image } }
                if model.headerImage != nil {
                    Button("Use default image") { HeaderImage.reset(); model.headerImage = nil }
                }
            }.controlSize(.small)
            Text("The token is stored in the Keychain. Over HTTP it travels unencrypted: use it only on your trusted network.").font(.caption2).foregroundStyle(.secondary)
            if !model.entities.isEmpty {
                DisclosureGroup("Associated entities") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("They must be only those of your air fryer.").font(.caption)
                        ForEach(Role.allCases) { role in
                            Picker(LocalizedStringKey(role.title), selection: model.bind(role)) {
                                Text("Select…").tag("")
                                ForEach(model.entities.filter { $0.id.hasPrefix(role.domain) }) { e in Text(e.label).tag(e.id) }
                            }
                        }
                    }.padding(.top, 6)
                }
            }
        }.disabled(model.busy)
    }
}

/// Monochrome air fryer glyph for the menu bar (template image: macOS tints it for light/dark mode).
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: nil)!
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

@main struct AirfryerMacApp: App {
    @StateObject private var model = Controller.shared
    init() { if Demo.isRequested { Demo.run() } else { Controller.shared.start() } }
    var body: some Scene {
        // Regular window: useful when the menu bar is full and the notch hides the icon.
        Window("Airfryer Mac", id: "main") {
            Panel(model: model)
        }.windowResizability(.contentSize)
        MenuBarExtra {
            Panel(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
            Text(model.menuTitle)
        }.menuBarExtraStyle(.window)
    }
}
