import AppKit
import ButlerCore
import SwiftUI

/// House Rules: a title, one line of explanation, and a mono editor with line
/// numbers inside a hairline border.
struct RulesPage: View {
    @ObservedObject var page: FolderViewModel
    @State private var text = ""
    @State private var savedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("House Rules")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Stock.ink)
                Text("Plain words. Sent with every proposal for \(page.folder?.name ?? "this folder").")
                    .font(.system(size: 12))
                    .foregroundStyle(Stock.secondary)
            }
            .padding(.horizontal, Layout.margin)
            .padding(.top, 8)
            .padding(.bottom, 12)

            RulesEditor(text: $text)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write the house rules for this folder.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Stock.tertiary)
                            .padding(.leading, RulesEditor.gutter + 9)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                }
                .overlay { Rectangle().strokeBorder(Stock.hairline, lineWidth: 1) }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, 12)
                .onChange(of: text) { _, value in
                    guard value != page.folder?.rules else { return }
                    page.updateRules(value)
                    savedAt = Date()
                }

            Hairline()
            HStack {
                Text(savedAt.map { "Saved " + $0.formatted(date: .omitted, time: .shortened) } ?? "Saved")
                    .font(.system(size: 12))
                    .monospacedDigit()
                Spacer()
                Text("Applies to future proposals")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Stock.secondary)
            .padding(.horizontal, Layout.margin)
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPaper()
        .overlay(alignment: .top) { Hairline() }
        .navigationTitle("House Rules")
        .toolbar {
            ToolbarItem {
                Menu("Templates") {
                    ForEach(RuleTemplate.all) { template in
                        Button(template.title) { text = template.text }
                    }
                }
                .help("Start from a set of example rules")
            }
        }
        .onAppear { text = page.folder?.rules ?? "" }
    }
}

/// A plain `NSTextView` with a line-number ruler. SwiftUI's `TextEditor` has
/// no way to keep numbers beside wrapped lines.
struct RulesEditor: NSViewRepresentable {
    static let gutter: CGFloat = 40
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = Stock.inkNS
        view.insertionPointColor = Stock.accentNS
        view.textContainerInset = NSSize(width: 4, height: 9)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        view.defaultParagraphStyle = paragraph
        view.typingAttributes[.paragraphStyle] = paragraph
        view.string = text

        let ruler = LineNumberRuler(textView: view, scrollView: scroll)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        if let style = view.defaultParagraphStyle, let storage = view.textStorage {
            storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
        }
        scroll.verticalRulerView?.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
            view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

/// Numbers the logical lines, not the wrapped ones, and draws one hairline
/// between the numbers and the text.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = RulesEditor.gutter
        clipsToBounds = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(redraw),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func redraw() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let ink = Stock.inkNS
        ink.withAlphaComponent(0.10).setFill()
        NSRect(x: bounds.maxX - 1, y: visibleRect.minY, width: 1, height: visibleRect.height).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: ink.withAlphaComponent(0.4),
        ]
        let content = textView.string as NSString
        let inset = textView.textContainerInset.height
        let offset = convert(NSPoint.zero, from: textView).y
        let visible = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let firstCharacter = layout.characterIndexForGlyph(at: visible.location)

        var number = 1
        content.substring(to: firstCharacter).forEach { if $0 == "\n" { number += 1 } }

        func label(_ value: Int, at y: CGFloat) {
            let text = "\(value)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: bounds.maxX - size.width - 10, y: y + 1), withAttributes: attributes)
        }

        var index = content.lineRange(for: NSRange(location: firstCharacter, length: 0)).location
        let end = NSMaxRange(layout.characterRange(forGlyphRange: visible, actualGlyphRange: nil))
        while index <= end, index < content.length {
            let line = content.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: line.location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            label(number, at: fragment.minY + inset + offset)
            number += 1
            index = NSMaxRange(line)
        }
        if content.length == 0 || content.hasSuffix("\n") {
            let extra = layout.extraLineFragmentRect
            let y = content.length == 0 ? 0 : extra.minY
            label(number, at: y + inset + offset)
        }
    }
}
