import Foundation

struct IconElement {
    let type: String
    let file: String
}

private func appendUInt32BE(_ value: Int, to data: inout Data) {
    var number = UInt32(value).bigEndian
    withUnsafeBytes(of: &number) { data.append(contentsOf: $0) }
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make_icns <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let elements = [
    IconElement(type: "icp4", file: "icon_16x16.png"),
    IconElement(type: "ic11", file: "icon_16x16@2x.png"),
    IconElement(type: "icp5", file: "icon_32x32.png"),
    IconElement(type: "ic12", file: "icon_32x32@2x.png"),
    IconElement(type: "ic07", file: "icon_128x128.png"),
    IconElement(type: "ic13", file: "icon_128x128@2x.png"),
    IconElement(type: "ic08", file: "icon_256x256.png"),
    IconElement(type: "ic14", file: "icon_256x256@2x.png"),
    IconElement(type: "ic09", file: "icon_512x512.png"),
    IconElement(type: "ic10", file: "icon_512x512@2x.png")
]

let payloads: [(String, Data)] = try elements.map { element in
    let data = try Data(contentsOf: directory.appendingPathComponent(element.file))
    guard data.starts(with: [0x89, 0x50, 0x4e, 0x47]) else {
        throw NSError(domain: "SnowVibeIconBuilder", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "\(element.file) is not a PNG"
        ])
    }
    return (element.type, data)
}

let totalLength = 8 + payloads.reduce(0) { $0 + 8 + $1.1.count }
var result = Data("icns".utf8)
appendUInt32BE(totalLength, to: &result)
for (type, payload) in payloads {
    result.append(Data(type.utf8))
    appendUInt32BE(8 + payload.count, to: &result)
    result.append(payload)
}
try result.write(to: output, options: .atomic)
print(output.path)
