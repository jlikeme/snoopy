// SnoopyClip.swift

import Foundation

class SnoopyClip: NSObject {
    var name: String = ""
    var startURL: String?
    var loopURL: String?
    var endURL: String?
    var repeatCount: Int = 0
    var from: String?
    var to: String?
    var others: [String] = []
    
    static func loadClips() -> [SnoopyClip] {
        guard let resourcePath = Bundle(for: self).resourcePath else { return [] }
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: resourcePath)
            let movFiles = files.filter { $0.hasSuffix(".mov") }
            
            var clipsDict: [String: SnoopyClip] = [:]
            
            for file in movFiles {
                let groupName = file.count >= 9 ? String(file.prefix(9)) : file
                
                let clip = clipsDict[groupName] ?? {
                    let newClip = SnoopyClip()
                    newClip.name = groupName
                    return newClip
                }()
                
                clipsDict[groupName] = clip
                
                if file.contains("Intro") {
                    clip.startURL = file
                    if file.contains("From") {
                        let fileNameWithoutExtension = file.deletingPathExtension
                        clip.from = String(fileNameWithoutExtension.suffix(5))
                    }
                } else if file.contains("Loop") {
                    clip.loopURL = file
                    clip.repeatCount = Int.random(in: 3...5)
                } else if file.contains("Outro") {
                    clip.endURL = file
                    if file.contains("To") {
                        let fileNameWithoutExtension = file.deletingPathExtension
                        clip.to = String(fileNameWithoutExtension.suffix(5))
                    }
                } else {
                    clip.others.append(file)
                }
            }
            
            return Array(clipsDict.values)
        } catch {
            print("Error reading Resources directory: \(error.localizedDescription)")
            return []
        }
    }
    
    static func randomClipURLs(_ clips: [SnoopyClip]) -> [String] {
        var mutableClips = clips
        var shuffledArray: [SnoopyClip] = []
        
        // Fisher-Yates 洗牌算法
        for i in (1..<mutableClips.count).reversed() {
            let j = Int.random(in: 0...i)
            mutableClips.swapAt(i, j)
        }
        
        var lastClip: SnoopyClip?
        
        while !mutableClips.isEmpty {
            // 50% 几率强制匹配 from 和 to
            let enforceMatching = Bool.random()
            var nextClip: SnoopyClip?
            
            if enforceMatching, let last = lastClip, let lastTo = last.to {
                if let matchIndex = mutableClips.firstIndex(where: { clip in
                    guard let from = clip.from else { return false }
                    return from == lastTo
                }) {
                    nextClip = mutableClips.remove(at: matchIndex)
                }
            }
            
            if nextClip == nil {
                nextClip = mutableClips.removeFirst()
            }
            
            if let clip = nextClip {
                shuffledArray.append(clip)
                lastClip = clip
            }
        }
        
        // 将clip转换为URL字符串数组
        var urlArray: [String] = []
        for clip in shuffledArray {
            if let startURL = clip.startURL {
                urlArray.append(startURL)
            }
            
            if let loopURL = clip.loopURL {
                for _ in 0..<clip.repeatCount {
                    urlArray.append(loopURL)
                }
            }
            
            if let endURL = clip.endURL {
                urlArray.append(endURL)
            }
            
            urlArray.append(contentsOf: clip.others)
        }
        
        return urlArray
    }
}

// String扩展添加方便的路径处理方法
extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}