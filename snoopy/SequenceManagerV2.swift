import Foundation

/// A new sequence manager that generates a sequence of poses and transitions based on AssetClipLoader logic.
class SequenceManagerV2 {
    private let allClips: [AnimationClipMetadata]
    private var rng = SystemRandomNumberGenerator()
    private let stateManager: StateManagerV2

    init(stateManager: StateManagerV2, allClips: [AnimationClipMetadata]) {
        self.stateManager = stateManager
        // Load all clips from assets
        self.allClips = allClips
        // Find all base poses
        reset()
    }

    /// Returns the next sequence based on lastClip and its groupType
    func nextStep() {
        guard let lastClip = stateManager.currentClipsQueue.last else {
            debugLog("[SequenceManagerV2] No last clip set and currentClipsQueue is empty.")
            return
        }
        // stateManager?.currentClipsQueue 最大个数为5
        if stateManager.currentClipsQueue.count >= 5 {
            debugLog("[SequenceManagerV2] Current clips queue is full, cannot add more clips.")
            return
        }
        var nextClip: AnimationClipMetadata?
        switch lastClip.groupType {
        case .pose:
            // Find all transitions starting from this pose
            let transitions = allClips.filter {
                $0.groupType == .transition && $0.startCharacterBasePoseID == lastClip.poseID ||
                ($0.clipType == .category && $0.transitionCategoryInfo?.revealCharacterPoseIDs.count == 0)
            }
            nextClip = transitions.randomElement(using: &rng)
        case .transition:
            // If last was a transition, go to its end pose
            guard let nextPoseID = lastClip.endCharacterBasePoseID else {
                debugLog("[SequenceManagerV2] Transition has no endCharacterBasePoseID: \(lastClip.poseID)")
                return
            }
            let nextPoses = allClips.filter {
                $0.groupType == .pose && $0.poseID == nextPoseID
            }
            nextClip = nextPoses.randomElement(using: &rng)
           
        case .other:
            // For other types, just pick a random base pose
            debugLog("[SequenceManagerV2] Last clip is of type .other, picking a random base pose.")
        }
        if let next = nextClip {
            if next.clipType != .category {
                stateManager.currentClipsQueue.append(next)
                debugLog("[SequenceManagerV2] Next clip added to queue: \(next.poseID) (\(next.clipType))")
                if next.phases.first?.sprites.first?.loopable ?? false {
                    // 从0-5创建随机数
                    let randomLoopCount = Int.random(in: 0...5)
                    for _ in 0..<randomLoopCount {
                        stateManager.currentClipsQueue.append(next)
                        debugLog("[SequenceManagerV2] Looping clip: \(next.poseID) (\(next.clipType))")
                    }
                }
            }
            
            if next.clipType == .sceneTransitionPose {
                // 查找其对应的所有category clip
                let categoryClips = allClips.filter {
                    $0.clipType == .category && $0.startCharacterBasePoseID == next.poseID
                }
                nextClip = categoryClips.randomElement(using: &rng)
            }
            
            if nextClip?.clipType == .category {
                if let categoryClip = nextClip {
                    // 查找activeScene中包含该category的所有clip
                    let activeSceneClips = allClips.filter {
                        $0.clipType == .activeScene && $0.transitionCategoryIDs?.contains(categoryClip.poseID) == true
                    }
                    if let sceneClip = activeSceneClips.randomElement(using: &rng) {
                        // 查找对应的scene transition pair
                        var revealClip: AnimationClipMetadata?
                        var hideClip: AnimationClipMetadata?
                        if let sceneTransitionPairs = categoryClip.transitionCategoryInfo?.sceneTransitionPairIDs {
                            let pair = sceneTransitionPairs.randomElement(using: &rng)
                            let pairClip = allClips.first(where: { $0.poseID == pair })
                            revealClip = allClips.first(where: { $0.poseID == pairClip?.revealStyleID })
                            hideClip = allClips.first(where: { $0.poseID == pairClip?.hideStyleID })
                        }
                        
                        if let revealClip = revealClip {
                            stateManager.currentClipsQueue.append(revealClip)
                            debugLog("[SequenceManagerV2] Added reveal clip: \(revealClip.poseID) for category \(categoryClip.poseID)")
                        }
                        
                        stateManager.currentClipsQueue.append(sceneClip)
                        debugLog("[SequenceManagerV2] Added active scene clip: \(sceneClip.poseID) for category \(categoryClip.poseID)")
                        
                        if let hideClip = hideClip {
                            stateManager.currentClipsQueue.append(hideClip)
                            debugLog("[SequenceManagerV2] Added hide clip: \(hideClip.poseID) for category \(categoryClip.poseID)")
                        }

                        // 添加category clip中的hide clip
                        if let hideClips = categoryClip.transitionCategoryInfo?.hideCharacterPoseIDs {
                            for hidePoseID in hideClips {
                                if let hideClip = allClips.first(where: { $0.assetBaseName == hidePoseID }) {
                                    // 添加hide clip到队列
                                    stateManager.currentClipsQueue.append(hideClip)
                                    debugLog("[SequenceManagerV2] Added hide clip: \(hideClip.poseID) for category \(categoryClip.poseID)")
                                    // 查找后续的transition clips
                                    let transitionClips = allClips.filter {
                                        $0.groupType == .transition && $0.startCharacterBasePoseID == hideClip.poseID
                                    }
                                    if let nextTransitionClip = transitionClips.randomElement(using: &rng) {
                                        stateManager.currentClipsQueue.append(nextTransitionClip)
                                        debugLog("[SequenceManagerV2] Added transition clip: \(nextTransitionClip.poseID) after hide clip \(hideClip.poseID)")
                                    }
                                    break // 只添加第一个hide clip
                                }
                            }
                        }
                    } else {
                        errorLog("[SequenceManagerV2] No active scene clips found for category \(categoryClip.poseID)")
                    }
                }
            }
            nextStep() // 递归调用以继续生成序列
        }
    }
    
    // 异步执行nextStep
    func nextStepAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.nextStep()
        }
    }

    /// Resets to a new random base pose
    func reset() {
        let basePoses = allClips.filter { $0.clipType == .basePose }
        guard let randomPose = basePoses.randomElement(using: &rng) else {
            print("[SequenceManagerV2] No base poses found for reset!")
            return
        }
        self.stateManager.currentClipsQueue.append(randomPose)
        print("[SequenceManagerV2] Reset to base pose: \(randomPose.poseID)")
        nextStepAsync()
    }
}
