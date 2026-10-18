// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
import SwiftUI
import AppKit

/// Sample data and offscreen rendering, used to produce the README screenshots:
/// `Airfryer Mac --screenshot <folder> <suffix>` writes light and dark PNGs and quits.
/// It never contacts Home Assistant and never shows the user's own header picture.
@MainActor enum Demo {
    static var isRequested: Bool { CommandLine.arguments.contains("--screenshot") }

    private static let json = """
    [
    {"entity_id":"sensor.demo_status","state":"cooking","attributes":{"friendly_name":"Cooking status"}},
    {"entity_id":"sensor.demo_remaining","state":"612","attributes":{"friendly_name":"Time remaining","unit_of_measurement":"s"}},
    {"entity_id":"number.demo_temperature","state":"180","attributes":{"friendly_name":"Set temperature","unit_of_measurement":"°C","min":40,"max":200,"step":5}},
    {"entity_id":"number.demo_time","state":"15","attributes":{"friendly_name":"Set cooking time","unit_of_measurement":"min","min":1,"max":60,"step":1}},
    {"entity_id":"button.demo_start","state":"unknown","attributes":{"friendly_name":"Start"}},
    {"entity_id":"button.demo_pause","state":"unknown","attributes":{"friendly_name":"Pause"}},
    {"entity_id":"button.demo_stop","state":"unknown","attributes":{"friendly_name":"Stop"}},
    {"entity_id":"switch.demo_power","state":"on","attributes":{"friendly_name":"Power"}}
    ]
    """

    static func run() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshot"), args.count > i + 1 else { NSApp?.terminate(nil); return }
        let folder = args[i + 1]
        let suffix = args.count > i + 2 ? args[i + 2] : "en"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let model = Controller.shared
            model.headerImage = nil
            model.entities = (try? JSONDecoder().decode([Entity].self, from: Data(json.utf8))) ?? []
            model.mapping = ["status": "sensor.demo_status", "remaining": "sensor.demo_remaining", "temp": "number.demo_temperature",
                             "time": "number.demo_time", "start": "button.demo_start", "pause": "button.demo_pause",
                             "stop": "button.demo_stop", "power": "switch.demo_power"]
            model.connected = true
            model.temperature = 180
            model.minutes = 15
            model.message = L("Connected. Air fryer entities were matched automatically.")
            for dark in [false, true] {
                render(model, dark: dark, to: "\(folder)/screenshot-\(suffix)-\(dark ? "dark" : "light").png")
            }
            NSApp.terminate(nil)
        }
    }

    private static func render(_ model: Controller, dark: Bool, to path: String) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let view = NSHostingView(rootView: Panel(model: model))
        let size = view.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let scale = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        appearance.performAsCurrentDrawingAppearance {
            let bounds = NSRect(origin: .zero, size: size)
            let clip = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
            clip.addClip()
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            view.displayIgnoringOpacity(bounds, in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
