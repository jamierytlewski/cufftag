#!/usr/bin/env swift
//
// Generates the app icon (light, dark and tinted) into the asset catalog.
//
//   brew install resvg
//   swift JacquardRemote/AppIcon/make_icon.swift
//
// The artwork is built as SVG below: conductive threads woven through denim,
// parting and lighting up under a fingertip, framed by copper stitching and rivets.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconSet = scriptDir.appendingPathComponent("../JacquardRemote/Assets.xcassets/AppIcon.appiconset")
  .standardizedFileURL

enum Variant: String, CaseIterable {
  case light = "AppIcon"
  case dark = "AppIcon-Dark"
  case tinted = "AppIcon-Tinted"
}

let touch = (x: 512.0, y: 548.0)
let threadTop = 196.0
let threadBottom = 828.0

func f(_ value: Double) -> String { String(format: "%.1f", value) }

/// A wavy vertical thread that bows away from the touch point.
func threadPath(x0: Double, phase: Double) -> String {
  let steps = 32
  let points: [(x: Double, y: Double)] = (0...steps).map { i in
    let y = threadTop + (threadBottom - threadTop) * Double(i) / Double(steps)
    let dx = x0 - touch.x
    let dy = y - touch.y
    let wave = 11 * sin(2 * .pi * (y - threadTop) / 316 + phase)
    let push = 58 * exp(-(dx * dx + dy * dy) / (2 * 165 * 165))
    return (x0 + wave + (dx < 0 ? -push : push), y)
  }
  // Catmull-Rom spline through the samples, as cubic Béziers.
  var d = "M\(f(points[0].x)),\(f(points[0].y))"
  for i in 0..<(points.count - 1) {
    let p0 = points[max(i - 1, 0)]
    let p1 = points[i]
    let p2 = points[i + 1]
    let p3 = points[min(i + 2, points.count - 1)]
    d += " C\(f(p1.x + (p2.x - p0.x) / 6)),\(f(p1.y + (p2.y - p0.y) / 6))"
    d += " \(f(p2.x - (p3.x - p1.x) / 6)),\(f(p2.y - (p3.y - p1.y) / 6))"
    d += " \(f(p2.x)),\(f(p2.y))"
  }
  return d
}

let threads = (0..<6).map { k in
  "<path d=\"\(threadPath(x0: 512 + (Double(k) - 2.5) * 104, phase: Double(k) * 1.3))\"/>"
}.joined(separator: "\n")

let rivets = [(176.0, 176.0), (848.0, 176.0), (176.0, 848.0), (848.0, 848.0)].map { x, y in
  """
  <g transform="translate(\(f(x)) \(f(y)))">
    <circle r="37" cy="6" fill="#000" fill-opacity="0.45" filter="url(#soft)"/>
    <circle r="35" fill="url(#rivet)"/>
    <circle r="21" fill="none" stroke="#5E2E10" stroke-opacity="0.55" stroke-width="4"/>
    <circle r="34" fill="none" stroke="#FFE2C4" stroke-opacity="0.3" stroke-width="2"/>
  </g>
  """
}.joined(separator: "\n")

func svg(_ variant: Variant) -> String {
  let denim =
    variant == .light
    ? ["#2A3E78", "#16244E", "#0A1027"]
    : ["#151F3D", "#0B1229", "#03060E"]
  return """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <defs>
        <radialGradient id="denim" cx="300" cy="220" r="1000" gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="\(denim[0])"/>
          <stop offset="0.55" stop-color="\(denim[1])"/>
          <stop offset="1" stop-color="\(denim[2])"/>
        </radialGradient>
        <pattern id="twill" width="16" height="16" patternUnits="userSpaceOnUse"
          patternTransform="rotate(-45 512 512)">
          <rect width="16" height="6" fill="#FFF" fill-opacity="0.045"/>
          <rect y="8" width="16" height="3" fill="#000" fill-opacity="0.18"/>
        </pattern>
        <radialGradient id="vignette" cx="512" cy="512" r="724" gradientUnits="userSpaceOnUse">
          <stop offset="0.55" stop-color="#000" stop-opacity="0"/>
          <stop offset="1" stop-color="#000" stop-opacity="0.45"/>
        </radialGradient>
        <linearGradient id="stitch" x1="0" y1="0" x2="1024" y2="1024" gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#F0AE73"/>
          <stop offset="1" stop-color="#C8743A"/>
        </linearGradient>
        <radialGradient id="rivet" cx="0.36" cy="0.3" r="0.8">
          <stop offset="0" stop-color="#FFD9B0"/>
          <stop offset="0.35" stop-color="#E69C5E"/>
          <stop offset="0.75" stop-color="#B0612C"/>
          <stop offset="1" stop-color="#6E3814"/>
        </radialGradient>
        <linearGradient id="thread" x1="0" y1="\(f(threadTop))" x2="0" y2="\(f(threadBottom))"
          gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#7590DB"/>
          <stop offset="1" stop-color="#4760A6"/>
        </linearGradient>
        <linearGradient id="endsGradient" x1="0" y1="\(f(threadTop))" x2="0" y2="\(f(threadBottom))"
          gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#000"/>
          <stop offset="0.14" stop-color="#FFF"/>
          <stop offset="0.86" stop-color="#FFF"/>
          <stop offset="1" stop-color="#000"/>
        </linearGradient>
        <mask id="ends" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
          <rect width="1024" height="1024" fill="url(#endsGradient)"/>
        </mask>
        <radialGradient id="litGradient" cx="\(f(touch.x))" cy="\(f(touch.y))" r="330"
          gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#FFF"/>
          <stop offset="0.35" stop-color="#DDD"/>
          <stop offset="1" stop-color="#000"/>
        </radialGradient>
        <mask id="lit" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
          <rect width="1024" height="1024" fill="url(#litGradient)"/>
        </mask>
        <radialGradient id="glow" cx="\(f(touch.x))" cy="\(f(touch.y))" r="175"
          gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#FFF" stop-opacity="0.95"/>
          <stop offset="0.18" stop-color="#E6FAFF" stop-opacity="0.85"/>
          <stop offset="0.45" stop-color="#7FE3FF" stop-opacity="0.4"/>
          <stop offset="1" stop-color="#7FE3FF" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="ripple" x1="0" y1="\(f(touch.y - 230))" x2="0" y2="\(f(touch.y + 230))"
          gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#7FE3FF"/>
          <stop offset="1" stop-color="#B380FF"/>
        </linearGradient>
        <filter id="soft" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="4"/>
        </filter>
        <filter id="bloom" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
          <feGaussianBlur stdDeviation="18"/>
        </filter>
      </defs>

      <rect width="1024" height="1024" fill="url(#denim)"/>
      <rect width="1024" height="1024" fill="url(#twill)"/>
      <rect width="1024" height="1024" fill="url(#vignette)"/>

      <g fill="none" stroke-width="11" stroke-dasharray="27 19" stroke-linecap="round">
        <rect x="74" y="79" width="876" height="876" rx="196" stroke="#000" stroke-opacity="0.45"
          filter="url(#soft)"/>
        <rect x="74" y="74" width="876" height="876" rx="196" stroke="url(#stitch)"/>
      </g>

      <g mask="url(#ends)" fill="none" stroke-linecap="round">
        <g stroke="#000" stroke-opacity="0.5" stroke-width="22" filter="url(#soft)"
          transform="translate(0 7)">\(threads)</g>
        <g stroke="url(#thread)" stroke-width="20">\(threads)</g>
        <g stroke="#FFF" stroke-opacity="0.18" stroke-width="5" transform="translate(-4 0)">\(threads)</g>
        <g mask="url(#lit)">
          <g stroke="#7FE3FF" stroke-width="34" filter="url(#bloom)" opacity="0.9">\(threads)</g>
          <g stroke="#7FE3FF" stroke-width="20">\(threads)</g>
          <g stroke="#FFF" stroke-opacity="0.6" stroke-width="6" transform="translate(-4 0)">\(threads)</g>
        </g>
      </g>

      <circle cx="\(f(touch.x))" cy="\(f(touch.y))" r="175" fill="url(#glow)"/>
      <g fill="none" stroke="url(#ripple)">
        <circle cx="\(f(touch.x))" cy="\(f(touch.y))" r="122" stroke-width="5" stroke-opacity="0.42"/>
        <circle cx="\(f(touch.x))" cy="\(f(touch.y))" r="190" stroke-width="3" stroke-opacity="0.16"/>
      </g>

      \(rivets)
    </svg>
    """
}

func run(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw NSError(domain: "make_icon", code: Int(process.terminationStatus), userInfo: [
      NSLocalizedDescriptionKey: "\(arguments.joined(separator: " ")) failed. Is resvg installed?",
    ])
  }
}

/// Re-encodes without an alpha channel (App Store requirement); tinted icons are grayscale.
func flatten(_ source: URL, to destination: URL, grayscale: Bool) throws {
  guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(input, 0, nil)
  else { throw CocoaError(.fileReadCorruptFile) }
  let space = grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
  let alpha = grayscale ? CGImageAlphaInfo.none : .noneSkipLast
  guard
    let context = CGContext(
      data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: alpha.rawValue)
  else { throw CocoaError(.fileWriteUnknown) }
  context.setFillColor(gray: 0, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  guard let flat = context.makeImage(),
    let output = CGImageDestinationCreateWithURL(
      destination as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw CocoaError(.fileWriteUnknown) }
  CGImageDestinationAddImage(output, flat, nil)
  guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
}

let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("jacquard-icon")
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
for variant in Variant.allCases {
  let svgURL = workDir.appendingPathComponent("\(variant.rawValue).svg")
  let rawURL = workDir.appendingPathComponent("\(variant.rawValue).png")
  try svg(variant).write(to: svgURL, atomically: true, encoding: .utf8)
  try run(["resvg", "-w", "1024", "-h", "1024", svgURL.path, rawURL.path])
  let finalURL = iconSet.appendingPathComponent("\(variant.rawValue).png")
  try flatten(rawURL, to: finalURL, grayscale: variant == .tinted)
  print("Wrote \(finalURL.path)")
}
