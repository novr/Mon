import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BadgeIcon

final class AppIconRendererTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        let untouched = try pixels(image)
        #expect((100...200).contains(Int(untouched[3])))
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
        let before = try pixels(try load(input))
        try render(input: input, output: input, title: "DEV", subtitle: "v1.2.0 (42)")
        let after = try pixels(try load(input))

        #expect(before.prefix(4) == after.prefix(4))
        #expect(before != after)
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

    private func render(input: URL, output: URL, title: String, subtitle: String?) throws {
        try AppIconRenderer.render(
            input: input,
            output: output,
            title: title,
            subtitle: subtitle,
            color: try #require(RibbonColor.parse("#1E1E1ED9"))
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
}
