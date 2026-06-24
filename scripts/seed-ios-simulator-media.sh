#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-booted}"
OUT_DIR="$(mktemp -d /tmp/photodelete-sim-seeds.XXXXXX)"
ASSET_DIR="$ROOT_DIR/Marketing/PhotoDeleteCampaign/appstore-video-square-v2-zh-20260618/assets"
SWIFT_HELPER="$OUT_DIR/make_seed_photos.swift"

cleanup() {
  rm -rf "$OUT_DIR"
}
trap cleanup EXIT

if [[ ! -d "$ASSET_DIR" ]]; then
  echo "Missing seed asset directory: $ASSET_DIR" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required to generate simulator seed videos." >&2
  exit 1
fi

cat > "$SWIFT_HELPER" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Seed {
    let src: String
    let out: String
    let date: String
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let srcDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let seeds: [Seed] = [
    Seed(src: "travel-seed-01.jpg", out: "pd-seed-20250321-shanghai.jpg", date: "2025:03:21 10:15:00", latitude: 31.2304, longitude: 121.4737, altitude: 12),
    Seed(src: "travel-seed-02.jpg", out: "pd-seed-20250404-hangzhou.jpg", date: "2025:04:04 16:45:00", latitude: 30.2741, longitude: 120.1551, altitude: 18),
    Seed(src: "travel-seed-03.jpg", out: "pd-seed-20250518-taipei.jpg", date: "2025:05:18 08:20:00", latitude: 25.0330, longitude: 121.5654, altitude: 22),
    Seed(src: "travel-seed-04.jpg", out: "pd-seed-20250601-hongkong.jpg", date: "2025:06:01 19:05:00", latitude: 22.3193, longitude: 114.1694, altitude: 10),
    Seed(src: "travel-seed-05.jpg", out: "pd-seed-20241225-tokyo.jpg", date: "2024:12:25 09:30:00", latitude: 35.6895, longitude: 139.6917, altitude: 40),
    Seed(src: "travel-seed-06.jpg", out: "pd-seed-20231102-paris.jpg", date: "2023:11:02 14:10:00", latitude: 48.8566, longitude: 2.3522, altitude: 35),
    Seed(src: "travel-seed-07.jpg", out: "pd-seed-20220910-newyork.jpg", date: "2022:09:10 11:55:00", latitude: 40.7128, longitude: -74.0060, altitude: 8),
    Seed(src: "travel-seed-08.jpg", out: "pd-seed-20200115-singapore.jpg", date: "2020:01:15 17:25:00", latitude: 1.3521, longitude: 103.8198, altitude: 15)
]

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let dateFormatter = DateFormatter()
dateFormatter.calendar = calendar
dateFormatter.timeZone = calendar.timeZone
dateFormatter.locale = Locale(identifier: "en_US_POSIX")
dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

for seed in seeds {
    for round in 0..<12 {
        let input = srcDir.appendingPathComponent(seed.src)
        let outputName = seed.out.replacingOccurrences(
            of: "pd-seed-",
            with: String(format: "pd-seed-r%02d-", round + 1)
        )
        let output = outDir.appendingPathComponent(outputName)
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil),
              let baseDate = dateFormatter.date(from: seed.date) else {
            fatalError("Unable to create seed image for \(seed.src)")
        }

        let captureDate = calendar.date(byAdding: .month, value: -(round * 3), to: baseDate) ?? baseDate
        let captureDateText = dateFormatter.string(from: captureDate)
        let latitude = seed.latitude + Double(round) * 0.006
        let longitude = seed.longitude + Double(round) * 0.006
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFDateTime: captureDateText
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: captureDateText,
                kCGImagePropertyExifDateTimeDigitized: captureDateText
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: abs(latitude),
                kCGImagePropertyGPSLatitudeRef: latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(longitude),
                kCGImagePropertyGPSLongitudeRef: longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSAltitude: seed.altitude
            ]
        ]

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Unable to finalize seed image for \(seed.src)")
        }
    }
}
SWIFT

swift "$SWIFT_HELPER" "$OUT_DIR" "$ASSET_DIR"

make_video() {
  local image_name="$1"
  local output_name="$2"
  local creation_time="$3"
  local iso_location="$4"

  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -t 4 -i "$ASSET_DIR/$image_name" \
    -f lavfi -t 4 -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    -vf "scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,format=yuv420p" \
    -metadata creation_time="$creation_time" \
    -metadata location="$iso_location" \
    -metadata com.apple.quicktime.location.ISO6709="$iso_location" \
    -movflags use_metadata_tags \
    -c:v libx264 -preset veryfast -crf 24 \
    -c:a aac \
    "$OUT_DIR/$output_name"
}

make_video "travel-seed-03.jpg" "pd-seed-video-20250602-hongkong.mov" "2025-06-02T11:05:00Z" "+22.3193+114.1694+000.000/"
make_video "travel-seed-05.jpg" "pd-seed-video-20241225-tokyo.mov" "2024-12-25T00:30:00Z" "+35.6895+139.6917+000.000/"
make_video "travel-seed-08.jpg" "pd-seed-video-20200115-singapore.mov" "2020-01-15T09:25:00Z" "+01.3521+103.8198+000.000/"

echo "Generated simulator media in $OUT_DIR"
ls -lh "$OUT_DIR"/pd-seed-* >&2
xcrun simctl addmedia "$DEVICE" "$OUT_DIR"/pd-seed-*.jpg "$OUT_DIR"/pd-seed-video-*.mov
echo "Imported 96 photos and 3 videos into simulator: $DEVICE"
