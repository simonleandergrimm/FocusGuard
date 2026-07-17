#!/usr/bin/env swift

import AppKit
import Foundation

private final class IconBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let inset = bounds.width * 0.035
        let tile = bounds.insetBy(dx: inset, dy: inset)
        let radius = bounds.width * 0.215
        let background = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
        NSColor(
            calibratedRed: 1.000,
            green: 1.000,
            blue: 1.000,
            alpha: 1
        ).setFill()
        background.fill()

        NSColor(calibratedWhite: 0.1, alpha: 0.07).setStroke()
        background.lineWidth = max(1, bounds.width * 0.006)
        background.stroke()
    }
}

private let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024),
]

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("usage: generate-app-icon.swift <FocusGuard.iconset directory> [FocusGuard.icns]\n", stderr)
    exit(EXIT_FAILURE)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

for iconFile in iconFiles {
    let size = CGFloat(iconFile.pixels)
    let canvas = IconBackgroundView(frame: NSRect(x: 0, y: 0, width: size, height: size))
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor = NSColor.clear.cgColor

    let symbolSide = size * 0.49
    let symbolView = NSImageView(
        frame: NSRect(
            x: (size - symbolSide) / 2,
            y: (size - symbolSide) / 2,
            width: symbolSide,
            height: symbolSide
        )
    )
    let symbol = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "FocusGuard")
    let configuration = NSImage.SymbolConfiguration(
        pointSize: size * 0.43,
        weight: .semibold
    )
    symbolView.image = symbol?.withSymbolConfiguration(configuration)
    symbolView.imageScaling = .scaleProportionallyUpOrDown
    symbolView.contentTintColor = NSColor(
        calibratedRed: 0.105,
        green: 0.455,
        blue: 0.900,
        alpha: 1
    )
    canvas.addSubview(symbolView)

    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputURL.appendingPathComponent(iconFile.name), options: .atomic)
}

if CommandLine.arguments.count == 3 {
    let chunks: [(type: String, file: String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic14", "icon_256x256@2x.png"),
    ]

    func appendBigEndian(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    var encodedChunks = Data()
    for chunk in chunks {
        let png = try Data(contentsOf: outputURL.appendingPathComponent(chunk.file))
        encodedChunks.append(Data(chunk.type.utf8))
        appendBigEndian(UInt32(png.count + 8), to: &encodedChunks)
        encodedChunks.append(png)
    }

    var icns = Data("icns".utf8)
    appendBigEndian(UInt32(encodedChunks.count + 8), to: &icns)
    icns.append(encodedChunks)
    try icns.write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]),
        options: .atomic
    )
}
