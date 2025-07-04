import Foundation

/// A new sequence manager that generates a sequence of poses and transitions based on AssetClipLoader logic.
class SequenceManagerV2 {
    private let allClips: [AnimationClipMetadata]
    private var currentPoseID: String?
    private var rng = SystemRandomNumberGenerator()

    init() {
        // Load all clips from assets
        self.allClips = AssetClipLoader.loadAllClips()
        // Find all base poses
        let basePoses = allClips.filter { $0.clipType.groupType == .pose }
        guard let randomPose = basePoses.randomElement(using: &rng) else {
            print("[SequenceManagerV2] No base poses found!")
            return
        }
        self.currentPoseID = randomPose.poseID
        print("[SequenceManagerV2] Initialized with base pose: \(randomPose.poseID)")
    }

    /// Returns the next sequence: (pose, transition, pose, ...)
    func nextStep() -> [AnimationClipMetadata]? {
        guard let currentPoseID = currentPoseID else {
            print("[SequenceManagerV2] No current pose set.")
            return nil
        }
        // Find the current pose clip
        guard let currentPose = allClips.first(where: { $0.clipType.groupType == .pose && $0.poseID == currentPoseID }) else {
            print("[SequenceManagerV2] Current pose not found: \(currentPoseID)")
            return nil
        }
        // Find all transitions starting from this pose
        let transitions = allClips.filter {
            $0.clipType.groupType == .transition && $0.startCharacterBasePoseID == currentPoseID
        }
        guard let transition = transitions.randomElement(using: &rng) else {
            print("[SequenceManagerV2] No transitions found from pose: \(currentPoseID)")
            return nil
        }
        print("[SequenceManagerV2] Picked transition: \(transition.poseID) from pose: \(currentPoseID)")
        // Find the next pose
        guard let nextPoseID = transition.endCharacterBasePoseID else {
            print("[SequenceManagerV2] Transition has no endCharacterBasePoseID: \(transition.poseID)")
            return nil
        }
        
        let nextPoses = allClips.filter {
            $0.clipType.groupType == .pose && $0.poseID == nextPoseID
        }
        guard let nextPose = nextPoses.randomElement(using: &rng) else {
            print("[SequenceManagerV2] Next pose not found: \(nextPoseID)")
            return nil
        }
        print("[SequenceManagerV2] Next pose: \(nextPose.poseID)")
        // Update current pose
        self.currentPoseID = nextPoseID

        if currentPose.clipType == .reactionPose {
            return [transition, nextPose]
        } else {
            return [currentPose, transition, nextPose]
        }
    }

    /// Resets to a new random base pose
    func reset() {
        let basePoses = allClips.filter { $0.clipType.groupType == .pose }
        guard let randomPose = basePoses.randomElement(using: &rng) else {
            print("[SequenceManagerV2] No base poses found for reset!")
            return
        }
        self.currentPoseID = randomPose.poseID
        print("[SequenceManagerV2] Reset to base pose: \(randomPose.poseID)")
    }
} 
