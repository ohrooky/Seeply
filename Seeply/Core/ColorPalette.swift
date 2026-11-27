import Foundation

struct PalettePixel: Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, alpha: UInt8 = 255) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
}

struct PaletteColor: Identifiable, Sendable, Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let fraction: Double
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var id: String { hex }
}

struct PhotoPalette: Sendable, Equatable {
    let colors: [PaletteColor]
}

/// Deterministic, opacity-weighted clustering in perceptual Oklab space.
/// Input is an sRGB, premultiplied RGBA preview of the entire image.
enum PaletteExtractor {
    private struct Bin {
        var red = 0, green = 0, blue = 0, weight = 0
    }
    private struct Lab {
        var l: Double, a: Double, b: Double
        func distance(to other: Lab) -> Double {
            let dl = l - other.l, da = a - other.a, db = b - other.b
            return dl * dl + da * da + db * db
        }
    }
    private struct Point {
        let lab: Lab
        let weight: Double
    }

    static func extract(_ pixels: [PalettePixel], colorCount: Int = 4) -> PhotoPalette {
        guard colorCount > 0 else { return PhotoPalette(colors: []) }
        var bins: [Int: Bin] = [:]
        for pixel in pixels {
            let alpha = Int(pixel.alpha)
            guard alpha > 0 else { continue }
            func channel(_ value: UInt8) -> Int {
                min(255, (Int(value) * 255 + alpha / 2) / alpha)
            }
            let r = channel(pixel.red), g = channel(pixel.green), b = channel(pixel.blue)
            let key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
            var bin = bins[key] ?? Bin()
            bin.red += r * alpha; bin.green += g * alpha; bin.blue += b * alpha; bin.weight += alpha
            bins[key] = bin
        }
        let points = bins.keys.sorted().compactMap { key -> Point? in
            guard let bin = bins[key], bin.weight > 0 else { return nil }
            let w = Double(bin.weight)
            return Point(lab: oklab(red: Double(bin.red) / w / 255,
                                   green: Double(bin.green) / w / 255, blue: Double(bin.blue) / w / 255), weight: w)
        }
        guard let first = points.indices.max(by: { points[$0].weight < points[$1].weight }) else {
            return PhotoPalette(colors: [])
        }
        let count = min(8, colorCount, points.count)
        var centers = [points[first].lab]
        while centers.count < count {
            var selected: Int?
            var best = 0.0
            for index in points.indices {
                let distance = centers.map { points[index].lab.distance(to: $0) }.min() ?? 0
                let score = distance * sqrt(points[index].weight)
                if score > best { best = score; selected = index }
            }
            guard let selected, best > 1e-14 else { break }
            centers.append(points[selected].lab)
        }
        var weights = Array(repeating: 0.0, count: centers.count)
        for _ in 0..<16 {
            var sums = Array(repeating: Lab(l: 0, a: 0, b: 0), count: centers.count)
            weights = Array(repeating: 0, count: centers.count)
            for point in points {
                let index = centers.indices.min { point.lab.distance(to: centers[$0]) < point.lab.distance(to: centers[$1]) } ?? 0
                weights[index] += point.weight
                sums[index].l += point.lab.l * point.weight
                sums[index].a += point.lab.a * point.weight
                sums[index].b += point.lab.b * point.weight
            }
            var movement = 0.0
            for index in centers.indices where weights[index] > 0 {
                let next = Lab(l: sums[index].l / weights[index], a: sums[index].a / weights[index], b: sums[index].b / weights[index])
                movement += centers[index].distance(to: next)
                centers[index] = next
            }
            if movement < 1e-12 { break }
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return PhotoPalette(colors: []) }
        var unique: [String: PaletteColor] = [:]
        for index in centers.indices where weights[index] > 0 {
            let rgb = srgb(centers[index])
            let color = PaletteColor(red: rgb.0, green: rgb.1, blue: rgb.2, fraction: weights[index] / total)
            let oldFraction = unique[color.hex]?.fraction ?? 0
            unique[color.hex] = PaletteColor(red: color.red, green: color.green, blue: color.blue, fraction: color.fraction + oldFraction)
        }
        return PhotoPalette(colors: unique.values.sorted {
            $0.fraction == $1.fraction ? $0.hex < $1.hex : $0.fraction > $1.fraction
        })
    }

    // Oklab matrices by Björn Ottosson, published as public domain:
    // https://bottosson.github.io/posts/oklab/
    private static func oklab(red: Double, green: Double, blue: Double) -> Lab {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Lab(l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func srgb(_ color: Lab) -> (Int, Int, Int) {
        let l = pow(color.l + 0.3963377774 * color.a + 0.2158037573 * color.b, 3)
        let m = pow(color.l - 0.1055613458 * color.a - 0.0638541728 * color.b, 3)
        let s = pow(color.l - 0.0894841775 * color.a - 1.2914855480 * color.b, 3)
        func channel(_ value: Double) -> Int {
            let v = min(1, max(0, value))
            let encoded = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            return min(255, max(0, Int((encoded * 255).rounded())))
        }
        return (channel(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                channel(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                channel(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }
}
