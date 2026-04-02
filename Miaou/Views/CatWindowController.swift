import Cocoa

/// A window that never steals focus from other apps
class NonActivatingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Speech Bubble View

/// Custom view that draws a cartoon speech bubble with a tail pointing down
class SpeechBubbleView: NSView {
    static let headerHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 14
    static let tailHeight: CGFloat = 12
    static let tailWidth: CGFloat = 20
    static let borderColor = NSColor(red: 1.0, green: 0.42, blue: 0.17, alpha: 0.4)
    static let headerColor = NSColor(red: 1.0, green: 0.42, blue: 0.17, alpha: 0.10)
    static let bodyColor = NSColor(red: 1.0, green: 0.97, blue: 0.94, alpha: 1.0) // #FFF8F0
    static let accentColor = NSColor(red: 1.0, green: 0.42, blue: 0.17, alpha: 1.0) // #FF6B2B

    var headerLabel: NSTextField!
    var closeButton: NSButton!
    var textView: NSTextView!
    var scrollView: NSScrollView!
    var onClose: (() -> Void)?
    var onClick: (() -> Void)?

    /// The body rect (above the tail)
    private var bodyRect: NSRect {
        NSRect(x: 0, y: Self.tailHeight, width: bounds.width, height: bounds.height - Self.tailHeight)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    /// Build the full bubble path: rounded rect + triangle tail
    private func bubblePath() -> NSBezierPath {
        let rect = bodyRect
        let r = Self.cornerRadius
        let path = NSBezierPath()

        // Start at top-left after corner
        path.move(to: NSPoint(x: rect.minX + r, y: rect.maxY))

        // Top edge → top-right corner
        path.line(to: NSPoint(x: rect.maxX - r, y: rect.maxY))
        path.curve(to: NSPoint(x: rect.maxX, y: rect.maxY - r),
                    controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY),
                    controlPoint2: NSPoint(x: rect.maxX, y: rect.maxY))

        // Right edge → bottom-right corner
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
        path.curve(to: NSPoint(x: rect.maxX - r, y: rect.minY),
                    controlPoint1: NSPoint(x: rect.maxX, y: rect.minY),
                    controlPoint2: NSPoint(x: rect.maxX, y: rect.minY))

        // Bottom edge → tail
        let tailCenterX = rect.midX
        let tailHalf = Self.tailWidth / 2
        path.line(to: NSPoint(x: tailCenterX + tailHalf, y: rect.minY))

        // Tail triangle (points down)
        path.line(to: NSPoint(x: tailCenterX, y: 0))
        path.line(to: NSPoint(x: tailCenterX - tailHalf, y: rect.minY))

        // Continue bottom edge → bottom-left corner
        path.line(to: NSPoint(x: rect.minX + r, y: rect.minY))
        path.curve(to: NSPoint(x: rect.minX, y: rect.minY + r),
                    controlPoint1: NSPoint(x: rect.minX, y: rect.minY),
                    controlPoint2: NSPoint(x: rect.minX, y: rect.minY))

        // Left edge → top-left corner
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - r))
        path.curve(to: NSPoint(x: rect.minX + r, y: rect.maxY),
                    controlPoint1: NSPoint(x: rect.minX, y: rect.maxY),
                    controlPoint2: NSPoint(x: rect.minX, y: rect.maxY))

        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = bubblePath()

        // Fill body
        Self.bodyColor.setFill()
        path.fill()

        // Draw header background
        let headerRect = NSRect(x: bodyRect.minX, y: bodyRect.maxY - Self.headerHeight,
                                width: bodyRect.width, height: Self.headerHeight)
        let headerClip = NSBezierPath(roundedRect: headerRect,
                                       xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        // Clip to just the top part (intersect with header rect + a bit below to cover the non-rounded bottom)
        let headerFillRect = NSRect(x: bodyRect.minX, y: bodyRect.maxY - Self.headerHeight,
                                     width: bodyRect.width, height: Self.headerHeight)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        Self.headerColor.setFill()
        NSBezierPath(rect: headerFillRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Stroke border
        Self.borderColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false

        // Header label
        headerLabel = NSTextField(labelWithString: "claude ~")
        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        headerLabel.textColor = Self.accentColor
        headerLabel.backgroundColor = .clear
        headerLabel.isBezeled = false
        headerLabel.isEditable = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        // Close button
        closeButton = NSButton(title: "×", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 16, weight: .light)
        closeButton.contentTintColor = Self.accentColor.withAlphaComponent(0.6)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        // Scroll view with text
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textColor = NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        addSubview(scrollView)

        // Click gesture on entire bubble (works across subviews)
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(bubbleClicked))
        clickGesture.delegate = self
        addGestureRecognizer(clickGesture)

        let tail = Self.tailHeight

        NSLayoutConstraint.activate([
            // Header label (at the top of the view)
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            headerLabel.heightAnchor.constraint(equalToConstant: Self.headerHeight - 8),

            // Close button (top-right)
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            // Scroll view (below header, above tail)
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight + 2),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(tail + 8)),
        ])
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func bubbleClicked(_ sender: NSClickGestureRecognizer) {
        onClick?()
    }

    func updateContent(_ text: String) {
        textView.string = text
    }

    func updateHeader(_ title: String) {
        headerLabel.stringValue = title
    }
}

extension SpeechBubbleView: NSGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        // Don't recognize click gesture on the close button
        return !closeButton.frame.contains(location)
    }
}

class CatWindowController: NSWindowController {
    private var catView: CatView!
    private var roaming: RoamingBehavior!
    private var animator: CatAnimator!
    private let prefs = CatPreferences.shared

    /// Resolve tmux binary path at startup (GUI apps have minimal PATH without /opt/homebrew/bin)
    private static let tmuxPath: String = {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "tmux"
    }()

    /// Resolve cmux binary path at startup
    private static let cmuxPath: String = {
        for path in ["/opt/homebrew/bin/cmux", "/usr/local/bin/cmux", "/Applications/cmux.app/Contents/MacOS/cmux"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "cmux"
    }()

    private var pendingTarget: String?  // tmux: session:window.pane, cmux: workspace_id
    private var pendingTitle: String?
    private var pendingMux: String = "tmux"  // "tmux" or "cmux"

    private var isCmux: Bool { pendingMux == "cmux" || prefs.terminalApp == "cmux" }

    // Tooltip window for showing notification title
    private var tooltipWindow: NSWindow?
    private var tooltipLabel: NSTextField?
    private var tooltipTimer: Timer?

    // Speech bubble window for showing Claude output
    private var speechBubbleWindow: NSWindow?
    private var speechBubbleView: SpeechBubbleView?
    private var speechBubbleTimer: Timer?

    // Track previous roaming state for transition animations
    private var previousRoamingState: CatState = .idle

    // Auto-dismiss: polls whether the user has manually focused the target pane
    private var focusCheckTimer: Timer?

    convenience init() {
        let catSize = CatPreferences.shared.catSize

        let window = NonActivatingWindow(
            contentRect: NSRect(origin: .zero, size: catSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        self.init(window: window)

        setupCat(in: window, size: catSize)
    }

    private func setupCat(in window: NSWindow, size: CGSize) {
        // Create the cat view
        catView = CatView(frame: NSRect(origin: .zero, size: size))
        catView.delegate = self
        window.contentView = catView

        // Setup animator
        animator = CatAnimator()
        animator.delegate = self
        animator.catType = prefs.catType

        // Setup roaming behavior
        roaming = RoamingBehavior()
        roaming.delegate = self

        // Start roaming when window appears
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            roaming.start(in: visibleFrame, catSize: size)
        }

        // Start idle animation
        animator.play(.walk, loop: true)

        // Handle screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Handle preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .catPreferencesChanged,
            object: nil
        )

        // Setup tooltip window
        setupTooltip()

        // Setup speech bubble window
        setupSpeechBubble()
    }

    private func setupTooltip() {
        let tooltip = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 28),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tooltip.isOpaque = false
        tooltip.backgroundColor = .clear
        tooltip.level = .floating
        tooltip.hasShadow = true
        tooltip.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        tooltip.ignoresMouseEvents = true

        // Use a background view for rounded corners
        let backgroundView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        backgroundView.layer?.cornerRadius = 6

        // Create centered label
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        backgroundView.addSubview(label)

        // Center label in background view using constraints
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor)
        ])

        tooltip.contentView = backgroundView
        tooltipWindow = tooltip
        tooltipLabel = label
    }

    private func showTooltip(target: String?, title: String?) {
        guard let tooltip = tooltipWindow, let label = tooltipLabel else { return }

        // Extract session/worktree name from target (format: SESSION:WINDOW.PANE)
        let sessionName = target?.split(separator: ":").first.map(String.init)

        // Just show the worktree name
        let displayText = sessionName ?? "Notification"
        label.stringValue = displayText

        // Resize tooltip to fit text with padding
        let size = (displayText as NSString).size(withAttributes: [.font: label.font!])
        let width = max(size.width + 20, 80)
        let height: CGFloat = 28
        tooltip.setContentSize(NSSize(width: width, height: height))

        updateTooltipPosition()
        tooltip.orderFront(nil)

        // Auto-hide after 3 seconds
        tooltipTimer?.invalidate()
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hideTooltip()
        }
    }

    private func hideTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        tooltipWindow?.orderOut(nil)
    }

    private func updateTooltipPosition() {
        guard let catWindow = window, let tooltip = tooltipWindow else { return }

        let catFrame = catWindow.frame
        let tooltipSize = tooltip.frame.size

        // Position tooltip above the cat, centered
        let x = catFrame.midX - tooltipSize.width / 2
        let y = catFrame.maxY + 2

        tooltip.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Speech Bubble

    private static let speechBubbleWidth: CGFloat = 240
    private static let speechBubbleMaxHeight: CGFloat = 200
    private static let speechBubbleMinHeight: CGFloat = 70

    private func setupSpeechBubble() {
        let bubbleWindow = NonActivatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.speechBubbleWidth, height: Self.speechBubbleMinHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        bubbleWindow.isOpaque = false
        bubbleWindow.backgroundColor = .clear
        bubbleWindow.level = .floating
        bubbleWindow.hasShadow = true
        bubbleWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        bubbleWindow.ignoresMouseEvents = false

        let bubbleView = SpeechBubbleView(frame: NSRect(x: 0, y: 0, width: Self.speechBubbleWidth, height: Self.speechBubbleMinHeight))
        bubbleView.autoresizingMask = [.width, .height]
        bubbleWindow.contentView = bubbleView

        bubbleView.onClose = { [weak self] in
            self?.hideSpeechBubble()
        }
        bubbleView.onClick = { [weak self] in
            self?.openSession()
        }

        speechBubbleWindow = bubbleWindow
        speechBubbleView = bubbleView
    }

    private func showSpeechBubble(target: String?) {
        guard let bubble = speechBubbleWindow, let view = speechBubbleView else { return }

        // Read window/workspace name for the header
        if let target = target, let paneName = readWindowName(target: target) {
            view.updateHeader("\(paneName) ~")
        } else {
            view.updateHeader("claude ~")
        }

        // Read initial content
        refreshSpeechBubbleContent()

        updateSpeechBubblePosition()
        bubble.orderFront(nil)

        // Start refresh timer
        speechBubbleTimer?.invalidate()
        speechBubbleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshSpeechBubbleContent()
        }
    }

    private func hideSpeechBubble() {
        speechBubbleTimer?.invalidate()
        speechBubbleTimer = nil
        speechBubbleWindow?.orderOut(nil)
    }

    private func refreshSpeechBubbleContent() {
        // Skip polling for cmux — CLI commands activate the app and steal focus
        guard !isCmux else { return }
        guard let target = pendingTarget, let view = speechBubbleView else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let content = self?.readPane(target: target) else { return }
            DispatchQueue.main.async {
                view.updateContent(content)
                self?.resizeSpeechBubble(for: content)
                self?.updateSpeechBubblePosition()
            }
        }
    }

    private func resizeSpeechBubble(for text: String) {
        guard let bubble = speechBubbleWindow else { return }

        // Calculate text height
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let textWidth = Self.speechBubbleWidth - 28 // padding
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        let contentHeight = textSize.height + SpeechBubbleView.headerHeight + SpeechBubbleView.tailHeight + 28
        let height = min(max(contentHeight, Self.speechBubbleMinHeight), Self.speechBubbleMaxHeight)
        let width = Self.speechBubbleWidth

        // Preserve position (top-left anchored) while resizing
        let oldFrame = bubble.frame
        let newOrigin = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY - height)
        bubble.setFrame(NSRect(x: newOrigin.x, y: newOrigin.y, width: width, height: height), display: true)
    }

    private func updateSpeechBubblePosition() {
        guard let catWindow = window, let bubble = speechBubbleWindow else { return }

        let catFrame = catWindow.frame
        let bubbleSize = bubble.frame.size

        // Position bubble above the cat, centered
        let x = catFrame.midX - bubbleSize.width / 2
        let y = catFrame.maxY + 4

        // Clamp to screen bounds (use the screen the cat is actually on)
        let screen = catWindow.screen ?? NSScreen.main
        if let screenFrame = screen?.visibleFrame {
            let clampedX = max(screenFrame.minX + 4, min(x, screenFrame.maxX - bubbleSize.width - 4))
            let clampedY = min(y, screenFrame.maxY - bubbleSize.height - 4)
            bubble.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        } else {
            bubble.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Read window/workspace name for the bubble header
    private func readWindowName(target: String) -> String? {
        // Skip cmux CLI calls — they activate the app and steal focus
        if isCmux { return nil }
        return readTmuxWindowName(target: target)
    }

    private func readTmuxWindowName(target: String) -> String? {
        guard target != "default",
              target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else {
            return nil
        }

        let safeTarget = target.replacingOccurrences(of: "'", with: "'\"'\"'")
        let task = Process()
        let pipe = Pipe()
        task.launchPath = Self.tmuxPath
        task.arguments = ["display-message", "-t", safeTarget, "-p", "#{window_name}"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }
        return output
    }

    private func readCmuxWorkspaceName(target: String) -> String? {
        guard target != "default",
              target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else {
            return nil
        }

        let task = Process()
        let pipe = Pipe()
        task.launchPath = Self.cmuxPath
        task.arguments = ["list-workspaces"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Parse workspace list to find the matching workspace name
        // cmux list-workspaces output format varies — look for our target ID
        for line in output.components(separatedBy: "\n") {
            if line.contains(target) {
                // Extract the workspace name (typically the last column or after the ID)
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "\t")
                if parts.count >= 2 {
                    return parts.last?.trimmingCharacters(in: .whitespaces)
                }
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Read pane/surface content, stripping ANSI escape codes
    private func readPane(target: String) -> String? {
        if isCmux {
            return readCmuxSurface(target: target)
        }
        return readTmuxPane(target: target)
    }

    private func readTmuxPane(target: String) -> String? {
        guard target != "default",
              target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else {
            return nil
        }

        let safeTarget = target.replacingOccurrences(of: "'", with: "'\"'\"'")
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/bash"
        let tmux = Self.tmuxPath
        task.arguments = ["-c", "\(tmux) capture-pane -p -t '\(safeTarget)' 2>/dev/null"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Strip ANSI escape sequences
        let ansiPattern = "\\x1b\\[[0-9;]*[a-zA-Z]|\\x1b\\][^\\x07]*\\x07|\\x1b[^\\[\\]][a-zA-Z]"
        var stripped = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Strip private-use Unicode (nerd font icons etc.) that render as □
        stripped = stripped.filter { char in
            let scalar = char.unicodeScalars.first!.value
            // Keep standard Unicode, exclude private use areas
            return scalar < 0xE000 || (scalar > 0xF8FF && scalar < 0xF0000)
        }

        // Process lines: trim trailing whitespace, collapse box-drawing separator lines
        let lines = stripped.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .map { line -> String in
                // Collapse lines made entirely of box-drawing characters (─, ═, ━, etc.) into a short separator
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy({ scalar in
                    let v = scalar.value
                    // Box drawing (U+2500-U+257F), dashes, underscores
                    return (v >= 0x2500 && v <= 0x257F) || v == 0x2014 || v == 0x2013 || v == 0x2015 || v == 0x5F
                }) {
                    return "───"
                }
                return line
            }

        // Remove trailing empty lines, then take last 15 non-empty-trailing lines
        let trimmed = Array(lines
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .suffix(15))

        let result = trimmed.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    private func readCmuxSurface(target: String) -> String? {
        guard target != "default",
              target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else {
            return nil
        }

        let task = Process()
        let pipe = Pipe()
        task.launchPath = Self.cmuxPath
        task.arguments = ["read-screen", "--surface", target]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Strip ANSI escape sequences (same cleanup as tmux)
        let ansiPattern = "\\x1b\\[[0-9;]*[a-zA-Z]|\\x1b\\][^\\x07]*\\x07|\\x1b[^\\[\\]][a-zA-Z]"
        var stripped = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        stripped = stripped.filter { char in
            let scalar = char.unicodeScalars.first!.value
            return scalar < 0xE000 || (scalar > 0xF8FF && scalar < 0xF0000)
        }

        let lines = stripped.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy({ scalar in
                    let v = scalar.value
                    return (v >= 0x2500 && v <= 0x257F) || v == 0x2014 || v == 0x2013 || v == 0x2015 || v == 0x5F
                }) {
                    return "───"
                }
                return line
            }

        let trimmed = Array(lines
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .suffix(15))

        let result = trimmed.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    @objc private func preferencesDidChange() {
        // Update cat type
        animator.catType = prefs.catType

        // Update size
        let newSize = prefs.catSize
        window?.setContentSize(newSize)
        catView.frame = NSRect(origin: .zero, size: newSize)

        // Update roaming bounds with new size
        if let screen = NSScreen.main {
            roaming.updateBounds(screen.visibleFrame)
            roaming.updateCatSize(newSize)
        }
    }

    @objc private func screenDidChange() {
        if let screen = NSScreen.main {
            roaming.updateBounds(screen.visibleFrame)
        }
    }

    // MARK: - Public API

    func pause() {
        roaming.pause()
        animator.pause()
    }

    func resume() {
        roaming.resume()
        animator.resume()
    }

    func triggerAttention(target: String?, title: String?, mux: String = "tmux") {
        pendingTarget = target
        pendingTitle = title
        pendingMux = mux

        // Make sure cat is visible and running (in case it was hidden)
        // Use orderFront instead of showWindow to avoid stealing focus
        window?.orderFront(nil)
        resume()

        roaming.triggerAttention(session: target, title: title)
        animator.play(.notification, loop: true)

        // Make window accept mouse events
        window?.ignoresMouseEvents = false

        // Show speech bubble (controlled by tooltip preference)
        if prefs.tooltipEnabled {
            showSpeechBubble(target: target)
        }

        // Start polling to auto-dismiss if user manually focuses the target pane
        startFocusCheck()
    }

    func resetToIdle() {
        pendingTarget = nil
        pendingTitle = nil
        stopFocusCheck()
        hideTooltip()
        hideSpeechBubble()
        roaming.resetToIdle()  // This triggers makeDecision() which sets state and calls roamingDidChangeState()
        NotificationCenter.default.post(name: .catAttentionDismissed, object: nil)
    }

    // MARK: - Auto-dismiss focus check

    private func startFocusCheck() {
        stopFocusCheck()
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkIfUserFocusedTarget()
        }
    }

    private func stopFocusCheck() {
        focusCheckTimer?.invalidate()
        focusCheckTimer = nil
    }

    private func checkIfUserFocusedTarget() {
        guard let target = pendingTarget, target != "default",
              target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else {
            return
        }

        if isCmux {
            checkIfUserFocusedCmuxTarget(target: target)
        } else {
            checkIfUserFocusedTmuxTarget(target: target)
        }
    }

    private func checkIfUserFocusedTmuxTarget(target: String) {
        let safeTarget = target.replacingOccurrences(of: "'", with: "'\"'\"'")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let frontmostScript = "tell application \"System Events\" to get name of first process whose frontmost is true"
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: frontmostScript),
                  let result = appleScript.executeAndReturnError(&error).stringValue,
                  result.lowercased() == self?.prefs.terminalApp.lowercased() else {
                return
            }

            let task = Process()
            let pipe = Pipe()
            task.launchPath = "/bin/bash"
            let tmux = Self.tmuxPath
            task.arguments = ["-c", """
                TARGET='\(safeTarget)'
                WINDOW_ACTIVE=$(\(tmux) display-message -t "$TARGET" -p '#{window_active}' 2>/dev/null)
                PANE_ACTIVE=$(\(tmux) display-message -t "$TARGET" -p '#{pane_active}' 2>/dev/null)
                if [ "$WINDOW_ACTIVE" = "1" ] && [ "$PANE_ACTIVE" = "1" ]; then
                    echo "focused"
                fi
                """]
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if output == "focused" {
                DispatchQueue.main.async {
                    self?.resetToIdle()
                }
            }
        }
    }

    private func checkIfUserFocusedCmuxTarget(target: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // cmux IS the terminal — if it's frontmost, the user can see the output.
            // No need to check the exact workspace (unlike tmux which runs inside another app).
            // Avoid calling cmux CLI here: CLI commands communicate via socket and can
            // activate the cmux app, causing it to steal focus repeatedly.
            let frontmostScript = "tell application \"System Events\" to get name of first process whose frontmost is true"
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: frontmostScript),
                  let result = appleScript.executeAndReturnError(&error).stringValue,
                  result.lowercased() == "cmux" else {
                return
            }

            DispatchQueue.main.async {
                self?.resetToIdle()
            }
        }
    }

    func handleStatusBarClick() {
        // Same behavior as clicking the cat
        if case .attentionNeeded = roaming.state {
            openSession()
        }
    }

    private func openSession() {
        if isCmux {
            openCmuxWorkspace()
        } else {
            openTmuxSession()
        }
    }

    private func openTmuxSession() {
        // Switch to the right tmux pane if we have a target
        // Validate target to prevent command injection (only allow valid tmux target characters)
        if let target = pendingTarget, target != "default",
           target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil {
            let safeTarget = target.replacingOccurrences(of: "'", with: "'\"'\"'")
            let task = Process()
            task.launchPath = "/bin/bash"
            let tmux = Self.tmuxPath
            let cmd = """
            TARGET='\(safeTarget)'
            CLIENT=$(\(tmux) list-clients -F '#{client_name}' 2>/dev/null | head -1)
            if [ -n "$CLIENT" ]; then
                \(tmux) switch-client -c "$CLIENT" -t "$TARGET" 2>/dev/null
            else
                \(tmux) switch-client -t "$TARGET" 2>/dev/null
            fi
            """
            task.arguments = ["-c", cmd]
            try? task.run()
            task.waitUntilExit()
        }

        // Bring the configured terminal to the front
        let terminalApp = prefs.terminalApp
        let script = """
        tell application "\(terminalApp)"
            activate
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }

        resetToIdle()
    }

    private func openCmuxWorkspace() {
        // Switch to the target workspace in cmux
        if let target = pendingTarget, target != "default",
           target.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil {
            let task = Process()
            task.launchPath = Self.cmuxPath
            task.arguments = ["select-workspace", target]
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }

        // Bring cmux to the front
        let script = """
        tell application "cmux"
            activate
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }

        resetToIdle()
    }
}

// MARK: - CatViewDelegate

extension CatWindowController: CatViewDelegate {
    func catViewWasClicked() {
        if case .attentionNeeded = roaming.state {
            openSession()
        }
    }

    func catViewDragDidBegin() {
        roaming.beginDragging()
        let liftedFrames = SpriteManager.shared.loadFrames(catType: prefs.catType, animation: .lifted)
        if !liftedFrames.isEmpty {
            animator.play(.lifted, loop: true, direction: roaming.direction)
        }
    }

    func catViewDragDidPause() {
        let idleFrames = SpriteManager.shared.loadFrames(catType: prefs.catType, animation: .liftedIdle)
        if !idleFrames.isEmpty {
            animator.play(.liftedIdle, loop: true, direction: roaming.direction)
        }
    }

    func catViewDragDidResume() {
        let liftedFrames = SpriteManager.shared.loadFrames(catType: prefs.catType, animation: .lifted)
        if !liftedFrames.isEmpty {
            animator.play(.lifted, loop: true, direction: roaming.direction)
        }
    }

    func catViewWasDragged(to position: NSPoint) {
        roaming.endDragging(at: position)
        if case .attentionNeeded = roaming.state {
            animator.play(.notification, loop: true, direction: roaming.direction)
        }
    }
}

// MARK: - CatAnimatorDelegate

extension CatWindowController: CatAnimatorDelegate {
    func animatorDidUpdateFrame(_ image: NSImage) {
        catView.updateImage(image)
    }

    func animatorDidCompleteAnimation(_ type: AnimationType) {
        switch type {
        case .walkToSleep:
            roaming.resume()
            animator.play(.sleep, loop: true, direction: roaming.direction)
            return
        case .sleepToWalk:
            roaming.resume()
            animator.play(.walk, loop: true, direction: roaming.direction)
            return
        default:
            break
        }

        // When a non-looping animation completes, return to appropriate state
        switch roaming.state {
        case .attentionNeeded:
            animator.play(.notification, loop: true)
        default:
            animator.play(.walk, loop: true)
        }
    }
}

// MARK: - RoamingBehaviorDelegate

extension CatWindowController: RoamingBehaviorDelegate {
    func roamingDidChangeState(_ newState: CatState) {
        let wasSleeping = previousRoamingState == .sleeping
        previousRoamingState = newState

        switch newState {
        case .idle:
            if wasSleeping && hasTransitionFrames(.sleepToWalk) {
                roaming.pause()
                animator.play(.sleepToWalk, loop: false, direction: roaming.direction)
            } else {
                animator.play(.walk, loop: true, direction: roaming.direction)
            }
        case .walking(let direction):
            if wasSleeping && hasTransitionFrames(.sleepToWalk) {
                roaming.pause()
                animator.play(.sleepToWalk, loop: false, direction: direction)
            } else {
                animator.play(.walk, loop: true, direction: direction)
            }
        case .sleeping:
            if !wasSleeping && hasTransitionFrames(.walkToSleep) {
                roaming.pause()
                animator.play(.walkToSleep, loop: false, direction: roaming.direction)
            } else {
                animator.play(.sleep, loop: true, direction: roaming.direction)
            }
        case .attentionNeeded:
            animator.play(.notification, loop: true, direction: roaming.direction)
        }
    }

    private func hasTransitionFrames(_ animation: AnimationType) -> Bool {
        !SpriteManager.shared.loadFrames(catType: prefs.catType, animation: animation).isEmpty
    }

    func roamingDidUpdatePosition(_ position: CGPoint) {
        window?.setFrameOrigin(position)
        // Keep tooltip/bubble above the cat
        if case .attentionNeeded = roaming.state {
            updateTooltipPosition()
            updateSpeechBubblePosition()
        }
    }

    func roamingDidChangeDirection(_ direction: Direction) {
        animator.updateDirection(direction)
    }
}
