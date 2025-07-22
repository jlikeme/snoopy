import Foundation

/// A new sequence manager that generates a sequence of poses and transitions based on AssetClipLoader logic.
class SequenceManager {
    private let allClips: [AnimationClipMetadata]
    private var rng = SystemRandomNumberGenerator()
    private let stateManager: StateManager
    private let sceneManager: SceneManager

    init(stateManager: StateManager, sceneManager: SceneManager, allClips: [AnimationClipMetadata]) {
        self.stateManager = stateManager
        self.sceneManager = sceneManager
        // Load all clips from assets
        self.allClips = allClips
        // Find all base poses
        reset()
    }

    /// Returns the next sequence based on lastClip and its groupType
    func nextStep() {
        // Check if currentClipsQueue is empty
        if stateManager.currentClipsQueue.isEmpty {
            debugLog("[SequenceManagerV2] Current clips queue is empty, starting with a base pose.")
            reset()
        }
        
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
            var transitions = allClips.filter {
                ($0.groupType == .transition && $0.startCharacterBasePoseID == lastClip.poseID)
            }
            if transitions.count > 3 {
                // 增加category clip的支持
                transitions += allClips.filter {
                    $0.clipType == .category && $0.startCharacterBasePoseID == lastClip.poseID
                }
            }
            
            debugLog("[SequenceManagerV2] Last clip is of type .pose, found \(transitions.count) transitions.")
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
                addClipToQueue(next)
                debugLog("[SequenceManagerV2] Next clip added to queue: \(next.poseID) (\(next.clipType))")
                if next.phases.first?.sprites.first?.loopable ?? false {
                    // 从0-5创建随机数
                    let randomLoopCount = Int.random(in: 2...10)
                    // 如果大于4，随机添加一个idleSceneVisitor
                    if randomLoopCount > 8 {
                        // 查找idleSceneVisitor clip
                        let idleClips = allClips.filter {
                            $0.clipType == .idleSceneVisitor
                        }
                        if let idleClip = idleClips.randomElement(using: &rng) {
                            addClipToQueue(idleClip)
                            debugLog("[SequenceManagerV2] Added idleSceneVisitor clip: \(idleClip.poseID) for pose \(next.poseID)")
                        }
                    }
                    
                    for _ in 0..<randomLoopCount {
                        addClipToQueue(next)
                        debugLog("[SequenceManagerV2] Looping clip: \(next.poseID) (\(next.clipType))")
                    }
                }
            }
            
            if next.clipType == .sceneTransitionPose {
                // 查找其对应的所有category clip
                let categoryClips = allClips.filter {
                    // $0.revealCharacterPoseIDs包含next.poseID
                    $0.clipType == .category && $0.transitionCategoryInfo?.revealCharacterPoseIDs.contains(next.assetBaseName) == true
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
                            debugLog("[SequenceManagerV2] Found scene transition pair: \(pair ?? "nil") for category \(categoryClip.poseID)")
                            let pairClip = allClips.first(where: { $0.poseID == pair })
                            revealClip = allClips.first(where: { $0.poseID == pairClip?.revealStyleID })
                            hideClip = allClips.first(where: { $0.poseID == pairClip?.hideStyleID })
                        }
                        
                        if let revealClip = revealClip {
                            addClipToQueue(revealClip)
                            debugLog("[SequenceManagerV2] Added reveal clip: \(revealClip.poseID) for category \(categoryClip.poseID)")
                        }
                        
                        addClipToQueue(sceneClip)
                        debugLog("[SequenceManagerV2] Added active scene clip: \(sceneClip.poseID) for category \(categoryClip.poseID)")
                        
                        if let hideClip = hideClip {
                            addClipToQueue(hideClip)
                            debugLog("[SequenceManagerV2] Added hide clip: \(hideClip.poseID) for category \(categoryClip.poseID)")
                        }

                        // 添加category clip中的hide clip
                        if let hideClips = categoryClip.transitionCategoryInfo?.hideCharacterPoseIDs {
                            for hidePoseID in hideClips {
                                if let hideClip = allClips.first(where: { $0.assetBaseName == hidePoseID }) {
                                    // 添加hide clip到队列
                                    addClipToQueue(hideClip)
                                    debugLog("[SequenceManagerV2] Added hide clip: \(hideClip.poseID) for category \(categoryClip.poseID)")
                                    // 查找后续的transition clips
                                    let transitionClips = allClips.filter {
                                        $0.groupType == .transition && $0.startCharacterBasePoseID == hideClip.poseID
                                    }
                                    if let nextTransitionClip = transitionClips.randomElement(using: &rng) {
                                        addClipToQueue(nextTransitionClip)
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
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            self?.nextStep()
//        }
        self.nextStep()
    }

    /// Resets to a new random base pose
    func reset() {
        let basePoses = allClips.filter { $0.clipType == .basePose }
        guard let randomPose = basePoses.randomElement(using: &rng) else {
            print("[SequenceManagerV2] No base poses found for reset!")
            return
        }
        addClipToQueue(randomPose)
        print("[SequenceManagerV2] Reset to base pose: \(randomPose.poseID)")
        nextStepAsync()
    }
    
    // MARK: - Private Helper Methods
    
    /// 私有方法：将AnimationClipMetadata添加到队列中，使用AnimationClipWithPlayer包装
    private func addClipToQueue(_ clip: AnimationClipMetadata) {
        stateManager.currentClipsQueue.append(clip)
    }
}
