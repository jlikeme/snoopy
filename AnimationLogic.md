# macOS 屏保动画逻辑

## 一、播放层级（从上到下）

1.  **顶层 (AS/SS/抠像层)**:
    *   播放 AS (Application Signature)、SS (Screen Saver) 动画。
    *   使用独立的播放器。
    *   播放 TM\_Mask (Transition Mask) 绿幕抠像转场动画。
        *   TM\_Mask 是一系列HEIC图片组成的动画，带有绿色部分和透明部分。
        *   绿色部分将显示 AS/SS 的内容。
        *   透明部分则透出该层下方的所有内容。
2.  **VI/WE 叠加层**:
    *   位于顶层下方，主播放层之上。
    *   播放 VI (Visual Interruption) 和 WE (Weather Effect) 叠加动画。
3.  **主播放层**:
    *   位于 VI/WE 叠加层下方，静态图片 IS 层之上。
    *   播放 AP (Action Pack), BP (Base Loop), CM (Connector Movie), ST (Short Transition), RPH (Random Placeholder) 动画。
4.  **IS (Interstitial Still) 层**:
    *   位于主播放层下方。
    *   显示静态图片 (HEIC格式)。
5.  **半色调背景图片层**:
    *   位于 IS 层下方。
6.  **底色层**:
    *   位于最底层。

## 二、播放逻辑和时机

### 开始运行后：

#### 1. 初次播放的AS流程

*   **a. 启动与AS播放准备**
    1.  启动屏保时，暂不加载底色、半色调背景和IS层。
    2.  随机选择一个 AS 动画。
    3.  随机选择一个 TM\_Hide 转场动画（这是一系列HEIC图片组成的动画）。
    4.  AS 和 TM\_Hide 被同时加载。
    5.  TM\_Hide 加载后停留在其第一帧。
    6.  AS 开始播放。此时，TM\_Hide 的绿色部分（视觉上）应显示 AS 的内容。
    7.  在当前（首次）AS 播放完毕后，才加载随机的底色、随机的半色调背景图片和随机的 IS 图片。这些背景层是为接下来的 TM\_Hide 转场效果做准备的，它们将显示在 TM\_Hide 的透明区域下方。

*   **b. AS播放完毕，进入TM\_Hide转场**
    1.  （首次）AS 动画播放完毕后，开始播放之前已加载并停在第一帧的 TM\_Hide 动画。
    2.  在 TM\_Hide 播放期间：
        *   其绿色部分（视觉上）继续展示（刚刚播放完毕的）AS 内容（或者可以理解为AS的最后一帧透过TM\_Hide的绿色区域可见，直到TM\_Hide转场完成）。
        *   其透明部分下方则显示先前已加载好的 ST\_Hide 视频以及更底层的背景（IS、半色调、底色）。
    3.  ST\_Hide 视频在此时与 TM\_Hide *同时* 播放。（用户注明：此同步播放功能暂未实现）。
    4.  **ST\_Hide 选择逻辑**:
        *   **与TM匹配**: ST\_Hide 的选择需要和 TM\_Hide 匹配。例如，`101_TM001_Hide_Mask` 对应 `101_ST001_Hide.mov`。
        *   **变种选择**:
            *   如果一个 TM\_Hide 对应的 ST\_Hide 包含多个变种文件（例如 `101_ST001_Hide_A.mov` 和 `101_ST001_Hide_B.mov`），则从这些变种中随机选择一个进行播放。
            *   如果只存在一个变种文件（例如 `101_ST001_Hide_A.mov`），则直接使用该文件。

*   **c. ST\_Hide播放完毕，播放RPH**
    1.  ST\_Hide 视频播放完毕后，随机选择一个 RPH (Random Placeholder) 视频播放。
    2.  RPH 视频的文件名中通常包含 `To` 属性（例如 `101_RPH_To_BP001.mov`），该属性指明了下一个将要播放的 BP (Base Loop) 视频。系统需根据此属性准备好对应的 BP 视频。

*   **d. RPH播放完毕，初始AS流程结束**
    1.  RPH 视频播放完毕后，初次的 AS 流程结束。接下来将进入 BP 流程。

#### 2. BP流程

*   **a. 播放BP并循环**
    1.  播放由上一个 RPH（或 BP\_To, CM, AP\_Outro）指向的 BP 视频。
    2.  此 BP 视频会进行循环播放（循环次数可能预设或随机）。

*   **b. BP循环完毕后的选择**
    1.  BP 循环（达到预定次数或条件）完毕后，系统会根据预设的概率，从以下几种可能性中选择下一段要播放的内容：
        *   **BP\_To (包括 BP\_To\_BP 和 BP\_To\_RPH)**:
            *   随机选择一个 BP\_To 类型的视频播放（例如 `101_BP001_To_BP002.mov` 或 `101_BP001_To_RPH.mov`）。
            *   BP\_To 视频播放完毕后，播放其文件名中 `To` 属性所指向的目标 BP 或 RPH。
        *   **CM (Connector Movie)**:
            *   随机选择一个 `from` 属性与当前 BP 匹配的 CM 视频（例如，若当前为 `BP001`，则可能选择 `101_CM001_From_BP001_To_BP003.mov`）。
            *   CM 视频播放完毕后，播放其文件名中 `to` 属性所指向的目标 BP。
        *   **AP (Action Pack)**:
            *   随机选择一个 `from` 属性与当前 BP 匹配的 AP\_Intro 视频（例如，若当前为 `BP003`，则可能选择 `101_AP001_Intro_From_BP003.mov`）。
            *   播放该 AP\_Intro 视频后，接着播放同组的 AP\_Loop 视频（例如 `101_AP001_Loop.mov`），AP\_Loop 会随机循环若干次数。
            *   AP\_Loop 循环结束后，播放同组的 AP\_Outro 视频（例如 `101_AP001_Outro_To_BP001.mov`）。
            *   AP\_Outro 播放完毕后，播放其文件名中 `to` 属性所指向的目标 BP。
        *   **无特定后续视频**: 如果根据以上规则没有找到明确的下一个视频，则系统会随机选择一个 BP 继续播放。

*   **c. 完整流程计数与跳出决策**
    1.  从一个 BP 开始播放，直到下一个新的 BP 即将开始播放前，这被视为一个“完整流程”。
    2.  每完成一个“完整流程”后，相关的计数器会清零。
    3.  然后，系统会随机决定是继续执行当前的 BP 流程（即回到步骤 2.a 或 2.b），还是跳出当前流程。
    4.  若决定跳出流程，则会再次随机选择进入“完整AS流程”还是“SS流程”。
        *   **若选中“完整AS流程”**:
            1.  首先播放当前 BP 对应的 BP\_To\_RPH 视频。
            2.  然后随机选择一个 ST\_Reveal 视频播放。
            3.  ST\_Reveal 播放完毕后，播放其 group ID 对应的 TM\_Reveal 绿幕转场动画。
                *   TM\_Reveal 的绿色部分将显示即将播放的 AS 内容。
                *   TM\_Reveal 的透明部分则显示其下层的内容（如主播放层、IS层等）。
            4.  随后，新的 AS 动画开始播放。
            5.  与此同时，加载与刚刚播放的 TM\_Reveal *相同 group ID* 的 TM\_Hide 动画，并使其停留在第一帧。
            6.  后续流程与“初次播放的AS流程”（从步骤 1.b 开始）类似：AS 播放完毕后，播放 TM\_Hide（并与 *同 group ID* 的 ST\_Hide 同时播放），然后播放 RPH，最后进入新的 BP 流程。关键区别在于 TM\_Hide 和 ST\_Hide 的选择是基于上一个 Reveal 的 group ID，而非随机。
        *   **若选中“SS流程” (Screen Saver)**:
            1.  首先播放当前 BP 对应的 BP\_To\_RPH 视频。
            2.  随后固定播放 `ST001_Reveal` 。
            3.  `ST001_Reveal` 播放完毕后，播放 `SS001_Intro`。
            4.  `SS001_Intro` 播完之后，播放 `SS001_Loop`（可能循环）。
            5.  `SS001_Loop` 播完后，播放 `SS001_Outro`。
            6.  `SS001_Outro` 播放完毕后，会在其最后一帧保持一会儿。
            7.  然后播放 `TM001_Hide` 与 `ST001_Hide`（可能同时播放，逻辑类似AS流程中的Hide阶段）。
            8.  最后，随机选择一个 RPH 视频，该 RPH 会指向任意一个 BP，从而使流程回到 BP 流程（步骤 2.a）。此跳出SS后的回流机制与跳出AS后的流程相似。

#### 3. 叠加动画 (VI/WE)

*   VI (Visual Interruption) 和 WE (Weather Effect) 动画在主视频层之上、AS/SS抠像层之下播放。
*   VI 和 WE 都包含两种情况：单动画文件和组动画（包含 Intro、Loop、Outro 部分）。
*   VI/WE 的触发是在 BP/AP/CM 的播放和流转过程中，以较低的概率随机发生。

*   **BP 播放时触发 VI/WE**:
    *   **单文件 VI/WE**:
        *   在任意 BP 视频播放期间，或者在从一个视频过渡到 BP（`to BP`）或从 BP 过渡到其他视频（`from BP`）的过程中，都有可能随机播放一个单文件的 VI 或 WE 动画。
    *   **组合 VI/WE**:
        *   **Intro 触发**: 在任何导致播放目标 BP 的转换过程中（例如 RPH to BP, AP\_Outro to BP, BP\_To\_BP to BP, CM to BP），与目标 BP 的开始同步，随机选择并播放一个 VI\_Intro 或 WE\_Intro 动画。
        *   **Loop 播放**: 当 BP 视频处于循环播放状态时，如果之前触发了对应的 VI/WE\_Intro，则接着播放相应的 VI\_Loop 或 WE\_Loop 动画，并随 BP 一同循环。
        *   **Outro 触发**: 当流程需要离开当前正在播放的 BP（例如 BP to RPH, BP to AP\_Intro via BP\_To\_AP, BP to CM via BP\_To\_CM）时，如果当前有 VI/WE\_Loop 正在播放，则会打断该 Loop，并立即播放对应的 VI\_Outro 或 WE\_Outro 动画。

*   **AP 播放时触发 VI/WE**:
    *   **单文件 VI/WE**:
        *   在整个 AP\_Intro、AP\_Loop 和 AP\_Outro 的播放阶段，都有可能随机播放一个单文件的 VI 或 WE 动画。
    *   **组合 VI/WE**:
        *   **Intro 触发**: 当 AP\_Intro 视频开始播放时，同步随机选择并播放一个 VI\_Intro 或 WE\_Intro 动画。
        *   **Loop 播放**: 当 AP\_Loop 视频播放时，如果之前触发了对应的 VI/WE\_Intro，则接着播放相应的 VI\_Loop 或 WE\_Loop 动画，并随 AP\_Loop 一同循环。
        *   **Outro 触发**: 当 AP\_Outro 视频开始播放时，如果当前有 VI/WE\_Loop 正在播放，则会打断该 Loop，并立即播放对应的 VI\_Outro 或 WE\_Outro 动画。

---
所有素材文件均位于项目内的 `./Resources` 文件夹下。
