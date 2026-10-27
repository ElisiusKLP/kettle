import Foundation

/// Dev-only CLI behind `make icons`, `make appicon` and `make seed`. Never shipped in the app bundle.
let usage = """
usage: kettle-tools <command>

commands:
  icons [path]  render every icon state into build/icons/preview.png (or path)
  appicon       regenerate Resources/AppIcon.icns (and build/icons/appicon.png to review)
  seed [--brewing]
                fill the dev data folder (or KETTLE_DATA_DIR) with two weeks of demo
                data; --brewing starts today's first task
"""

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "icons":
        let path = arguments.count > 1 ? arguments[1] : "build/icons/preview.png"
        let url = URL(fileURLWithPath: path)
        try IconPreview.render(to: url)
        print("Wrote \(url.path)")
    case "seed":
        try Seed.run(arguments: Array(arguments.dropFirst()))
    case "appicon":
        let output = URL(fileURLWithPath: "Resources/AppIcon.icns")
        try AppIcon.build(output: output, previewPNG: URL(fileURLWithPath: "build/icons/appicon.png"))
        print("Wrote \(output.path) and build/icons/appicon.png")
    default:
        print(usage)
        exit(arguments.isEmpty ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
