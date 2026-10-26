import Foundation

/// Dev-only CLI behind `make icons`, `make appicon` and `make seed`. Never shipped in the app bundle.
let usage = """
usage: kettle-tools <command>

commands:
  icons     render every icon state into build/icons/preview.png   (build step 6)
  appicon   regenerate Resources/AppIcon.icns                      (build step 15)
  seed      fill the dev data folder with two weeks of demo data   (build step 13)
"""

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "icons", "appicon", "seed":
    FileHandle.standardError.write(Data("kettle-tools \(arguments[0]): not implemented yet\n".utf8))
    exit(1)
default:
    print(usage)
    exit(arguments.isEmpty ? 0 : 64)
}
