import Foundation

/// Dev-only CLI behind `make icons`, `make appicon` and `make seed`. Never shipped in the app bundle.
let usage = """
usage: kettle-tools <command>

commands:
  icons [path]  render every icon state into build/icons/preview.png (or path)
  appicon       regenerate Resources/AppIcon.icns                      (build step 15)
  seed          fill the dev data folder with two weeks of demo data   (build step 13)
"""

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "icons":
        let path = arguments.count > 1 ? arguments[1] : "build/icons/preview.png"
        let url = URL(fileURLWithPath: path)
        try IconPreview.render(to: url)
        print("Wrote \(url.path)")
    case "appicon", "seed":
        throw ToolError("kettle-tools \(arguments[0]): not implemented yet")
    default:
        print(usage)
        exit(arguments.isEmpty ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
