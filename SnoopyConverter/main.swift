//
//  main.swift
//  SnoopyConverter
//
//  Created by GaoJing on 2025/7/3.
//

import Foundation

// 运行 AssetClipLoader 的主逻辑

let resourcesPath = "/Users/gaojing/Xcode/snoopy-swift/Resources/"

let clips = AssetClipLoader.loadAllClips(resourcesPath: resourcesPath)

// 遍历 clips 并导出为 .mov
for clip in clips {
    for phase in clip.phases {
        for sprite in phase.sprites {
            guard sprite.spriteType == "frameSequence" else { continue }

            let baseName = sprite.assetBaseName
            let digitCount = sprite.frameIndexDigitCount
            let startFrame = sprite.customTiming?.start ?? 0
            let endFrame = sprite.customTiming?.end ?? 0
            if startFrame == endFrame {
                continue
            }

            var imageURLs: [URL] = []

            let folderPath = resourcesPath + clip.fullFolderPath
            for frameIndex in startFrame...endFrame {
                let fileName = String(format: "%@_%0*d.heic", baseName, digitCount, frameIndex)
                let fileURL = URL(fileURLWithPath: folderPath).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    imageURLs.append(fileURL)
                } else {
                    print("⚠️ Missing frame: \(fileURL.lastPathComponent)")
                }
            }

            guard !imageURLs.isEmpty else {
                print("❌ No frames found for \(clip.assetFolder) / \(baseName)")
                continue
            }

            let exportName = baseName + ".mov"
            let outputURL = URL(fileURLWithPath: folderPath).appendingPathComponent(exportName)
            // 如果文件已存在则先删除，避免 AVAssetWriter 报错
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            exportFrameSequenceToMov(from: imageURLs, to: outputURL, frameRate: 24)
            print("exportFrameSequenceToMov for \(clip.assetFolder) / \(baseName)")
        }
    }
}


import AVFoundation
import ImageIO
import UniformTypeIdentifiers

func exportFrameSequenceToMov(from imageURLs: [URL], to outputURL: URL, frameRate: Int32) {
    guard !imageURLs.isEmpty else {
        print("⚠️ No image files provided for export.")
        return
    }

    guard let firstImageSource = CGImageSourceCreateWithURL(imageURLs[0] as CFURL, nil),
          let firstImage = CGImageSourceCreateImageAtIndex(firstImageSource, 0, nil) else {
        print("❌ Failed to read first image in sequence")
        return
    }

    let width = firstImage.width
    let height = firstImage.height

    do {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6000000,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoProfileLevelKey: "HEVC_Main_AutoLevel"
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let duration = CMTime(value: 1, timescale: frameRate)
        var time = CMTime.zero

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()

        var frameIndex = 0
        input.requestMediaDataWhenReady(on: DispatchQueue.global()) {
            
            guard let pool = adaptor.pixelBufferPool else {
                print("❌ adaptor.pixelBufferPool is nil, cannot proceed")
                input.markAsFinished()
                writer.cancelWriting()
                dispatchGroup.leave()
                return
            }

            while input.isReadyForMoreMediaData && frameIndex < imageURLs.count {
                autoreleasepool {
                    let url = imageURLs[frameIndex]
                    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                       let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
                       let pb = pixelBufferFromCGImage(img, using: pool) {
                        let alphaInfo = img.alphaInfo
                        if alphaInfo == .none || alphaInfo == .noneSkipLast || alphaInfo == .noneSkipFirst {
                            print("⚠️ 图像无 alpha 通道: \(url.lastPathComponent)")
                        }
                        adaptor.append(pb, withPresentationTime: time)
                        time = CMTimeAdd(time, duration)

                    } else {
                        print("⚠️ 图像未添加: \(url.lastPathComponent)")
                    }
                    frameIndex += 1
                }
            }
            if frameIndex >= imageURLs.count {
                input.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        print("✅ Exported: \(outputURL.lastPathComponent)")
                    } else {
                        print("❌ Failed to export: \(outputURL.lastPathComponent), error: \(writer.error?.localizedDescription ?? "unknown")")
                    }
                    dispatchGroup.leave()
                }
            }
        }
        dispatchGroup.wait()
        print("dispatchGroup.wait")
    } catch {
        print("❌ Failed to create video writer: \(error.localizedDescription)")
    }
}

func pixelBufferFromCGImage(_ image: CGImage, using pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    guard let buffer = pb else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )
    // 先清空整个 buffer，确保透明区域不会叠加
    context?.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
}
