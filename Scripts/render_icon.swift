import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(srgbRed: 0.075, green: 0.24, blue: 0.22, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(srgbRed: 0.18, green: 0.35, blue: 0.29, alpha: 1).setStroke()
let orbit = NSBezierPath(ovalIn: NSRect(x: 345, y: 218, width: 610, height: 610))
orbit.lineWidth = 2
orbit.stroke()
NSColor(srgbRed: 0.93, green: 0.96, blue: 0.86, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 218, y: 210, width: 122, height: 250), xRadius: 40, yRadius: 40).fill()
NSBezierPath(roundedRect: NSRect(x: 400, y: 210, width: 122, height: 430), xRadius: 40, yRadius: 40).fill()
NSColor(srgbRed: 0.84, green: 0.93, blue: 0.57, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 582, y: 210, width: 122, height: 475), xRadius: 40, yRadius: 40).fill()
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 626, y: 683))
leaf.curve(to: NSPoint(x: 802, y: 843), controlPoint1: NSPoint(x: 603, y: 797), controlPoint2: NSPoint(x: 710, y: 873))
leaf.curve(to: NSPoint(x: 626, y: 683), controlPoint1: NSPoint(x: 814, y: 727), controlPoint2: NSPoint(x: 729, y: 660))
leaf.fill()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
