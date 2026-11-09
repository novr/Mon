import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BadgeIcon

final class AppIconRendererTests {
    private let directory: URL
    private let firstRowIsTop: Bool

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        firstRowIsTop = try Self.detectFirstRowIsTop()
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func displayP3OpaqueImageKeepsProfileAndSize() throws {
        let input = directory.appendingPathComponent("p3.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 48,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.displayP3)),
            hasAlpha: false
        )
        let output = directory.appendingPathComponent("p3-out.png")
        try render(input: input, output: output, title: "DEV", subtitle: "v1.2.0 (42)")

        let image = try load(output)
        #expect(image.width == 64)
        #expect(image.height == 48)
        #expect(!hasAlpha(image))
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        #expect(try profileName(output) == "Display P3")
    }

    @Test func alphaIsPreserved() throws {
        let input = directory.appendingPathComponent("alpha.png")
        try writeImage(
            to: input,
            type: .png,
            width: 32,
            height: 32,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: true
        )
        let output = directory.appendingPathComponent("alpha-out.png")
        try render(input: input, output: output, title: "QA", subtitle: nil)

        let image = try load(output)
        #expect(hasAlpha(image))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        let center = try rgba(image, x: 16, yFromTop: 16)
        #expect((100...200).contains(Int(center.a)))
    }

    @Test func longTitleKeepsDimensions() throws {
        let input = directory.appendingPathComponent("long.png")
        try writeImage(
            to: input,
            type: .png,
            width: 128,
            height: 128,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let output = directory.appendingPathComponent("long-out.png")
        try render(
            input: input,
            output: output,
            title: "feature/very-long-branch-name-xxxx",
            subtitle: "v1.2.0 (42) build-99999"
        )

        let image = try load(output)
        #expect(image.width == 128)
        #expect(image.height == 128)
        #expect(!hasAlpha(image))
    }

    @Test func badgeChangesPixelsAndCanOverwriteInput() throws {
        let input = directory.appendingPathComponent("overwrite.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 64,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let beforeImage = try load(input)
        let beforeCenter = try rgba(beforeImage, x: 32, yFromTop: 32)
        let beforeBottom = try rgba(beforeImage, x: 32, yFromTop: 60)
        try render(input: input, output: input, title: "DEV", subtitle: "v1.2.0 (42)")
        let afterImage = try load(input)
        let afterCenter = try rgba(afterImage, x: 32, yFromTop: 32)
        let afterBottom = try rgba(afterImage, x: 32, yFromTop: 60)

        #expect(beforeCenter == afterCenter)
        #expect(beforeBottom != afterBottom)
    }

    @Test func sixteenBitDepthIsPreserved() throws {
        let input = directory.appendingPathComponent("deep.png")
        try writeImage(
            to: input,
            type: .png,
            width: 16,
            height: 16,
            bitsPerComponent: 16,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let output = directory.appendingPathComponent("deep-out.png")
        try render(input: input, output: output, title: "DEV", subtitle: nil)

        let image = try load(output)
        #expect(image.bitsPerComponent == 16)
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(!hasAlpha(image))
    }

    @Test func missingInputIsRejected() {
        expectRejected(
            ["-i", directory.appendingPathComponent("missing.png").path, "-t", "DEV"],
            containing: "入力ファイルがありません"
        )
    }

    @Test func jpegWithoutOutputIsRejected() throws {
        let input = directory.appendingPathComponent("photo.jpg")
        try writeImage(
            to: input,
            type: .jpeg,
            width: 16,
            height: 16,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        expectRejected(["-i", input.path, "-t", "DEV"], containing: "入力が PNG ではないため")
    }

    @Test func nonPNGOutputIsRejected() throws {
        let input = try fixturePNG()
        expectRejected(
            ["-i", input.path, "-o", directory.appendingPathComponent("out.jpg").path, "-t", "DEV"],
            containing: "出力ファイルの拡張子は .png"
        )
    }

    @Test func missingOutputDirectoryIsRejected() throws {
        let input = try fixturePNG()
        let output = directory.appendingPathComponent("missing").appendingPathComponent("out.png")
        expectRejected(
            ["-i", input.path, "-o", output.path, "-t", "DEV"],
            containing: "出力先のディレクトリがありません"
        )
    }

    @Test func invalidColorIsRejected() throws {
        let input = try fixturePNG()
        expectRejected(
            ["-i", input.path, "-t", "DEV", "--color", "zz"],
            containing: "色の指定が正しくありません"
        )
    }

    @Test func blankTitleIsRejected() throws {
        let input = try fixturePNG()
        expectRejected(["-i", input.path, "-t", "   "], containing: "title が空です")
    }

    @Test func invalidPositionIsRejected() throws {
        let input = try fixturePNG()
        expectRejected(
            ["-i", input.path, "-t", "DEV", "--position", "left"],
            containing: "位置の指定が正しくありません"
        )
    }

    @Test func defaultPositionIsBottom() throws {
        let input = try fixturePNG()
        let command = try BadgeIconCommand.parse(["-i", input.path, "-t", "DEV"])
        try command.validate()
        #expect(command.position == "bottom")
    }

    @Test func omittedPositionMatchesBottomRender() throws {
        let input = directory.appendingPathComponent("default-pos.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 64,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let omitted = directory.appendingPathComponent("default-omitted.png")
        let explicit = directory.appendingPathComponent("default-bottom.png")
        var command = try BadgeIconCommand.parse(["-i", input.path, "-o", omitted.path, "-t", "DEV", "-s", "v1"])
        try command.run()
        command = try BadgeIconCommand.parse([
            "-i", input.path, "-o", explicit.path, "-t", "DEV", "-s", "v1", "--position", "bottom",
        ])
        try command.run()
        let omittedImage = try load(omitted)
        let omittedPixels = try pixels(omittedImage)
        let explicitPixels = try pixels(try load(explicit))
        #expect(omittedPixels == explicitPixels)

        let source = try load(input)
        #expect(try rgba(omittedImage, x: 32, yFromTop: 4) == rgba(source, x: 32, yFromTop: 4))
        #expect(try rgba(omittedImage, x: 32, yFromTop: 60) != rgba(source, x: 32, yFromTop: 60))
    }

    @Test func bottomBandPaintsBottomAndLeavesTop() throws {
        let input = directory.appendingPathComponent("bottom.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 64,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let before = try load(input)
        let beforeTop = try rgba(before, x: 32, yFromTop: 4)
        let beforeBottom = try rgba(before, x: 32, yFromTop: 60)
        let output = directory.appendingPathComponent("bottom-out.png")
        try render(input: input, output: output, title: "DEV", subtitle: nil, position: .bottom)
        let after = try load(output)
        #expect(try rgba(after, x: 32, yFromTop: 4) == beforeTop)
        #expect(try rgba(after, x: 32, yFromTop: 60) != beforeBottom)
    }

    @Test func topBandPaintsTopAndLeavesBottom() throws {
        let input = directory.appendingPathComponent("top.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 64,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let before = try load(input)
        let beforeTop = try rgba(before, x: 32, yFromTop: 4)
        let beforeBottom = try rgba(before, x: 32, yFromTop: 60)
        let output = directory.appendingPathComponent("top-out.png")
        try render(input: input, output: output, title: "DEV", subtitle: nil, position: .top)
        let after = try load(output)
        #expect(try rgba(after, x: 32, yFromTop: 4) != beforeTop)
        #expect(try rgba(after, x: 32, yFromTop: 60) == beforeBottom)
    }

    @Test func ribbonPaintsTopRightAndLeavesBottomLeft() throws {
        let input = directory.appendingPathComponent("ribbon.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 64,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let before = try load(input)
        let beforeBottomLeft = try rgba(before, x: 4, yFromTop: 60)
        // 右上角からの距離 (13 + 13) / √2 ≈ 18.4。帯の中心 0.28 * 64 ≈ 17.9 に近く、縁の白線から離れている。
        let beforeRibbon = try rgba(before, x: 51, yFromTop: 13)
        let output = directory.appendingPathComponent("ribbon-out.png")
        try render(input: input, output: output, title: "DEV", subtitle: "v1", position: .ribbon)
        let after = try load(output)
        #expect(try rgba(after, x: 4, yFromTop: 60) == beforeBottomLeft)
        #expect(try rgba(after, x: 51, yFromTop: 13) != beforeRibbon)
    }

    @Test func topAndBottomRendersDiffer() throws {
        let input = directory.appendingPathComponent("diff.png")
        try writeImage(
            to: input,
            type: .png,
            width: 64,
            height: 64,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        let top = directory.appendingPathComponent("diff-top.png")
        let bottom = directory.appendingPathComponent("diff-bottom.png")
        try render(input: input, output: top, title: "DEV", subtitle: nil, position: .top)
        try render(input: input, output: bottom, title: "DEV", subtitle: nil, position: .bottom)
        let topPixels = try pixels(try load(top))
        let bottomPixels = try pixels(try load(bottom))
        #expect(topPixels != bottomPixels)
    }

    private func render(
        input: URL,
        output: URL,
        title: String,
        subtitle: String?,
        position: RibbonPosition = .bottom
    ) throws {
        try AppIconRenderer.render(
            input: input,
            output: output,
            title: title,
            subtitle: subtitle,
            color: try #require(RibbonColor.parse("#1E1E1ED9")),
            position: position
        )
    }

    private func validate(_ arguments: [String]) throws {
        let command = try BadgeIconCommand.parse(arguments)
        try command.validate()
    }

    private func expectRejected(_ arguments: [String], containing snippet: String) {
        do {
            try validate(arguments)
            Issue.record("エラーになりませんでした")
        } catch {
            let message = BadgeIconCommand.message(for: error)
            #expect(message.contains(snippet), "実際のメッセージ: \(message)")
        }
    }

    private func fixturePNG() throws -> URL {
        let url = directory.appendingPathComponent("in.png")
        try writeImage(
            to: url,
            type: .png,
            width: 16,
            height: 16,
            colorSpace: try #require(CGColorSpace(name: CGColorSpace.sRGB)),
            hasAlpha: false
        )
        return url
    }

    private func writeImage(
        to url: URL,
        type: UTType,
        width: Int,
        height: Int,
        bitsPerComponent: Int = 8,
        colorSpace: CGColorSpace,
        hasAlpha: Bool
    ) throws {
        let alpha: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        var bitmapInfo = alpha.rawValue
        if bitsPerComponent == 16 {
            bitmapInfo |= CGBitmapInfo.byteOrder16Little.rawValue
        }
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        let components: [CGFloat] = hasAlpha ? [0.2, 0.4, 0.9, 0.5] : [0.2, 0.4, 0.9, 1]
        context.setFillColor(try #require(CGColor(colorSpace: colorSpace, components: components)))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    private func load(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func profileName(_ url: URL) throws -> String? {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return properties[kCGImagePropertyProfileName] as? String
    }

    private struct RGBA: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }

    private func rgba(_ image: CGImage, x: Int, yFromTop: Int) throws -> RGBA {
        let data = try pixels(image)
        let row = firstRowIsTop ? yFromTop : (image.height - 1 - yFromTop)
        let offset = (row * image.width + x) * 4
        return RGBA(r: data[offset], g: data[offset + 1], b: data[offset + 2], a: data[offset + 3])
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    private func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        default:
            return true
        }
    }

    private static func detectFirstRowIsTop() throws -> Bool {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(try #require(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(try #require(CGColor(colorSpace: colorSpace, components: [0, 0, 1, 1])))
        context.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        let image = try #require(context.makeImage())

        var data = [UInt8](repeating: 0, count: 8)
        try data.withUnsafeMutableBytes { buffer in
            let read = try #require(CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            read.interpolationQuality = .none
            read.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 2))
        }
        // CG の y=1（上端）を青、y=0（下端）を赤にした。先頭が青ならバッファ先頭は上端。
        return data[2] > 200 && data[0] < 50
    }
}
