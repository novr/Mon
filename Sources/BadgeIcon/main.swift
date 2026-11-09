import ArgumentParser
import Foundation

struct BadgeIconCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mon",
        abstract: "アプリアイコンに帯バッジを合成する"
    )

    @Option(name: .shortAndLong, help: "入力画像のパス")
    var input: String

    @Option(name: .shortAndLong, help: "出力 PNG のパス。省略時は入力が PNG のときだけ上書きする")
    var output: String?

    @Option(name: .shortAndLong, help: "帯の上段文字列")
    var title: String

    @Option(name: .shortAndLong, help: "帯の下段文字列")
    var subtitle: String?

    @Option(name: .long, help: "帯の色。#RRGGBB または #RRGGBBAA")
    var color: String = "#1E1E1ED9"

    @Option(name: .shortAndLong, help: "帯の位置。top（上端）、bottom（下端）、ribbon（右上の斜めリボン）。省略時は bottom")
    var position: String = "bottom"

    func validate() throws {
        _ = try resolved()
    }

    func run() throws {
        let job = try resolved()
        try AppIconRenderer.render(
            input: job.input,
            output: job.output,
            title: job.title,
            subtitle: job.subtitle,
            color: job.color,
            position: job.position
        )
    }

    private func resolved() throws -> RenderJob {
        let inputURL = URL(fileURLWithPath: input)
        var inputIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &inputIsDirectory) else {
            throw ValidationError("入力ファイルがありません: \(inputURL.path)")
        }
        guard !inputIsDirectory.boolValue else {
            throw ValidationError("入力パスがディレクトリです: \(inputURL.path)")
        }

        let outputURL: URL
        if let output {
            outputURL = URL(fileURLWithPath: output)
        } else if inputURL.pathExtension.lowercased() == "png" {
            outputURL = inputURL
        } else {
            throw ValidationError("入力が PNG ではないため、-o で .png の出力パスを指定してください")
        }

        guard outputURL.pathExtension.lowercased() == "png" else {
            throw ValidationError("出力ファイルの拡張子は .png にしてください: \(outputURL.path)")
        }
        var outputIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &outputIsDirectory), outputIsDirectory.boolValue {
            throw ValidationError("出力パスがディレクトリです: \(outputURL.path)")
        }

        let parentPath = outputURL.deletingLastPathComponent().path
        if !parentPath.isEmpty, parentPath != "." {
            var parentIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parentPath, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
                throw ValidationError("出力先のディレクトリがありません: \(parentPath)")
            }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ValidationError("title が空です")
        }

        let trimmedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSubtitle = (trimmedSubtitle?.isEmpty == false) ? trimmedSubtitle : nil

        guard let ribbonColor = RibbonColor.parse(color) else {
            throw ValidationError("色の指定が正しくありません（#RRGGBB または #RRGGBBAA）: \(color)")
        }

        guard let ribbonPosition = RibbonPosition.parse(position) else {
            throw ValidationError("位置の指定が正しくありません（top、bottom、ribbon）: \(position)")
        }

        return RenderJob(
            input: inputURL,
            output: outputURL,
            title: trimmedTitle,
            subtitle: resolvedSubtitle,
            color: ribbonColor,
            position: ribbonPosition
        )
    }
}

BadgeIconCommand.main()
