import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// usage: pdf2png in.pdf out.png scale
let a = CommandLine.arguments
let doc = CGPDFDocument(URL(fileURLWithPath: a[1]) as CFURL)!
let page = doc.page(at: 1)!
let box = page.getBoxRect(.mediaBox)
let s = CGFloat(Double(a[3])!)
let w = Int((box.width * s).rounded()), h = Int((box.height * s).rounded())
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: s, y: s)
ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
ctx.drawPDFPage(page)
let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
print(box.width, box.height, "->", w, h)
