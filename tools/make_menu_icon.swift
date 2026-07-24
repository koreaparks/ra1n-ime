import Cocoa

let size1x: CGFloat = 16
let size2x: CGFloat = 32

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    
    // 완전 투명 배경으로 초기화
    ctx.clear(rect)
    
    // SF Symbol drop.fill 사용
    if let symbol = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.85, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config)!
        let symbolSize = configured.size
        let x = (size - symbolSize.width) / 2
        let y = (size - symbolSize.height) / 2
        configured.draw(at: NSPoint(x: x, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    image.unlockFocus()
    return image
}

let img1x = makeIcon(size: size1x)
let img2x = makeIcon(size: size2x)

let tiffData = img1x.tiffRepresentation!
let rep1x = NSBitmapImageRep(data: tiffData)!
rep1x.size = NSSize(width: size1x, height: size1x)

let tiffData2x = img2x.tiffRepresentation!
let rep2x = NSBitmapImageRep(data: tiffData2x)!
rep2x.size = NSSize(width: size1x, height: size1x)

let combined = NSImage(size: NSSize(width: size1x, height: size1x))
combined.addRepresentation(rep1x)
combined.addRepresentation(rep2x)

let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("MenuIcon.tiff")

try combined.tiffRepresentation!.write(to: outURL)
print("Saved: \(outURL.path)")
