// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ElectronicPrescriptionMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ElectronicPrescriptionMac", targets: ["ElectronicPrescriptionMac"])],
    targets: [.executableTarget(name: "ElectronicPrescriptionMac")]
)
