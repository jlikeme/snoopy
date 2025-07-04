//
//  AssetClipLoader.swift
//  snoopy
//
//  Created by GaoJing on 2025/7/1.
//

import Foundation

// MARK: - 通用结构体定义

enum AnimationClipType: String {
    case basePose          // BP: Base Pose，角色基础姿态，通常为角色静止或默认状态，可循环
    case additionalPose    // AP: Additional Pose，角色附加动作（Intro/Loop/Outro），描述角色的动态行为
    case activeScene       // AS: Active Scene，活动场景，描述场景动画，通常为 oneShot
    case idleScene         // IS: Idle Scene，静止场景/背景，通常为 oneShot，可能有偏移
    case sceneTransition   // ST: Scene Transition，场景转场动画，分为 hide/reveal 等阶段
    case transitionMask    // TM: Transition Mask，转场遮罩/遮罩动画，通常为多帧遮罩序列
    case customMotion      // CM: Custom/Complex Motion，自定义/复杂动作或转场，通常带有 from/to 信息
    case moment            // CM: Character Moment，角色特殊时刻/复杂转场
    case reactionTransition// RPH: Reaction/Hub/Path Transition，角色反应/枢纽/路径转场
    case reactionPose      // RPD: Reaction Pose，角色反应动作
    case poseTransition    // PT: Pose Transition，基础姿态转场
    case sceneTransitionPair // SceneTransitionPair: 转场遮罩配对
    case scenePalette      // ScenePalette: 场景调色板
    case randomPathHub     // RPH: Random Path/Hub，随机路径/枢纽，用于节点跳转（保留，兼容旧命名）
    case specialSequence   // SS: Special Sequence，独立/特殊序列，独立的动画片段
    case variant           // VI: Variant/Video Insert，变体/插入动画，特殊用途
    case weather           // WE: Weather，天气动画，表现天气变化
    case category          // Category: 分类标签，用于内容分组或筛选
    case idleSceneVisitor  // WE: Idle Scene Visitor/Weather Effect，天气/访客特效
    case switcherScene     // SS: Switcher Scene，切换场景/独立序列
    case additionalPoseIntro    // AP_Intro: Additional Pose Intro，角色附加动作-引入
    case additionalPoseLoop     // AP_Loop: Additional Pose Loop，角色附加动作-循环
    case additionalPoseOutro    // AP_Outro: Additional Pose Outro，角色附加动作-结尾
    case unknown           // 未知类型
}

enum AnimationClipGroupType: String {
    case pose
    case transition
    case other
}

enum AnimationPhaseType: String {
    case intro, loop, outro, oneShot, unknown
}

struct AnimationSprite {
    let assetBaseName: String
    let assetSize: [Double]
    let frameIndexDigitCount: Int
    let endBehavior: String
    let alignment: String
    let anchorTo: String
    let plane: String
    let spriteType: String
    let loopable: Bool?
    let customTiming: (start: Int, end: Int)?
}

struct AnimationPhase {
    let phaseType: AnimationPhaseType
    let sprites: [AnimationSprite]
}

struct ScenePaletteColor {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Double
}

struct ScenePaletteInfo {
    let weather: String?
    let timeOfDay: String?
}

struct SceneTransitionCategoryInfo {
    let hideCharacterPoseIDs: [String]
    let revealCharacterPoseIDs: [String]
    let sceneTransitionPairIDs: [String]
    let preventsIdleSceneChange: Bool
}

struct AnimationClipMetadata {
    let clipType: AnimationClipType
    let phases: [AnimationPhase]
    let startNode: String?
    let endNode: String?
    let transitionPhase: String?
    let transitionCategoryIDs: [String]?
    let sceneOffset: (x: Int, y: Int)?
    let assetFolder: String
    let fullFolderPath: String
    let startCharacterBasePoseID: String?
    let endCharacterBasePoseID: String?
    let reactionStyleID: String?
    let reactionTrigger: String?
    let hideStyleID: String?
    let revealStyleID: String?
    let backgroundColor: ScenePaletteColor?
    let overlayColor: ScenePaletteColor?
    let paletteInfo: ScenePaletteInfo?
    let transitionCategoryInfo: SceneTransitionCategoryInfo?
    let ignoresSceneOffset: Bool?
    let isFullscreenEffect: Bool?
    let poseID: String
}

// MARK: - 解析器

class AssetClipLoader {
    static func loadAllClips() -> [AnimationClipMetadata] {

        // 获取 Resources 目录路径
        guard let resourcesPath = Bundle(for: self).resourcePath else { return [] }
        
        return self.loadAllClips(resourcesPath: resourcesPath)
    }
    
    static func loadAllClips(resourcesPath: String) -> [AnimationClipMetadata] {
        var result: [AnimationClipMetadata] = []
        let fileManager = FileManager.default

        // 遍历 Resources 下所有主文件夹
        guard let mainFolders = try? fileManager.contentsOfDirectory(atPath: resourcesPath) else { return [] }
        for mainFolder in mainFolders {
            let mainFolderPath = (resourcesPath as NSString).appendingPathComponent(mainFolder)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: mainFolderPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // 遍历主文件夹下所有 .icasset 文件夹
            guard let assetFolders = try? fileManager.contentsOfDirectory(atPath: mainFolderPath) else { continue }
            for assetFolder in assetFolders where assetFolder.hasSuffix(".icasset") {
                let assetFolderPath = (mainFolderPath as NSString).appendingPathComponent(assetFolder)
                let metadataPath = (assetFolderPath as NSString).appendingPathComponent("metadata.icmetadata")
                guard fileManager.fileExists(atPath: metadataPath) else { continue }

                let fullFolderPath = "\(mainFolder)/\(assetFolder)"
                if let clips = parseMetadata(at: metadataPath, assetFolder: assetFolder, fullFolderPath: fullFolderPath) {
                    result.append(contentsOf: clips)
                }
            }
        }
        print("🔦 Asset clips loaded: \(result.count)")
        // 遍历result，按clipType分组
        var groupedClips: [AnimationClipGroupType: [AnimationClipMetadata]] = [:]
        for clip in result {
            groupedClips[clip.clipType.groupType, default: []].append(clip)
        }
        // // 打印分组结果
        // for (clipGroupType, clips) in groupedClips {
        //     print("🔦 Clip type: \(clipGroupType), count: \(clips.count)")
        //     for clip in clips {
        //         if clip.clipType.groupType != .other {
        //             print("🔦 Clip: \(clip.assetFolder)")
        //         }
        //     }
        // }
        return result
    }

    private static func parseMetadata(at path: String, assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }

        guard let rootKey = plist.keys.first, let rootDict = plist[rootKey] as? [String: Any], let _0 = rootDict["_0"] as? [String: Any] else { return nil }
        let assetContainer = (_0["assetContainer"] as? [String: Any]) ?? [:]
        let content = (assetContainer["content"] as? [String: Any]) ?? [:]

        switch rootKey {
        case "characterBasePose":
            // BP
            return parseBasePose(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "characterAdditionalPose":
            // AP
            return parseAdditionalPose(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "activeScene":
            // AS
            return parseActiveScene(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "idleScene":
            // IS
            return parseIdleScene(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "characterSceneTransitionPose":
            // ST
            return parseSceneTransition(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "characterReactionTransitionPose":
            // RPH/reactionTransition
            return parseReactionTransition(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "characterReactionPose":
            // RPD/reactionPose
            return parseReactionPose(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "characterPoseTransition":
            // BP_To/poseTransition
            return parsePoseTransition(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "characterMoment":
            // CM/moment
            return parseMoment(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "sceneTransitionPair":
            // SceneTransitionPair
            return parseSceneTransitionPair(_0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "scenePalette":
            // ScenePalette
            return parseScenePalette(_0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "sceneTransitionCategory":
            // SceneTransitionCategory
            return parseSceneTransitionCategory(_0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "spriteTransitionParameters":
            // TM: Transition Mask（新格式）
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .transitionMask, fullFolderPath: fullFolderPath)
        // 通用 oneShotSprites 结构类型
        case "transitionMask":
            // TM
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .transitionMask, fullFolderPath: fullFolderPath)
        case "customMotion":
            // CM
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .customMotion, fullFolderPath: fullFolderPath)
        case "randomPathHub":
            // RPH(兼容旧命名)
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .randomPathHub, fullFolderPath: fullFolderPath)
        case "specialSequence":
            // SS
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .specialSequence, fullFolderPath: fullFolderPath)
        case "variant":
            // VI
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .variant, fullFolderPath: fullFolderPath)
        case "weather":
            // WE
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .weather, fullFolderPath: fullFolderPath)
        case "category":
            // Category
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .category, fullFolderPath: fullFolderPath)
        case "idleSceneVisitor":
            // WE: Idle Scene Visitor/Weather Effect
            return parseIdleSceneVisitor(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        case "switcherScene":
            // SS: Switcher Scene
            return parseSwitcherScene(content: content, _0: _0, assetFolder: assetFolder, fullFolderPath: fullFolderPath)
        default:
            print("🔦 Unknown clip type: \(rootKey), assetFolder: \(assetFolder)")
            // 依然尝试用通用解析，clipType设为.unknown
            return parseGenericOneShot(content: content, _0: _0, assetFolder: assetFolder, type: .unknown, fullFolderPath: fullFolderPath)
        }
    }

    // 通用 oneShotSprites 结构解析
    private static func parseGenericOneShot(content: [String: Any], _0: [String: Any], assetFolder: String, type: AnimationClipType, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: type,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    // MARK: - 各类型解析

    private static func parseBasePose(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .basePose,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    private static func parseAdditionalPose(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let phasedSpritesDict = content["phasedSprites"] as? [String: Any],
              let phasedSprites = phasedSpritesDict["phasedSprites"] as? [String: Any] else { return nil }
        let startNode = _0["startCharacterBasePoseID"] as? String
        let endNode = _0["endCharacterBasePoseID"] as? String
        let startCharacterBasePoseID = _0["startCharacterBasePoseID"] as? String
        let endCharacterBasePoseID = _0["endCharacterBasePoseID"] as? String
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        // 取loopSprites的AssetBaseName去掉_Loop后作为loopCharacterBasePoseID
        var loopCharacterBasePoseID = _0["loopCharacterBasePoseID"] as? String
        if let loopSpritesDict = phasedSprites["loopSprites"] as? [String: Any],
           let spritesArr = loopSpritesDict["sprites"] as? [[String: Any]],
           let firstSprite = spritesArr.first,
           let atlasDict = firstSprite["atlas"] as? [String: Any],
           let assetBaseName = atlasDict["assetBaseName"] as? String {
            loopCharacterBasePoseID = assetBaseName.replacingOccurrences(of: "_Loop", with: "")
        }
        var result: [AnimationClipMetadata] = []
        let phaseMap: [(String, AnimationClipType, AnimationPhaseType, String?, String?)] = [
            ("introSprites", .additionalPoseIntro, .intro, startCharacterBasePoseID, loopCharacterBasePoseID),
            ("loopSprites", .additionalPoseLoop, .loop, nil, nil),
            ("outroSprites", .additionalPoseOutro, .outro, loopCharacterBasePoseID, endCharacterBasePoseID)
        ]
        for (phaseKey, clipType, phaseType, startID, endID) in phaseMap {
            if let phaseDict = phasedSprites[phaseKey] as? [String: Any],
               let spritesArr = phaseDict["sprites"] as? [[String: Any]] {
                let sprites = spritesArr.compactMap { parseSprite($0, loopable: nil, fullFolderPath: fullFolderPath) }
                let phase = AnimationPhase(phaseType: phaseType, sprites: sprites)
                var poseID = phase.sprites.first?.assetBaseName ?? ""
                if phaseType == .loop {
                    poseID = loopCharacterBasePoseID ?? ""
                }
                result.append(AnimationClipMetadata(
                    clipType: clipType,
                    phases: [phase],
                    startNode: startNode,
                    endNode: endNode,
                    transitionPhase: nil,
                    transitionCategoryIDs: transitionCategoryIDs,
                    sceneOffset: nil,
                    assetFolder: assetFolder,
                    fullFolderPath: fullFolderPath,
                    startCharacterBasePoseID: startID,
                    endCharacterBasePoseID: endID,
                    reactionStyleID: nil,
                    reactionTrigger: nil,
                    hideStyleID: nil,
                    revealStyleID: nil,
                    backgroundColor: nil,
                    overlayColor: nil,
                    paletteInfo: nil,
                    transitionCategoryInfo: nil,
                    ignoresSceneOffset: nil,
                    isFullscreenEffect: nil,
                    poseID: poseID
                ))
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func parseActiveScene(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .activeScene,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    private static func parseIdleScene(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        var sceneOffset: (x: Int, y: Int)? = nil
        if let offset = _0["sceneOffset"] as? [String: Any],
           let x = offset["x"] as? Int,
           let y = offset["y"] as? Int {
            sceneOffset = (x, y)
        }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .idleScene,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: sceneOffset,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    private static func parseSceneTransition(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let transitionPhase = _0["transitionPhase"] as? String
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .sceneTransition,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: transitionPhase,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    // 新增 reactionTransition 解析
    private static func parseReactionTransition(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        // 解析 phase.exit.endCharacterPoseID
        var endCharacterBasePoseID: String? = nil
        if let phaseDict = _0["phase"] as? [String: Any],
           let exitDict = phaseDict["exit"] as? [String: Any],
           let endID = exitDict["endCharacterPoseID"] as? String {
            endCharacterBasePoseID = endID
        }
        // 解析 phase.enter.startCharacterPoseID
        var startCharacterBasePoseID: String? = nil
        if let phaseDict = _0["phase"] as? [String: Any],
           let enterDict = phaseDict["enter"] as? [String: Any],
           let startID = enterDict["startCharacterPoseID"] as? String {
            startCharacterBasePoseID = startID
        }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        var reactionStyleID = _0["reactionStyleID"] as? String

        if reactionStyleID == nil && phases.first?.sprites.first?.assetBaseName.contains("RPH") ?? false {
            reactionStyleID = "standardReactionTransitionStyleID"
        }
        
        // 如果endCharacterBasePoseID为nil，使用reactionStyleID
        let finalEndCharacterBasePoseID = endCharacterBasePoseID ?? reactionStyleID
        // 如果startCharacterBasePoseID为nil，使用reactionStyleID
        let finalStartCharacterBasePoseID = startCharacterBasePoseID ?? reactionStyleID
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .reactionTransition,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: finalStartCharacterBasePoseID,
                endCharacterBasePoseID: finalEndCharacterBasePoseID,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    // 新增 reactionPose 解析
    private static func parseReactionPose(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        // 解析 reactionStyleID
        let reactionStyleID = _0["reactionStyleID"] as? String
        // 解析 relevancyData.info.reactionTrigger
        var reactionTrigger: String? = nil
        if let relevancyData = _0["relevancyData"] as? [String: Any],
           let infoArr = relevancyData["info"] as? [[String: Any]],
           let firstInfo = infoArr.first,
           let triggerDict = firstInfo["reactionTrigger"] as? [String: Any],
           let trigger = triggerDict["reactionTrigger"] as? String {
            reactionTrigger = trigger
        }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .reactionPose,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: reactionStyleID,
                reactionTrigger: reactionTrigger,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: reactionStyleID ?? phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    // 新增 poseTransition 解析
    private static func parsePoseTransition(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let startCharacterBasePoseID = _0["startCharacterBasePoseID"] as? String
        let endCharacterBasePoseID = _0["endCharacterBasePoseID"] as? String
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .poseTransition,
                phases: [phase],
                startNode: startCharacterBasePoseID,
                endNode: endCharacterBasePoseID,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: startCharacterBasePoseID,
                endCharacterBasePoseID: endCharacterBasePoseID,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    // 新增 moment 解析
    private static func parseMoment(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let startCharacterBasePoseID = _0["startCharacterBasePoseID"] as? String
        let endCharacterBasePoseID = _0["endCharacterBasePoseID"] as? String
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .moment,
                phases: [phase],
                startNode: startCharacterBasePoseID,
                endNode: endCharacterBasePoseID,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: startCharacterBasePoseID,
                endCharacterBasePoseID: endCharacterBasePoseID,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    // 新增 sceneTransitionPair 解析
    private static func parseSceneTransitionPair(_0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        // 提取 hideStyle.sprite.parametersID 和 revealStyle.sprite.parametersID
        var hideStyleID: String? = nil
        var revealStyleID: String? = nil
        if let hideStyle = _0["hideStyle"] as? [String: Any],
           let sprite = hideStyle["sprite"] as? [String: Any],
           let parametersID = sprite["parametersID"] as? String {
            hideStyleID = parametersID
        }
        if let revealStyle = _0["revealStyle"] as? [String: Any],
           let sprite = revealStyle["sprite"] as? [String: Any],
           let parametersID = sprite["parametersID"] as? String {
            revealStyleID = parametersID
        }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = [
            AnimationClipMetadata(
                clipType: .sceneTransitionPair,
                phases: [],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: hideStyleID,
                revealStyleID: revealStyleID,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: assetFolder
            )
        ]
        return result
    }

    // 新增 scenePalette 解析
    private static func parseScenePalette(_0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        func parseColor(_ dict: [String: Any]) -> ScenePaletteColor? {
            guard let red = dict["red"] as? Int,
                  let green = dict["green"] as? Int,
                  let blue = dict["blue"] as? Int,
                  let alpha = dict["alpha"] as? Double else { return nil }
            return ScenePaletteColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        let backgroundColor = (_0["backgroundColor"] as? [String: Any]).flatMap(parseColor)
        let overlayColor = (_0["overlayColor"] as? [String: Any]).flatMap(parseColor)
        var weather: String? = nil
        var timeOfDay: String? = nil
        if let relevancyData = _0["relevancyData"] as? [String: Any],
           let infoArr = relevancyData["info"] as? [[String: Any]] {
            for info in infoArr {
                if let weatherDict = info["weather"] as? [String: Any],
                   let cond = weatherDict["condition"] as? String {
                    weather = cond
                }
                if let todDict = info["timeOfDay"] as? [String: Any],
                   let tod = todDict["timeOfDay"] as? String {
                    timeOfDay = tod
                }
            }
        }
        let paletteInfo = ScenePaletteInfo(weather: weather, timeOfDay: timeOfDay)
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = [
            AnimationClipMetadata(
                clipType: .scenePalette,
                phases: [],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: backgroundColor,
                overlayColor: overlayColor,
                paletteInfo: paletteInfo,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: assetFolder
            )
        ]
        return result
    }

    // 新增 sceneTransitionCategory 解析
    private static func parseSceneTransitionCategory(_0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        let hideIDs = _0["hideCharacterPoseIDs"] as? [String] ?? []
        let revealIDs = _0["revealCharacterPoseIDs"] as? [String] ?? []
        let pairIDs = _0["sceneTransitionPairIDs"] as? [String] ?? []
        let preventsIdle = _0["preventsIdleSceneChange"] as? Bool ?? false
        let info = SceneTransitionCategoryInfo(
            hideCharacterPoseIDs: hideIDs,
            revealCharacterPoseIDs: revealIDs,
            sceneTransitionPairIDs: pairIDs,
            preventsIdleSceneChange: preventsIdle
        )
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = [
            AnimationClipMetadata(
                clipType: .category,
                phases: [],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: info,
                ignoresSceneOffset: nil,
                isFullscreenEffect: nil,
                poseID: assetFolder
            )
        ]
        return result
    }

    // MARK: - Sprite解析
    private static func parseSprite(_ dict: [String: Any], loopable: Bool?, fullFolderPath: String) -> AnimationSprite? {
        guard let atlas = dict["atlas"] as? [String: Any],
              let assetBaseName = atlas["assetBaseName"] as? String,
              let assetSize = atlas["assetSize"] as? [Double],
              let frameIndexDigitCount = atlas["frameIndexDigitCount"] as? Int,
              let endBehavior = dict["endBehavior"] as? String,
              let placement = dict["placement"] as? [String: Any],
              let anchored = placement["anchored"] as? [String: Any],
              let alignment = anchored["alignment"] as? String,
              let anchorTo = anchored["to"] as? String,
              let plane = dict["plane"] as? String,
              var spriteType = dict["spriteType"] as? String
        else { return nil }
        var customTiming: (start: Int, end: Int)? = nil
        if let timing = dict["customTiming"] as? [String: Any],
           let start = timing["start"] as? Int,
           let end = timing["end"] as? Int {
            customTiming = (start, end)
        }

        // 如果 spriteType 为 frameSequence，检查对应 .mov 文件是否存在
        if spriteType == "frameSequence" && customTiming?.start != customTiming?.end {
            let folderPath = ((Bundle(for: self).resourcePath ?? "") as NSString).appendingPathComponent(fullFolderPath)
            let movPath = (folderPath as NSString).appendingPathComponent(assetBaseName + ".mov")
            if FileManager.default.fileExists(atPath: movPath) {
                spriteType = "video"
            }
        }


        return AnimationSprite(
            assetBaseName: assetBaseName,
            assetSize: assetSize,
            frameIndexDigitCount: frameIndexDigitCount,
            endBehavior: endBehavior,
            alignment: alignment,
            anchorTo: anchorTo,
            plane: plane,
            spriteType: spriteType,
            loopable: loopable,
            customTiming: customTiming
        )
    }

    private static func parseIdleSceneVisitor(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let oneShotSpritesDict = content["oneShotSprites"] as? [String: Any],
              let oneShotSprites = oneShotSpritesDict["oneShotSprites"] as? [String: Any],
              let spritesArr = oneShotSprites["sprites"] as? [[String: Any]] else { return nil }
        let loopable = oneShotSprites["loopable"] as? Bool
        let sprites = spritesArr.compactMap { parseSprite($0, loopable: loopable, fullFolderPath: fullFolderPath) }
        let phases = sprites.map { AnimationPhase(phaseType: .oneShot, sprites: [$0]) }
        let ignoresSceneOffset = _0["ignoresSceneOffset"] as? Bool
        let isFullscreenEffect = _0["isFullscreenEffect"] as? Bool
        // 解析所有weather condition
        var weatherConditions: [String] = []
        if let relevancyData = _0["relevancyData"] as? [String: Any],
           let infoArr = relevancyData["info"] as? [[String: Any]] {
            for info in infoArr {
                if let weatherDict = info["weather"] as? [String: Any],
                   let cond = weatherDict["condition"] as? String {
                    weatherConditions.append(cond)
                }
            }
        }
        if !weatherConditions.isEmpty {
            print("🔦 idleSceneVisitor weather conditions: \(weatherConditions) for asset: \(assetFolder)")
        }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        let result = phases.map { phase in
            AnimationClipMetadata(
                clipType: .idleSceneVisitor,
                phases: [phase],
                startNode: nil,
                endNode: nil,
                transitionPhase: nil,
                transitionCategoryIDs: transitionCategoryIDs,
                sceneOffset: nil,
                assetFolder: assetFolder,
                fullFolderPath: fullFolderPath,
                startCharacterBasePoseID: nil,
                endCharacterBasePoseID: nil,
                reactionStyleID: nil,
                reactionTrigger: nil,
                hideStyleID: nil,
                revealStyleID: nil,
                backgroundColor: nil,
                overlayColor: nil,
                paletteInfo: nil,
                transitionCategoryInfo: nil,
                ignoresSceneOffset: ignoresSceneOffset,
                isFullscreenEffect: isFullscreenEffect,
                poseID: phase.sprites.first?.assetBaseName ?? ""
            )
        }
        return result
    }

    private static func parseSwitcherScene(content: [String: Any], _0: [String: Any], assetFolder: String, fullFolderPath: String) -> [AnimationClipMetadata]? {
        guard let phasedSpritesDict = content["phasedSprites"] as? [String: Any],
              let phasedSprites = phasedSpritesDict["phasedSprites"] as? [String: Any] else { return nil }
        let transitionCategoryIDs = _0["transitionCategoryIDs"] as? [String]
        var result: [AnimationClipMetadata] = []
        let phaseMap: [(String, AnimationPhaseType)] = [
            ("introSprites", .intro),
            ("loopSprites", .loop),
            ("outroSprites", .outro)
        ]
        for (phaseKey, phaseType) in phaseMap {
            if let phaseDict = phasedSprites[phaseKey] as? [String: Any],
               let spritesArr = phaseDict["sprites"] as? [[String: Any]] {
                let sprites = spritesArr.compactMap { parseSprite($0, loopable: nil, fullFolderPath: fullFolderPath) }
                let phase = AnimationPhase(phaseType: phaseType, sprites: sprites)
                result.append(AnimationClipMetadata(
                    clipType: .switcherScene,
                    phases: [phase],
                    startNode: nil,
                    endNode: nil,
                    transitionPhase: nil,
                    transitionCategoryIDs: transitionCategoryIDs,
                    sceneOffset: nil,
                    assetFolder: assetFolder,
                    fullFolderPath: fullFolderPath,
                    startCharacterBasePoseID: nil,
                    endCharacterBasePoseID: nil,
                    reactionStyleID: nil,
                    reactionTrigger: nil,
                    hideStyleID: nil,
                    revealStyleID: nil,
                    backgroundColor: nil,
                    overlayColor: nil,
                    paletteInfo: nil,
                    transitionCategoryInfo: nil,
                    ignoresSceneOffset: nil,
                    isFullscreenEffect: nil,
                    poseID: phase.sprites.first?.assetBaseName ?? ""
                ))
            }
        }
        return result.isEmpty ? nil : result
    }
}

extension AnimationClipType {
    var groupType: AnimationClipGroupType {
        switch self {
        case .additionalPoseLoop, .basePose, .reactionPose:
//        case .additionalPoseLoop, .basePose:
            return .pose
        case .poseTransition, .moment, .reactionTransition, .additionalPoseIntro, .additionalPoseOutro:
            return .transition
        default:
            return .other
        }
    }
}

extension AnimationClipMetadata {
    var assetBaseName: String {
        return self.phases.first?.sprites.first?.assetBaseName ?? ""
    }
}
