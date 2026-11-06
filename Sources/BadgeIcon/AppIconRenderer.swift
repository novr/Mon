import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RenderJob {
    var input: URL
    var output: URL
    var title: String
    var subtitle: String?
    var color: RibbonColor
}

struct RibbonColor {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static func parse(_ raw: String) -> RibbonColor? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit) else {
            return nil
        }
        guard let value = UInt32(hex, radix: 16) else {
            return nil
        }
        if hex.count == 6 {
            return RibbonColor(
                red: channel(value >> 16),
                green: channel(value >> 8),
                blue: channel(value),
                alpha: 1
            )
        }
        return RibbonColor(
            red: channel(value >> 24),
            green: channel(value >> 16),
            blue: channel(value >> 8),
            alpha: channel(value)
        )
    }

    var cgColor: CGColor {
        CGColor(colorSpace: Self.sRGB, components: [red, green, blue, alpha])!
    }

    var textCGColor: CGColor {
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        let channel: CGFloat = luminance < 0.5 ? 1 : 0
        return CGColor(colorSpace: Self.sRGB, components: [channel, channel, channel, 1])!
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func channel(_ value: UInt32) -> CGFloat {
        CGFloat(value & 0xFF) / 255
    }

    private func linear(_ channel: CGFloat) -> CGFloat {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }
}

enum RenderError: LocalizedError {
    case loadFailed(String)
    case contextFailed
    case writeFailed(String, reason: String? = nil)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let path):
            return "画像を読み込めませんでした: \(path)"
        case .contextFailed:
            return "画像の描画に失敗しました"
        case .writeFailed(let path, let reason?):
            return "画像を書き出せませんでした: \(path)（\(reason)）"
        case .writeFailed(let path, nil):
            return "画像を書き出せませんでした: \(path)"
        }
    }
}

enum AppIconRenderer {
    static func render(input: URL, output: URL, title: String, subtitle: String?, color: RibbonColor) throws {
        let image = try loadImage(at: input)
        guard image.width > 0, image.height > 0 else {
            throw RenderError.loadFailed(input.path)
        }

        guard let context = makeContext(width: image.width, height: image.height, candidates: bitmapSpecs(for: image)) else {
            throw RenderError.contextFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        drawBadge(
            in: context,
            width: image.width,
            height: image.height,
            title: title,
            subtitle: subtitle,
            color: color
        )
        guard let rendered = context.makeImage() else {
            throw RenderError.contextFailed
        }
        try writePNG(rendered, to: output)
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RenderError.loadFailed(url.path)
        }
        // Up はそのまま返し、ビット深度と色空間を維持する。それ以外は ImageIO に向きを適用させる。
        guard imageOrientation(source) != .up else {
            return image
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw RenderError.loadFailed(url.path)
        }
        return oriented
    }

    private static func imageOrientation(_ source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .up
        }
        let raw: UInt32
        if let value = properties[kCGImagePropertyOrientation] as? UInt32 {
            raw = value
        } else if let value = properties[kCGImagePropertyOrientation] as? Int {
            raw = UInt32(value)
        } else {
            return .up
        }
        return CGImagePropertyOrientation(rawValue: raw) ?? .up
    }

    private static func drawBadge(
        in ctx: CGContext,
        width: Int,
        height: Int,
        title: String,
        subtitle: String?,
        color: RibbonColor
    ) {
        let s = min(CGFloat(width), CGFloat(height))
        let distance = 0.28 * s
        let thickness = 0.16 * s
        let length = 2 * s
        let padding = 0.04 * s
        let band = CGRect(x: -length / 2, y: -distance - thickness / 2, width: length, height: thickness)

        ctx.saveGState()
        // 原点は右上。+x は画面の右下、+y は画像の外。帯の中心は y = -distance。
        ctx.translateBy(x: CGFloat(width), y: CGFloat(height))
        ctx.rotate(by: -.pi / 4)

        ctx.setFillColor(color.cgColor)
        ctx.fill(band)

        let border = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 1, 1, 0.9])!
        ctx.setStrokeColor(border)
        ctx.setLineWidth(0.006 * s)
        ctx.beginPath()
        let outerY = -distance + thickness / 2
        let innerY = -distance - thickness / 2
        ctx.move(to: CGPoint(x: -length / 2, y: outerY))
        ctx.addLine(to: CGPoint(x: length / 2, y: outerY))
        ctx.move(to: CGPoint(x: -length / 2, y: innerY))
        ctx.addLine(to: CGPoint(x: length / 2, y: innerY))
        ctx.strokePath()

        ctx.saveGState()
        ctx.clip(to: band)
        let textColor = color.textCGColor
        if let subtitle {
            let titleSize = drawLine(title, yCenter: -distance + thickness * 0.22, heightCap: thickness * 0.40, padding: padding, color: textColor, in: ctx)
            drawLine(subtitle, yCenter: -distance - thickness * 0.18, heightCap: thickness * 0.30, maxFontSize: titleSize, padding: padding, color: textColor, in: ctx)
        } else {
            drawLine(title, yCenter: -distance, heightCap: thickness * 0.55, padding: padding, color: textColor, in: ctx)
        }
        ctx.restoreGState()
        ctx.restoreGState()
    }

    @discardableResult
    private static func drawLine(
        _ text: String,
        yCenter: CGFloat,
        heightCap: CGFloat,
        maxFontSize: CGFloat = .greatestFiniteMagnitude,
        padding: CGFloat,
        color: CGColor,
        in ctx: CGContext
    ) -> CGFloat {
        var fontSize = max(min(heightCap, maxFontSize), 1)
        var line = makeLine(text, fontSize: fontSize, color: color)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var measured = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        for _ in 0..<8 {
            let lineHeight = ascent + descent
            let cornerDistance = -(yCenter + lineHeight / 2)
            let available = 2 * cornerDistance - 2 * padding
            let heightScale = lineHeight > heightCap && lineHeight > 0 ? heightCap / lineHeight : 1
            let widthScale: CGFloat
            if available <= 0 {
                widthScale = 0.5
            } else if measured > available && measured > 0 {
                widthScale = available / measured
            } else {
                widthScale = 1
            }
            let scale = min(heightScale, widthScale)
            if scale >= 0.999 {
                break
            }
            let next = max(1, fontSize * scale)
            if next == fontSize {
                break
            }
            fontSize = next
            line = makeLine(text, fontSize: fontSize, color: color)
            ascent = 0
            descent = 0
            measured = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        }

        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -measured / 2, y: yCenter - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        return fontSize
    }

    private static func makeLine(_ text: String, fontSize: CGFloat, color: CGColor) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func writePNG(_ image: CGImage, to output: URL) throws {
        let directory = output.deletingLastPathComponent()
        let name = output.deletingPathExtension().lastPathComponent
        let temporary = directory.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")

        do {
            guard let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw RenderError.writeFailed(output.path, reason: "一時ファイルを作成できません: \(temporary.path)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw RenderError.writeFailed(output.path, reason: "PNG のエンコードに失敗しました")
            }

            if FileManager.default.fileExists(atPath: output.path) {
                _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: output)
            }
        } catch let error as RenderError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw RenderError.writeFailed(output.path, reason: error.localizedDescription)
        }
    }
}

private struct BitmapSpec {
    var colorSpace: CGColorSpace
    var bitsPerComponent: Int
    var hasAlpha: Bool

    var bitmapInfo: UInt32 {
        let alpha: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        var info = alpha.rawValue
        if bitsPerComponent == 16 {
            info |= CGBitmapInfo.byteOrder16Little.rawValue
        }
        return info
    }

}

// 先頭から順に CGContext の生成を試す。元の色空間を 8bpc で保てるなら sRGB より優先する。
private func bitmapSpecs(for image: CGImage) -> [BitmapSpec] {
    let hasAlpha = imageHasAlpha(image)
    let sRGB = BitmapSpec(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, bitsPerComponent: 8, hasAlpha: hasAlpha)
    guard image.bitsPerComponent != 32, let colorSpace = image.colorSpace, colorSpace.model == .rgb else {
        return [sRGB]
    }
    var specs: [BitmapSpec] = []
    if image.bitsPerComponent == 16 {
        specs.append(BitmapSpec(colorSpace: colorSpace, bitsPerComponent: 16, hasAlpha: hasAlpha))
    }
    specs.append(BitmapSpec(colorSpace: colorSpace, bitsPerComponent: 8, hasAlpha: hasAlpha))
    specs.append(sRGB)
    return specs
}

private func imageHasAlpha(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipLast, .noneSkipFirst:
        return false
    default:
        return true
    }
}

private func makeContext(width: Int, height: Int, candidates: [BitmapSpec]) -> CGContext? {
    for spec in candidates {
        if let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: spec.bitsPerComponent,
            bytesPerRow: 0,
            space: spec.colorSpace,
            bitmapInfo: spec.bitmapInfo
        ) {
            return context
        }
    }
    return nil
}
