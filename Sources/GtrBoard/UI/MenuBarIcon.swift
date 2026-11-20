//  MenuBarIcon.swift
//  GtrBoard
//
//  The menu-bar mark: an amber pick with a dark "G", drawn as a vector image
//  on a transparent background.

import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: rect.size).fill()
            draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }()

    private static func draw(in rect: CGRect) {
        let width = rect.width
        let centerX = rect.midX

        let pick = NSBezierPath()
        pick.move(to: NSPoint(x: centerX, y: 1.2))
        pick.curve(
            to: NSPoint(x: 2.1, y: 11.3),
            controlPoint1: NSPoint(x: centerX - 3.2, y: 4.2),
            controlPoint2: NSPoint(x: 2.1, y: 7.8)
        )
        pick.curve(
            to: NSPoint(x: centerX, y: 16.6),
            controlPoint1: NSPoint(x: 2.1, y: 15.8),
            controlPoint2: NSPoint(x: centerX - 4.3, y: 17.0)
        )
        pick.curve(
            to: NSPoint(x: width - 2.1, y: 11.3),
            controlPoint1: NSPoint(x: centerX + 4.3, y: 17.0),
            controlPoint2: NSPoint(x: width - 2.1, y: 15.8)
        )
        pick.curve(
            to: NSPoint(x: centerX, y: 1.2),
            controlPoint1: NSPoint(x: width - 2.1, y: 7.8),
            controlPoint2: NSPoint(x: centerX + 3.2, y: 4.2)
        )
        pick.close()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 1.00, green: 0.77, blue: 0.50, alpha: 1),
            NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.10, alpha: 1)
        ])
        gradient?.draw(in: pick, angle: -90)

        let font = NSFont.systemFont(ofSize: 9.6, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.04, alpha: 1)
        ]
        let text = "G" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2 - 0.5
            ),
            withAttributes: attributes
        )
    }
}
