//
//  SequenceManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import Foundation

// MARK: - Array Safe Access Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

class SequenceManager {
    private weak var stateManager: StateManager?

    init(stateManager: StateManager) {
        self.stateManager = stateManager
    }

    func generateNextSequence(basedOn finishedClip: SnoopyClip) {
        guard let stateManager = stateManager else { return }
        debugLog(
            "📊 基于完成的片段生成下一个序列: \(finishedClip.fileName) (类型: \(finishedClip.type), 状态: \(stateManager.currentStateType))"
        )
        var nextQueue: [SnoopyClip] = []

        switch finishedClip.type {
        case SnoopyClip.ClipType.AS:
            debugLog("🎬 AS 完成。队列 Halftone 过渡。")

            let requiredNumber = stateManager.lastTransitionNumber
            debugLog("🔍 Debug: lastTransitionNumber = \(requiredNumber ?? "nil")")

            guard
                let tmHide = findRandomClip(
                    ofType: SnoopyClip.ClipType.TM_Hide, matchingNumber: requiredNumber)
            else {
                debugLog("❌ Guard Failed: 找不到编号为 \(requiredNumber ?? "any") 的 TM_Hide")
                // Don't reset lastTransitionNumber here, keep it for potential retry
                break
            }

            // Only reset lastTransitionNumber after successful finding of TM_Hide
            stateManager.lastTransitionNumber = nil
            debugLog("✅ Guard OK: Found TM_Hide: \(tmHide.fileName)")

            guard let stHide = findMatchingST(for: tmHide, type: SnoopyClip.ClipType.ST_Hide) else {
                debugLog("❌ Guard Failed: 找不到匹配 TM \(tmHide.number ?? "") 的 ST_Hide")
                break
            }
            debugLog("✅ Guard OK: Found ST_Hide: \(stHide.fileName)")

            guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
                debugLog("❌ Guard Failed: 找不到随机 RPH")
                break
            }
            debugLog("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

            guard
                let targetBPNode = findClip(
                    ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
            else {
                debugLog(
                    "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")"
                )
                break
            }
            debugLog("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

            // 检查是否已经存储了nextAfterAS，如果存储了就使用它
            if !stateManager.nextAfterAS.isEmpty {
                debugLog(
                    "🎬 AS完成，使用已存储的后续片段: \(stateManager.nextAfterAS.map { $0.fileName }.joined(separator: ", "))"
                )
                nextQueue = stateManager.nextAfterAS
                stateManager.nextAfterAS = []  // 清空存储，防止重复使用
            } else {
                // 🎬 修复：如果没有存储，生成序列时跳过TM_Hide和ST_Hide
                // TM_Hide通过直接调用处理，ST_Hide通过同步播放处理
                nextQueue = [randomRPH, targetBPNode]
                debugLog("🎬 AS完成，使用新生成的后续片段（TM_Hide和ST_Hide通过其他机制处理）")
            }

        case SnoopyClip.ClipType.BP_Node:
            debugLog(
                "🎬 BP 节点完成循环。当前节点: \(stateManager.currentNode ?? "nil"), 周期计数: \(stateManager.bpCycleCount)"
            )
            stateManager.currentStateType = .decidingNextHalftoneAction

            if stateManager.bpCycleCount >= 5 {
                debugLog("🔄 已完成 \(stateManager.bpCycleCount) 个 BP 周期，随机选择 AS, SS 或 Halftone 序列。")
                stateManager.bpCycleCount = 0

                let choice = Double.random(in: 0..<1)
                let asProbability = 0.4
                let ssProbability = 0.08

                if choice < asProbability {
                    debugLog("  选择生成 AS 序列。")
                    // 特殊处理：BP001有概率进入AS序列（使用固定006编号）
                    if stateManager.currentNode == "BP001" {
                        debugLog("🎯 BP001选择进入AS序列（使用固定006编号）")
                        nextQueue = generateBP001ASSequence()
                    } else {
                        nextQueue = generateASSequence(fromNode: stateManager.currentNode)
                    }
                } else if choice < asProbability + ssProbability {
                    debugLog("  选择生成 SS 序列。")
                    stateManager.isPlayingSS = true  // 标记进入SS流程
                    nextQueue = generateSSSequenceNew(fromNode: stateManager.currentNode)
                } else {
                    debugLog("  选择生成 Halftone 转换序列 (继续)。")
                    guard let nodeName = stateManager.currentNode else {
                        debugLog("❌ 错误：BP_Node 完成时 currentNode 为 nil。回退。")
                        nextQueue = generateFallbackSequence()
                        break
                    }
                    let nextSequenceFileNames = SnoopyClip.generatePlaySequence(
                        currentNode: nodeName, clips: stateManager.allClips)
                    nextQueue = nextSequenceFileNames.compactMap { findClip(byFileName: $0) }
                    if nextQueue.isEmpty {
                        debugLog("⚠️ 未找到合适的 AP/CM/BP_To 转换。回退。")
                        nextQueue = generateFallbackSequence()
                    }
                }
            } else {
                debugLog("  周期数未达 5 的倍数 (当前: \(stateManager.bpCycleCount))，选择下一个 Halftone 动作。")

                guard let nodeName = stateManager.currentNode else {
                    debugLog("❌ 错误：BP_Node 完成时 currentNode 为 nil。回退。")
                    nextQueue = generateFallbackSequence()
                    break
                }
                let nextSequenceFileNames = SnoopyClip.generatePlaySequence(
                    currentNode: nodeName, clips: stateManager.allClips)
                nextQueue = nextSequenceFileNames.compactMap { findClip(byFileName: $0) }
                if nextQueue.isEmpty {
                    debugLog("⚠️ 未找到合适的 AP/CM/BP_To 转换。回退。")
                    nextQueue = generateFallbackSequence()
                }
            }

        case SnoopyClip.ClipType.AP_Outro, SnoopyClip.ClipType.CM, SnoopyClip.ClipType.BP_To,
            SnoopyClip.ClipType.RPH:
            debugLog("🎬 \(finishedClip.type) 完成。转到节点: \(finishedClip.to ?? "nil")")

            if finishedClip.type == SnoopyClip.ClipType.RPH {
                // RPH完成，整个AS/SS → TM_Hide → ST_Hide → RPH序列结束，重置转场编号
                debugLog("🔄 RPH完成，重置AS/SS转场编号")
                stateManager.lastTransitionNumber = nil
                stateManager.ssTransitionNumber = nil
                stateManager.isPlayingSS = false

                // 检查RPH是否在预构建的序列中（下一个应该是BP_Node）
                if let nextClipInQueue = stateManager.currentClipsQueue[
                    safe: stateManager.currentClipIndex + 1],
                    nextClipInQueue.type == SnoopyClip.ClipType.BP_Node
                {
                    debugLog(
                        "🎬 RPH (part of sequence) 完成。继续序列到 BP_Node: \(nextClipInQueue.fileName)")
                    // 更新当前节点
                    stateManager.currentNode = finishedClip.to
                    return
                } else {
                    // RPH不在预构建的序列中，需要生成新的BP_Node队列
                    stateManager.currentNode = finishedClip.to
                    guard
                        let targetBPNode = findClip(
                            ofType: SnoopyClip.ClipType.BP_Node, nodeName: stateManager.currentNode)
                    else {
                        debugLog("❌ 错误：找不到目标 BP 节点 \(stateManager.currentNode ?? "nil")。回退。")
                        nextQueue = generateFallbackSequence()
                        break
                    }
                    debugLog("✅ RPH 完成，队列目标 BP 节点: \(targetBPNode.fileName)")
                    nextQueue = [targetBPNode]
                    stateManager.bpCycleCount += 1
                    debugLog("🔄 增加 BP 周期计数至: \(stateManager.bpCycleCount)")
                }
            } else if finishedClip.type == SnoopyClip.ClipType.BP_To {
                if finishedClip.to?.starts(with: "RPH") ?? false {
                    if let nextClipInQueue = stateManager.currentClipsQueue[
                        safe: stateManager.currentClipIndex + 1],
                        nextClipInQueue.type == SnoopyClip.ClipType.ST_Reveal
                    {
                        debugLog("🎬 BP_To_RPH (part of AS sequence) 完成。继续序列 (ST_Reveal)。")

                        // 清除所有存储的跳转后序列，防止循环
                        if !stateManager.nextAfterAS.isEmpty || !stateManager.nextAfterSS.isEmpty {
                            debugLog("⚠️ BP_To_RPH序列开始，清除已存储的nextAfterAS/nextAfterSS防止循环")
                            stateManager.nextAfterAS = []
                            stateManager.nextAfterSS = []
                        }
                        return
                    } else {
                        guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
                            debugLog("❌ 错误：找不到任何 RPH 片段来处理 BP_To_RPH 完成。回退。")
                            nextQueue = generateFallbackSequence()
                            break
                        }
                        debugLog("✅ BP_To_RPH 完成，队列随机 RPH: \(randomRPH.fileName)")
                        nextQueue = [randomRPH]
                    }
                } else {
                    stateManager.currentNode = finishedClip.to
                    guard
                        let targetBPNode = findClip(
                            ofType: SnoopyClip.ClipType.BP_Node, nodeName: stateManager.currentNode)
                    else {
                        debugLog("❌ 错误：找不到目标 BP 节点 \(stateManager.currentNode ?? "nil")。回退。")
                        nextQueue = generateFallbackSequence()
                        break
                    }
                    debugLog("✅ BP_To_BP 完成，队列目标 BP 节点: \(targetBPNode.fileName)")
                    nextQueue = [targetBPNode]
                    stateManager.bpCycleCount += 1
                    debugLog("🔄 增加 BP 周期计数至: \(stateManager.bpCycleCount)")
                }
            } else {
                // 处理其他类型(.AP_Outro, .CM)
                stateManager.currentNode = finishedClip.to
                guard
                    let targetBPNode = findClip(
                        ofType: SnoopyClip.ClipType.BP_Node, nodeName: stateManager.currentNode)
                else {
                    debugLog("❌ 错误：找不到目标 BP 节点 \(stateManager.currentNode ?? "nil")。回退。")
                    nextQueue = generateFallbackSequence()
                    break
                }
                debugLog("✅ \(finishedClip.type) 完成，队列目标 BP 节点: \(targetBPNode.fileName)")
                nextQueue = [targetBPNode]
                stateManager.bpCycleCount += 1
                debugLog("🔄 增加 BP 周期计数至: \(stateManager.bpCycleCount)")
            }

        case SnoopyClip.ClipType.ST_Hide, SnoopyClip.ClipType.ST_Reveal:
            debugLog("🎬 \(finishedClip.type) 完成。继续序列。")
            return

        case SnoopyClip.ClipType.TM_Hide:
            debugLog("🎬 TM_Hide 完成。生成 ST_Hide → RPH → BP_Node 序列。")

            guard let transitionNumber = finishedClip.number else {
                debugLog("❌ Guard Failed: TM_Hide 没有有效的转场编号")
                break
            }

            guard
                let stHide = findMatchingST(
                    forNumber: transitionNumber, type: SnoopyClip.ClipType.ST_Hide)
            else {
                debugLog("❌ Guard Failed: 找不到匹配 TM \(transitionNumber) 的 ST_Hide")
                break
            }
            debugLog("✅ Guard OK: Found ST_Hide: \(stHide.fileName)")

            guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
                debugLog("❌ Guard Failed: 找不到随机 RPH")
                break
            }
            debugLog("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

            guard
                let targetBPNode = findClip(
                    ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
            else {
                debugLog(
                    "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")"
                )
                break
            }
            debugLog("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

            // 🎬 修复：ST_Hide通过同步播放处理，不应在队列中
            // 注意：这个分支理论上不应该被调用，因为TM_Hide通过heicSequenceMaskCompleted处理
            nextQueue = [randomRPH, targetBPNode]
            debugLog(
                "🎬 TM_Hide完成（意外路径），跳过ST_Hide，序列: \(nextQueue.map { $0.fileName }.joined(separator: ", "))"
            )

        case SnoopyClip.ClipType.TM_Reveal:
            debugLog("❌ 错误：TM 片段在主播放器序列生成中完成。")
            break

        case SnoopyClip.ClipType.SS_Outro:
            debugLog("🎬 SS 完成。队列 Halftone 过渡。")

            let requiredNumber = stateManager.lastTransitionNumber
            debugLog("🔍 Debug: lastTransitionNumber = \(requiredNumber ?? "nil")")

            guard
                let tmHide = findRandomClip(
                    ofType: SnoopyClip.ClipType.TM_Hide, matchingNumber: requiredNumber)
            else {
                debugLog("❌ Guard Failed: 找不到编号为 \(requiredNumber ?? "any") 的 TM_Hide")
                // Don't reset lastTransitionNumber here, keep it for potential retry
                break
            }

            // Only reset lastTransitionNumber after successful finding of TM_Hide
            stateManager.lastTransitionNumber = nil
            debugLog("✅ Guard OK: Found TM_Hide: \(tmHide.fileName)")

            guard let stHide = findMatchingST(for: tmHide, type: SnoopyClip.ClipType.ST_Hide) else {
                debugLog("❌ Guard Failed: 找不到匹配 TM \(tmHide.number ?? "") 的 ST_Hide")
                break
            }
            debugLog("✅ Guard OK: Found ST_Hide: \(stHide.fileName)")

            guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
                debugLog("❌ Guard Failed: 找不到随机 RPH")
                break
            }
            debugLog("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

            guard
                let targetBPNode = findClip(
                    ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
            else {
                debugLog(
                    "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")"
                )
                break
            }
            debugLog("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

            // 检查是否已经存储了nextAfterAS，如果存储了就使用它
            if !stateManager.nextAfterAS.isEmpty {
                debugLog(
                    "🎬 SS完成，使用已存储的后续片段: \(stateManager.nextAfterAS.map { $0.fileName }.joined(separator: ", "))"
                )
                nextQueue = stateManager.nextAfterAS
                stateManager.nextAfterAS = []  // 清空存储，防止重复使用
            } else {
                // 🎬 修复：如果没有存储，生成序列时跳过TM_Hide和ST_Hide
                // TM_Hide通过直接调用处理，ST_Hide通过同步播放处理
                nextQueue = [randomRPH, targetBPNode]
                debugLog("🎬 SS完成，使用新生成的后续片段（TM_Hide和ST_Hide通过其他机制处理）")
            }

        case SnoopyClip.ClipType.SS_Intro, SnoopyClip.ClipType.SS_Loop,
            SnoopyClip.ClipType.AP_Intro, SnoopyClip.ClipType.AP_Loop:
            debugLog("🎬 \(finishedClip.type) 完成。继续序列。")
            return

        default:
            debugLog("⚠️ 未处理的片段类型完成: \(finishedClip.type)。使用随机 AS 重新开始。")
            nextQueue = generateFallbackSequence()
            stateManager.bpCycleCount = 0
        }

        if !nextQueue.isEmpty {
            debugLog("✅ 生成新队列，包含 \(nextQueue.count) 个片段。")
            stateManager.currentClipsQueue = nextQueue
            stateManager.currentClipIndex = -1
        } else if finishedClip.type != SnoopyClip.ClipType.ST_Hide
            && finishedClip.type != SnoopyClip.ClipType.ST_Reveal
            && finishedClip.type != SnoopyClip.ClipType.RPH
            && finishedClip.type != SnoopyClip.ClipType.SS_Outro
            && finishedClip.type != SnoopyClip.ClipType.SS_Intro
            && finishedClip.type != SnoopyClip.ClipType.SS_Loop
            && finishedClip.type != SnoopyClip.ClipType.AP_Intro
            && finishedClip.type != SnoopyClip.ClipType.AP_Loop
        {
            debugLog(
                "❌ 无法为 \(finishedClip.fileName) 生成下一个序列。处理队列结束。"
            )
            handleEndOfQueue()
        }
    }

    func handleEndOfQueue() {
        guard let stateManager = stateManager else { return }
        debugLog(
            "❌ 意外到达队列末尾或序列生成失败。回退到随机 BP_Node。"
        )
        // Note: These player operations should be handled by PlayerManager
        let fallbackQueue = generateFallbackSequence()
        if !fallbackQueue.isEmpty {
            stateManager.currentClipsQueue = fallbackQueue
            stateManager.currentClipIndex = 0
            // Note: playNextClipInQueue should be called by the coordinator
        } else {
            debugLog("❌ 严重错误：无法生成回退队列！停止播放。")
        }
    }

    func generateASSequence(fromNode: String? = nil) -> [SnoopyClip] {
        guard let stateManager = stateManager else { return [] }
        var sequence: [SnoopyClip] = []
        var transitionNumber: String? = nil

        if let nodeName = fromNode {
            let bpToRphCandidates = stateManager.allClips.filter { clip in
                guard clip.type == SnoopyClip.ClipType.BP_To, clip.to?.starts(with: "RPH") ?? false
                else {
                    return false
                }
                let pattern = "_BP\(nodeName.suffix(3))_To_"
                return clip.fileName.contains(pattern)
            }

            if let bpToRph = bpToRphCandidates.randomElement() {
                debugLog("  Prepending BP_To_RPH: \(bpToRph.fileName) to AS sequence.")
                sequence.append(bpToRph)
            } else {
                debugLog(
                    "⚠️ Warning: Could not find BP_To_RPH for node \(nodeName) to prepend to AS sequence."
                )
            }
        }

        guard let randomTMReveal = findRandomClip(ofType: SnoopyClip.ClipType.TM_Reveal) else {
            debugLog("❌ Error: Could not find random TM_Reveal for AS sequence.")
            return generateFallbackSequence()
        }
        transitionNumber = randomTMReveal.number
        debugLog(
            "  Selected TM_Reveal: \(randomTMReveal.fileName) (Number: \(transitionNumber ?? "nil"))"
        )

        guard
            let matchingSTReveal = findMatchingST(
                for: randomTMReveal, type: SnoopyClip.ClipType.ST_Reveal)
        else {
            debugLog(
                "❌ Error: Could not find matching ST_Reveal for TM number \(transitionNumber ?? "nil")."
            )
            return generateFallbackSequence()
        }
        debugLog("  Selected ST_Reveal: \(matchingSTReveal.fileName)")

        guard let randomAS = findRandomClip(ofType: SnoopyClip.ClipType.AS) else {
            debugLog("❌ Error: Could not find random AS clip.")
            return generateFallbackSequence()
        }
        debugLog("  Selected AS: \(randomAS.fileName)")

        // 在此存储转场编号，以便AS播放完成后可以找到匹配的TM_Hide
        stateManager.lastTransitionNumber = transitionNumber
        debugLog("💾 Stored lastTransitionNumber: \(stateManager.lastTransitionNumber ?? "nil")")

        // 找到匹配的TM_Hide，但不加入序列 - 这将在AS播放完成时使用
        guard
            let tmHide = findRandomClip(
                ofType: SnoopyClip.ClipType.TM_Hide, matchingNumber: transitionNumber)
        else {
            debugLog("❌ Guard Failed: 找不到编号为 \(transitionNumber ?? "any") 的 TM_Hide")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found TM_Hide: \(tmHide.fileName) - 将在AS完成后使用")

        guard let stHide = findMatchingST(for: tmHide, type: SnoopyClip.ClipType.ST_Hide) else {
            debugLog("❌ Guard Failed: 找不到匹配 TM \(tmHide.number ?? "") 的 ST_Hide")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found ST_Hide: \(stHide.fileName) - 将在TM_Hide完成后使用")

        guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
            debugLog("❌ Guard Failed: 找不到随机 RPH")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

        guard
            let targetBPNode = findClip(ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
        else {
            debugLog(
                "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

        // 关键修改: 序列中只包含ST_Reveal, TM_Reveal和AS
        // 其他部分(TM_Hide, ST_Hide, RPH, BP_Node)将在AS播放完成后单独处理
        sequence += [matchingSTReveal, randomTMReveal, randomAS]

        // 🎬 修复重复播放问题：nextAfterAS中不包含TM_Hide和ST_Hide
        // TM_Hide通过直接调用startTMHideTransition处理，ST_Hide通过同步播放处理
        // 为后续使用存储需要播放的部分（只包含RPH -> BP_Node）
        stateManager.nextAfterAS = [randomRPH, targetBPNode]

        debugLog(
            "✅ Generated AS sequence with \(sequence.count) clips. Stored \(stateManager.nextAfterAS.count) clips for after AS (TM_Hide and ST_Hide excluded - handled separately)."
        )
        return sequence
    }

    func generateBP001ASSequence() -> [SnoopyClip] {
        guard let stateManager = stateManager else { return [] }
        var sequence: [SnoopyClip] = []
        let fixedTransitionNumber: String = "006"  // 固定使用006编号

        debugLog("🎯 生成BP001专用AS序列，使用固定转场编号: \(fixedTransitionNumber)")

        // 找到编号为006的TM_Reveal
        guard
            let tmReveal006 = findRandomClip(
                ofType: SnoopyClip.ClipType.TM_Reveal, matchingNumber: fixedTransitionNumber)
        else {
            debugLog("❌ Error: 找不到编号为006的TM_Reveal")
            return generateFallbackSequence()
        }
        debugLog("✅ 找到TM_Reveal: \(tmReveal006.fileName)")

        // 随机选择AS片段
        guard let randomAS = findRandomClip(ofType: SnoopyClip.ClipType.AS) else {
            debugLog("❌ Error: 找不到AS片段")
            return generateFallbackSequence()
        }
        debugLog("✅ 找到AS: \(randomAS.fileName)")

        // 存储转场编号，用于AS播放完成后找到匹配的TM_Hide
        stateManager.lastTransitionNumber = fixedTransitionNumber
        debugLog("💾 存储转场编号: \(stateManager.lastTransitionNumber ?? "nil")")

        // 找到编号为006的TM_Hide
        guard
            let tmHide006 = findRandomClip(
                ofType: SnoopyClip.ClipType.TM_Hide, matchingNumber: fixedTransitionNumber)
        else {
            debugLog("❌ Error: 找不到编号为006的TM_Hide")
            return generateFallbackSequence()
        }
        debugLog("✅ 找到TM_Hide: \(tmHide006.fileName)")

        // 找到匹配的ST_Hide (A或B变体)
        guard let stHide = findMatchingST(for: tmHide006, type: SnoopyClip.ClipType.ST_Hide) else {
            debugLog("❌ Error: 找不到匹配006编号的ST_Hide")
            return generateFallbackSequence()
        }
        debugLog("✅ 找到ST_Hide: \(stHide.fileName) (变体: \(stHide.variant ?? "default"))")

        // 随机选择RPH
        guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
            debugLog("❌ Error: 找不到RPH片段")
            return generateFallbackSequence()
        }
        debugLog("✅ 找到RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

        // 找到目标BP节点
        guard
            let targetBPNode = findClip(ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
        else {
            debugLog("❌ Error: 找不到RPH指向的BP节点 \(randomRPH.to ?? "nil")")
            return generateFallbackSequence()
        }
        debugLog("✅ 找到目标BP节点: \(targetBPNode.fileName)")

        // 构建序列 TM_Reveal -> AS
        sequence = [tmReveal006, randomAS]

        // 🎬 修复BP001重复播放问题：nextAfterAS中不包含TM_Hide和ST_Hide
        // TM_Hide通过直接调用startTMHideTransition处理，ST_Hide通过同步播放处理
        // 存储后续片段：只包含 RPH -> BP_Node
        stateManager.nextAfterAS = [randomRPH, targetBPNode]

        debugLog(
            "🎯 BP001 AS序列生成完成: \(sequence.count)个片段，后续\(stateManager.nextAfterAS.count)个片段（已跳过TM_Hide和ST_Hide）"
        )
        debugLog("  序列: \(sequence.map { $0.fileName }.joined(separator: " -> "))")
        debugLog("  后续: \(stateManager.nextAfterAS.map { $0.fileName }.joined(separator: " -> "))")
        debugLog(
            "  注意: TM_Hide (\(tmHide006.fileName)) 通过直接调用处理，ST_Hide (\(stHide.fileName)) 通过同步播放处理")

        return sequence
    }

    func generateSSSequenceNew(fromNode: String? = nil) -> [SnoopyClip] {
        guard let stateManager = stateManager else { return [] }
        var sequence: [SnoopyClip] = []
        let transitionNumber: String = "001"  // SS流程固定使用001编号

        debugLog("🎬 生成SS序列，固定使用转场编号: \(transitionNumber)")

        if let nodeName = fromNode {
            let bpToRphCandidates = stateManager.allClips.filter { clip in
                guard clip.type == SnoopyClip.ClipType.BP_To, clip.to?.starts(with: "RPH") ?? false
                else {
                    return false
                }

                let pattern = "_BP\(nodeName.suffix(3))_To_"
                return clip.fileName.contains(pattern)
            }

            if let bpToRph = bpToRphCandidates.randomElement() {
                debugLog("  Prepending BP_To_RPH: \(bpToRph.fileName) to SS sequence.")
                sequence.append(bpToRph)
            } else {
                debugLog(
                    "⚠️ Warning: Could not find BP_To_RPH for node \(nodeName) to prepend to SS sequence."
                )
            }
        }

        // 固定找到编号为001的ST_Reveal
        guard
            let stReveal001 = findMatchingST(
                forNumber: transitionNumber, type: SnoopyClip.ClipType.ST_Reveal)
        else {
            debugLog(
                "❌ Error: Could not find ST001_Reveal for SS sequence."
            )
            return generateFallbackSequence()
        }
        debugLog("  Selected ST_Reveal: \(stReveal001.fileName)")

        // 找到SS序列的三部分：Intro, Loop, Outro
        guard let ssIntro = findRandomClip(ofType: SnoopyClip.ClipType.SS_Intro) else {
            debugLog("❌ Error: Could not find random ssIntro.")
            return generateFallbackSequence()
        }
        debugLog("  Selected ssIntro: \(ssIntro.fileName)")

        guard let ssLoop = findRandomClip(ofType: SnoopyClip.ClipType.SS_Loop) else {
            debugLog("❌ Error: Could not find random ssLoop.")
            return generateFallbackSequence()
        }
        debugLog("  Selected ssLoop: \(ssLoop.fileName)")

        guard let ssOutro = findRandomClip(ofType: SnoopyClip.ClipType.SS_Outro) else {
            debugLog("❌ Error: Could not find random ssOutro.")
            return generateFallbackSequence()
        }
        debugLog("  Selected ssOutro: \(ssOutro.fileName)")

        // 存储SS专用编号，用于找到匹配的TM_Hide
        stateManager.ssTransitionNumber = transitionNumber
        debugLog("💾 Stored ssTransitionNumber: \(stateManager.ssTransitionNumber ?? "nil")")

        debugLog("🎬 SS 序列生成。规划SS完成后的Halftone过渡。")

        // SS流程：TM_Hide可以随机使用，但ST_Hide固定使用001编号
        guard let randomTMHide = findRandomClip(ofType: SnoopyClip.ClipType.TM_Hide) else {
            debugLog("❌ Guard Failed: 找不到随机 TM_Hide")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found random TM_Hide: \(randomTMHide.fileName) - 将在SS完成后使用")

        // ST_Hide固定使用001编号
        guard let stHide001 = findMatchingST(forNumber: "001", type: SnoopyClip.ClipType.ST_Hide)
        else {
            debugLog("❌ Guard Failed: 找不到编号为001的 ST_Hide")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found ST_Hide: \(stHide001.fileName) - 将在TM_Hide完成后使用")

        guard let randomRPH = findRandomClip(ofType: SnoopyClip.ClipType.RPH) else {
            debugLog("❌ Guard Failed: 找不到随机 RPH")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

        guard
            let targetBPNode = findClip(ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
        else {
            debugLog(
                "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")")
            return generateFallbackSequence()
        }
        debugLog("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

        // 当前序列只包括ST_Reveal和SS三部分
        sequence += [stReveal001, ssIntro, ssLoop, ssOutro]

        // 🎬 修复重复播放问题：nextAfterSS中不包含TM_Hide和ST_Hide
        // TM_Hide通过直接调用startTMHideTransition处理，ST_Hide通过同步播放处理
        // 为后续使用存储需要播放的部分（只包含RPH -> BP_Node） - 这将在SS_Outro播放完成后的延迟结束时使用
        stateManager.nextAfterSS = [randomRPH, targetBPNode]

        debugLog(
            "✅ Generated SS sequence with \(sequence.count) clips. Stored \(stateManager.nextAfterSS.count) clips for after SS_Outro (TM_Hide and ST_Hide excluded - handled separately)."
        )
        return sequence
    }

    func generateFallbackSequence() -> [SnoopyClip] {
        guard let stateManager = stateManager else { return [] }
        debugLog("🚨 生成回退序列：随机选择 BP 节点")

        let bpClips = stateManager.allClips.filter { $0.type == SnoopyClip.ClipType.BP_Node }
        guard let randomBPNode = bpClips.randomElement() else {
            debugLog("❌ Error: 找不到任何 BP_Node 进行回退")
            return []
        }

        // 重置状态
        stateManager.bpCycleCount = 0
        stateManager.lastTransitionNumber = nil
        stateManager.ssTransitionNumber = nil
        stateManager.isPlayingSS = false  // 重置SS标志
        stateManager.currentNode = randomBPNode.node
        debugLog("  回退到: \(randomBPNode.fileName)")
        return [randomBPNode]
    }

    func findClip(byFileName fileName: String) -> SnoopyClip? {
        return stateManager?.allClips.first { $0.fileName == fileName }
    }

    func findClip(ofType type: SnoopyClip.ClipType, nodeName: String? = nil, groupID: String? = nil)
        -> SnoopyClip?
    {
        return stateManager?.allClips.first { clip in
            var match = clip.type == type
            if let targetNodeName = nodeName {
                match =
                    match
                    && (clip.node == targetNodeName || clip.from == targetNodeName
                        || clip.to == targetNodeName)
            }
            if let group = groupID {
                match = match && clip.groupID == group
            }
            return match
        }
    }

    func findRandomClip(ofType type: SnoopyClip.ClipType, matchingNumber: String? = nil)
        -> SnoopyClip?
    {
        guard let stateManager = stateManager else { return nil }
        let candidates = stateManager.allClips.filter { $0.type == type }

        // Add debugging for TM clips
        if type == SnoopyClip.ClipType.TM_Hide || type == SnoopyClip.ClipType.TM_Reveal {
            debugLog("🔍 Debug TM clips:")
            for clip in candidates {
                debugLog("  - \(clip.fileName) (number: \(clip.number ?? "nil"))")
            }
        }

        if let number = matchingNumber {
            let filteredByNumber = candidates.filter { $0.number == number }
            if !filteredByNumber.isEmpty {
                debugLog("🔍 找到匹配编号 \(number) 的 \(type) 片段。")
                return filteredByNumber.randomElement()
            } else {
                debugLog("⚠️ 警告: 未找到编号为 \(number) 的 \(type) 片段，将随机选择。")
                debugLog(
                    "🔍 Available candidates: \(candidates.map { "\($0.fileName)(num:\($0.number ?? "nil"))" })"
                )

                // 对于TM类型，随机选择时排除006编号
                if type == SnoopyClip.ClipType.TM_Hide || type == SnoopyClip.ClipType.TM_Reveal {
                    let filteredCandidates = candidates.filter { $0.number != "006" }
                    if !filteredCandidates.isEmpty {
                        debugLog("🔍 排除006编号后，从 \(filteredCandidates.count) 个候选中随机选择")
                        return filteredCandidates.randomElement()
                    } else {
                        debugLog("⚠️ 排除006后没有可用的TM片段，使用原始候选")
                        return candidates.randomElement()
                    }
                } else {
                    return candidates.randomElement()
                }
            }
        } else {
            // 对于TM类型，随机选择时排除006编号
            if type == SnoopyClip.ClipType.TM_Hide || type == SnoopyClip.ClipType.TM_Reveal {
                let filteredCandidates = candidates.filter { $0.number != "006" }
                if !filteredCandidates.isEmpty {
                    debugLog("🔍 排除006编号后，从 \(filteredCandidates.count) 个TM候选中随机选择")
                    return filteredCandidates.randomElement()
                } else {
                    debugLog("⚠️ 排除006后没有可用的TM片段，使用原始候选")
                    return candidates.randomElement()
                }
            } else {
                return candidates.randomElement()
            }
        }
    }

    func findMatchingST(
        for tmClip: SnoopyClip? = nil, forNumber number: String? = nil, type: SnoopyClip.ClipType
    ) -> SnoopyClip? {
        guard let stateManager = stateManager else { return nil }
        guard type == SnoopyClip.ClipType.ST_Hide || type == SnoopyClip.ClipType.ST_Reveal else {
            return nil
        }
        let targetNumber = tmClip?.number ?? number
        guard let num = targetNumber else { return nil }

        let matchingSTs = stateManager.allClips.filter { $0.type == type && $0.number == num }

        if matchingSTs.isEmpty {
            debugLog("⚠️ 警告：未找到匹配的 \(type) 片段，编号为 \(num)")
            return nil
        }

        let variants = matchingSTs.filter { $0.variant != nil }
        if !variants.isEmpty {
            return variants.randomElement()
        } else {
            return matchingSTs.first
        }
    }
}
