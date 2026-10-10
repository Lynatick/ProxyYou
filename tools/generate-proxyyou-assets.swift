import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
func drawMark(_ color: NSColor, _ ringColor: NSColor) {
  ringColor.setStroke()
  let ring = NSBezierPath(ovalIn: NSRect(x:132,y:132,width:760,height:760)); ring.lineWidth = 44; ring.stroke()
  color.setFill()
  let p = NSBezierPath(); p.windingRule = .evenOdd
  p.move(to:NSPoint(x:345,y:295));p.line(to:NSPoint(x:345,y:725));p.line(to:NSPoint(x:530,y:725))
  p.curve(to:NSPoint(x:530,y:445),controlPoint1:NSPoint(x:745,y:725),controlPoint2:NSPoint(x:745,y:445))
  p.line(to:NSPoint(x:445,y:445));p.line(to:NSPoint(x:445,y:295));p.close()
  p.append(NSBezierPath(roundedRect:NSRect(x:445,y:535,width:145,height:100),xRadius:40,yRadius:40));p.fill()
}
func export(_ rel:String, _ width:Int, _ height:Int?=nil, _ kind:String="app") throws {
  let h=height ?? width
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
  let t=NSAffineTransform(); t.scaleX(by:CGFloat(width)/1024,yBy:CGFloat(h)/1024);t.concat()
  let navy=NSColor(srgbRed:11/255,green:31/255,blue:58/255,alpha:1)
  if kind == "banner" {
    navy.setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()
    let m=NSAffineTransform();m.translateX(by:40,yBy:195);m.scaleX(by:0.32,yBy:0.6);m.concat();drawMark(.white,NSColor(srgbRed:49/255,green:199/255,blue:216/255,alpha:1));m.invert();m.concat()
    let text="PROXYYOU" as NSString
    text.draw(at:NSPoint(x:380,y:410),withAttributes:[.font:NSFont.systemFont(ofSize:92,weight:.bold),.foregroundColor:NSColor.white])
  } else {
    if kind == "app" {navy.setFill();NSBezierPath(roundedRect:NSRect(x:0,y:0,width:1024,height:1024),xRadius:205,yRadius:205).fill()}
    let color:NSColor = kind == "light" ? .white : kind == "connected" ? NSColor(srgbRed:22/255,green:128/255,blue:60/255,alpha:1) : kind == "app" ? .white : .black
    let ringColor=kind == "app" ? NSColor(srgbRed:49/255,green:199/255,blue:216/255,alpha:1) : color
    drawMark(color,ringColor)
  }
  NSGraphicsContext.restoreGraphicsState()
  let url=root.appendingPathComponent(rel);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
  try bitmap.representation(using:.png,properties:[:])!.write(to:url)
}
for s in [16,32,64,128,256,512,1024] {try export("macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_\(s).png",s)}
for (density,s) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
  for n in ["ic_launcher","ic_launcher_round"] {try export("android/app/src/main/res/mipmap-\(density)/\(n).png",s)}
  try export("android/app/src/main/res/drawable-\(density)/ic_stat_logo.png",s/2,nil,"dark")
}
try export("android/app/src/main/ic_launcher-playstore.png",512)
try export("android/app/src/main/res/mipmap-xhdpi/ic_banner.png",320,180,"banner")
for n in ["tray_icon","tray_icon_dark","tray_icon_connected","tray_icon_disconnected"] {
  let mode=n == "tray_icon_dark" ? "light" : n == "tray_icon_connected" ? "connected" : "dark"
  try export("assets/images/\(n).png",64,nil,mode)
  if n != "tray_icon_dark" {try export("assets/images/source/\(n).png",64,nil,mode)}
}
try export("assets/images/source/ic_notify.png",96,nil,"dark")
for n in ["ic_launcher_border","ic_launcher_splash","ic_launcher_foreground"] {try export("assets/images/source/\(n).png",512)}
try export("web/icon.png",512)
try export("site/icon.png",512)
try export("linux/packaging/proxyyou.png",256)
for (name,s) in [("LaunchImage",168),("LaunchImage@2x",336),("LaunchImage@3x",504)] {try export("ios/Runner/Assets.xcassets/LaunchImage.imageset/\(name).png",s)}
try export("assets/images/connect_norouz.PNG",256)
try export("assets/images/disconnect_norouz.PNG",256)
print("Platform PNG assets generated")
