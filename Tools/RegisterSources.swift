import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let project = root.appendingPathComponent("DreamTravelMobile.xcodeproj/project.pbxproj")
var text = try String(contentsOf: project, encoding: .utf8)
let files = ["Services/DiscoveryService.swift", "Services/ReferenceLibrary.swift", "Views/MobileReferenceLibraryView.swift", "Services/PlaceResearchService.swift", "Style/PlanThemeCatalog.swift", "Views/MobileThemeGalleryView.swift", "Services/PlaceReservation.swift", "Views/MobileBookingWebView.swift"]
for (offset, path) in files.enumerated() where FileManager.default.fileExists(atPath: root.appendingPathComponent("DreamTravelMobile/" + path).path) {
    let name = URL(fileURLWithPath: path).lastPathComponent
    if text.contains("path = DreamTravelMobile/" + path + ";") { continue }
    let fileID = String(format:"2000000000000000000000%02X", offset + 28)
    let buildID = String(format:"1000000000000000000000%02X", offset + 28)
    text = text.replacingOccurrences(of: "/* End PBXBuildFile section */", with: "\t\t\(buildID) /* \(name) in Sources */ = {isa = PBXBuildFile; fileRef = \(fileID) /* \(name) */; };\n/* End PBXBuildFile section */")
    text = text.replacingOccurrences(of: "/* End PBXFileReference section */", with: "\t\t\(fileID) /* \(name) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DreamTravelMobile/\(path); sourceTree = SOURCE_ROOT; };\n/* End PBXFileReference section */")
    text = text.replacingOccurrences(of: "20000000000000000000001B /* TencentTravelAPI.swift */,", with: "20000000000000000000001B /* TencentTravelAPI.swift */,\n\t\t\t\t\(fileID) /* \(name) */,")
    text = text.replacingOccurrences(of: "100000000000000000000019 /* TencentTravelAPI.swift in Sources */,", with: "100000000000000000000019 /* TencentTravelAPI.swift in Sources */,\n\t\t\t\t\(buildID) /* \(name) in Sources */,")
}
text = text.replacingOccurrences(of: "MARKETING_VERSION = 0.16.0", with: "MARKETING_VERSION = 0.16.1")
try text.write(to:project,atomically:true,encoding:.utf8)
