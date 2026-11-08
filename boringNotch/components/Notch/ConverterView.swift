//
//  ConverterView.swift
//  boringNotch
//
//  Notch tab that converts images and text documents locally (ImageIO, PDFKit, NSAttributedString).
//  Nothing leaves the Mac.
//

import AppKit
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Engine (no app dependencies)

enum FileConverter {
    enum Kind { case image, text }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let docx = UTType("org.openxmlformats.wordprocessingml.document") ?? .data
    static let doc = UTType("com.microsoft.word.doc") ?? .data
    static let odt = UTType("org.oasis-open.opendocument.text") ?? .data
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    /// Writable image formats, in display order, limited to what ImageIO can encode on this Mac.
    static let imageTargets: [UTType] = {
        let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        return [UTType.png, .jpeg, .heic, .tiff, .gif, .bmp].filter { writable.contains($0.identifier) } + [.pdf]
    }()

    static let textTargets: [UTType] = [.plainText, .rtf, .html, docx, odt, doc, .pdf]

    /// A PDF can become text or images, whichever kind was picked.
    static func targets(for kind: Kind, from source: UTType) -> [UTType] {
        if source.conforms(to: .pdf) { return (textTargets + imageTargets).filter { $0 != .pdf } }
        return (kind == .image ? imageTargets : textTargets).filter { $0 != source }
    }

    static func accepts(_ kind: Kind, url: URL, type: UTType) -> Bool {
        type.conforms(to: .pdf) || self.kind(of: url, type: type) == kind
    }

    /// The jobs a source→target pair needs: image work (ImageIO) or text work (AppKit, main thread).
    static func isImageJob(kind: Kind, source: UTType, target: UTType) -> Bool {
        source.conforms(to: .pdf) ? target.conforms(to: .image) : kind == .image
    }

    /// The kind a file belongs to, if we can read it.
    static func kind(of url: URL, type: UTType) -> Kind? {
        if type.conforms(to: .pdf) { return PDFDocument(url: url) != nil ? .text : nil }
        if type.conforms(to: .image),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 { return .image }
        return textReadType(type) != nil ? .text : nil
    }

    static func label(_ type: UTType) -> String {
        if type == .plainText { return "TXT" }
        return (type.preferredFilenameExtension ?? type.localizedDescription ?? "?").uppercased()
    }

    // MARK: Images

    static func convertImage(_ source: URL, to target: UTType, at dest: URL) throws {
        if (try? source.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .pdf) == true, let pdf = PDFDocument(url: source) {
            return try rasterize(pdf, to: target, at: dest)
        }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw Failure("This image can't be read.")
        }
        if target == .pdf {
            guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  let page = PDFPage(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))) else {
                throw Failure("This image can't be turned into a PDF.")
            }
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)
            guard pdf.write(to: dest) else { throw Failure("The PDF couldn't be written.") }
            return
        }
        // Animated/multi-page formats keep every frame, the others take the first one.
        let frames = [UTType.gif, .tiff].contains(target) ? CGImageSourceGetCount(src) : 1
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, target.identifier as CFString, frames, nil) else {
            throw Failure("\(label(target)) isn't supported on this Mac.")
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        for i in 0..<frames { CGImageDestinationAddImageFromSource(out, src, i, options) }
        guard CGImageDestinationFinalize(out) else { throw Failure("The image couldn't be converted.") }
    }

    /// PDF pages to an image at 2× (144 dpi). GIF and TIFF get every page, the others the first one.
    private static func rasterize(_ pdf: PDFDocument, to target: UTType, at dest: URL) throws {
        let pages = [UTType.gif, .tiff].contains(target) ? pdf.pageCount : min(pdf.pageCount, 1)
        guard pages > 0, let out = CGImageDestinationCreateWithURL(dest as CFURL, target.identifier as CFString, pages, nil) else {
            throw Failure("This PDF can't be turned into \(label(target)).")
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        for i in 0..<pages {
            guard let page = pdf.page(at: i) else { continue }
            var size = page.bounds(for: .mediaBox).size
            if page.rotation % 180 != 0 { size = NSSize(width: size.height, height: size.width) }
            let image = page.thumbnail(of: NSSize(width: size.width * 2, height: size.height * 2), for: .mediaBox)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            CGImageDestinationAddImage(out, cg, options)
        }
        guard CGImageDestinationFinalize(out) else { throw Failure("The PDF couldn't be converted.") }
    }

    // MARK: Text

    static func textReadType(_ type: UTType) -> NSAttributedString.DocumentType? {
        if type.conforms(to: markdown) { return .plain } // parsed separately
        if type.conforms(to: .html) { return .html }
        if type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD) { return .rtfd }
        if type.conforms(to: .rtf) { return .rtf }
        if type.conforms(to: .webArchive) { return .webArchive }
        if type.conforms(to: docx) { return .officeOpenXML }
        if type.conforms(to: doc) { return .docFormat }
        if type.conforms(to: odt) { return .openDocument }
        if type.conforms(to: .plainText) { return .plain }
        return nil
    }

    /// Main thread only: AppKit's HTML importer and the PDF print operation require it.
    @MainActor
    static func convertText(_ source: URL, type: UTType, to target: UTType, at dest: URL) throws {
        let text: NSAttributedString
        if type.conforms(to: .pdf) {
            guard let extracted = PDFDocument(url: source)?.selectionForEntireDocument?.attributedString, extracted.length > 0 else {
                throw Failure("This PDF has no selectable text (it may be a scan).")
            }
            text = extracted
        } else if type.conforms(to: markdown) {
            let raw = try String(contentsOf: source, encoding: .utf8)
            let parsed = try AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            text = styled(NSAttributedString(parsed))
        } else {
            guard let readType = textReadType(type) else { throw Failure("This document can't be read.") }
            text = try NSAttributedString(url: source, options: [.documentType: readType], documentAttributes: nil)
        }

        if target == .pdf { return try writePDF(text, to: dest) }

        let writeType: NSAttributedString.DocumentType
        switch target {
        case .plainText: writeType = .plain
        case .rtf: writeType = .rtf
        case .html: writeType = .html
        case docx: writeType = .officeOpenXML
        case odt: writeType = .openDocument
        case doc: writeType = .docFormat
        default: throw Failure("\(label(target)) isn't supported.")
        }
        let data = try text.data(from: NSRange(location: 0, length: text.length),
                                 documentAttributes: [.documentType: writeType,
                                                      .characterEncoding: String.Encoding.utf8.rawValue])
        try data.write(to: dest)
    }

    /// Markdown marks bold/italic/code as presentation intents, which the RTF/DOCX/… writers ignore: turn them into fonts.
    private static func styled(_ parsed: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: parsed)
        let full = NSRange(location: 0, length: out.length)
        let base = NSFont.systemFont(ofSize: 13)
        out.addAttribute(.font, value: base, range: full)
        out.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            if intent.contains(.code) {
                out.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: range)
                return
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if intent.contains(.strikethrough) { out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            guard !traits.isEmpty else { return }
            out.addAttribute(.font, value: NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: 13) ?? base, range: range)
        }
        return out
    }

    @MainActor
    private static func writePDF(_ text: NSAttributedString, to dest: URL) throws {
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = dest
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.appearance = NSAppearance(named: .aqua) // print black on white even in dark mode
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.textStorage?.setAttributedString(text)
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: dest.path) else {
            throw Failure("The PDF couldn't be written.")
        }
    }

    #if DEBUG
    /// Converts generated samples and checks the results. Runs once in Debug builds.
    @MainActor
    static func selfCheck() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConverterSelfCheck-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            // 2×2 PNG
            let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            let png = dir.appendingPathComponent("a.png")
            let pd = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(pd, ctx.makeImage()!, nil); assert(CGImageDestinationFinalize(pd))
            assert(kind(of: png, type: .png) == .image)
            assert(!targets(for: .image, from: .png).contains(.png))

            let jpg = dir.appendingPathComponent("a.jpg")
            try convertImage(png, to: .jpeg, at: jpg)
            let back = CGImageSourceCreateWithURL(jpg as CFURL, nil)!
            assert(CGImageSourceGetType(back) as String? == UTType.jpeg.identifier)
            let ipdf = dir.appendingPathComponent("a.pdf")
            try convertImage(png, to: .pdf, at: ipdf)
            assert(PDFDocument(url: ipdf)?.pageCount == 1)

            // RTF
            let rtf = dir.appendingPathComponent("b.rtf")
            let sample = NSAttributedString(string: "Hello", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
            try sample.data(from: NSRange(location: 0, length: 5), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: rtf)
            assert(kind(of: rtf, type: .rtf) == .text)

            let txt = dir.appendingPathComponent("b.txt")
            try convertText(rtf, type: .rtf, to: .plainText, at: txt)
            assert((try? String(contentsOf: txt, encoding: .utf8)) == "Hello")
            let docxURL = dir.appendingPathComponent("b.docx")
            try convertText(rtf, type: .rtf, to: docx, at: docxURL)
            assert((try? NSAttributedString(url: docxURL, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil))?.string.hasPrefix("Hello") == true)
            let tpdf = dir.appendingPathComponent("b.pdf")
            try convertText(txt, type: .plainText, to: .pdf, at: tpdf)
            assert((PDFDocument(url: tpdf)?.pageCount ?? 0) >= 1)
            // PDF source: text out and image out
            let ptxt = dir.appendingPathComponent("c.txt")
            try convertText(tpdf, type: .pdf, to: .plainText, at: ptxt)
            assert((try? String(contentsOf: ptxt, encoding: .utf8))?.contains("Hello") == true)
            let ppng = dir.appendingPathComponent("c.png")
            try convertImage(tpdf, to: .png, at: ppng)
            assert(CGImageSourceGetType(CGImageSourceCreateWithURL(ppng as CFURL, nil)!) as String? == UTType.png.identifier)
            assert(isImageJob(kind: .text, source: .pdf, target: .png) && !isImageJob(kind: .image, source: .pdf, target: .rtf))
            print("FileConverter selfCheck passed")
        } catch {
            assertionFailure("FileConverter selfCheck failed: \(error)")
        }
    }
    #endif
}

// MARK: - Model

@MainActor
final class ConverterModel: ObservableObject {
    static let shared = ConverterModel()

    enum Phase: Equatable { case idle, converting, done(URL), failed(String) }

    @Published var kind: FileConverter.Kind?
    @Published private(set) var file: URL?
    @Published private(set) var sourceType: UTType?
    @Published var target: UTType?
    @Published var phase: Phase = .idle
    @Published var dropError: String?

    var targets: [UTType] {
        guard let kind, let sourceType else { return [] }
        return FileConverter.targets(for: kind, from: sourceType)
    }

    /// Loads the first dropped file URL.
    func load(_ providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL else { return }
            Task { @MainActor in ConverterModel.shared.load(url) }
        }
    }

    /// With no type chosen yet, the file picks it.
    func load(_ url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let detected = FileConverter.kind(of: url, type: type)
        // No type chosen yet, or a file already loaded: the new file picks the type.
        if kind == nil || file != nil, let detected { kind = detected }
        guard let kind, FileConverter.accepts(kind, url: url, type: type) else {
            let message = switch file == nil ? kind : nil {
            case .image: "“\(url.lastPathComponent)” isn't an image this Mac can read."
            case .text: "“\(url.lastPathComponent)” isn't a text document this Mac can read."
            case nil: "“\(url.lastPathComponent)” isn't an image or a text document this Mac can read."
            }
            if file == nil { dropError = message } else { phase = .failed(message) }
            return
        }
        dropError = nil
        file = url
        sourceType = type
        target = targets.first
        phase = .idle
    }

    /// Back one step: from the file to the drop zone, from the drop zone to the type choice.
    func back() {
        if file != nil { file = nil; sourceType = nil; target = nil; phase = .idle } else { kind = nil }
        dropError = nil
    }

    func convert() {
        guard let file, let sourceType, let target, let kind else { return }
        let base = file.deletingPathExtension().lastPathComponent
        let ext = target.preferredFilenameExtension ?? "out"

        let panel = NSSavePanel()
        panel.title = "Save Converted File"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "\(base).\(ext)"
        panel.directoryURL = file.deletingLastPathComponent()
        panel.allowedContentTypes = [target]
        panel.canCreateDirectories = true

        // Keep the notch open while the panel is up, so the result is visible afterwards.
        SharingStateManager.shared.beginInteraction()
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor in
                defer { SharingStateManager.shared.endInteraction() }
                guard let self, response == .OK, let dest = panel.url else { return }
                self.phase = .converting
                // Write to a temporary file first, so a failure never leaves a half-written file behind.
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                do {
                    if FileConverter.isImageJob(kind: kind, source: sourceType, target: target) {
                        try await Task.detached { try FileConverter.convertImage(file, to: target, at: tmp) }.value
                    } else {
                        try FileConverter.convertText(file, type: sourceType, to: target, at: tmp)
                    }
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    self.phase = .done(dest)
                } catch {
                    try? FileManager.default.removeItem(at: tmp)
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Views

/// Tab icon, drawn natively like `MacRemoteIcon`: teal→blue squircle with the swap glyph.
struct ConverterIcon: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.78, blue: 0.72), Color(red: 0.16, green: 0.42, blue: 0.95)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
            }
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.1, green: 0.55, blue: 0.85).opacity(0.45), radius: 10, y: 3)
    }
}

struct ConverterView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var model = ConverterModel.shared
    /// Shared with the Shelf: while it is true the notch knows a drag is over it and stays open.
    private var dropTargeted: Bool { vm.dragDetectorTargeting }

    private static let accent = LinearGradient(colors: [Color(red: 0.12, green: 0.72, blue: 0.7), Color(red: 0.2, green: 0.45, blue: 0.98)],
                                               startPoint: .leading, endPoint: .trailing)

    var body: some View {
        Group {
            if model.kind == nil {
                chooser
            } else if model.file == nil {
                dropZone
            } else {
                formatStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $vm.dragDetectorTargeting) { providers in
            guard model.phase != .converting else { return false }
            vm.dropEvent = true // otherwise the notch closes after the drag ends
            model.load(providers)
            return true
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.kind)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.file)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.phase)
        #if DEBUG
        .onAppear { _ = Self.selfCheckOnce }
        #endif
    }

    #if DEBUG
    @MainActor private static let selfCheckOnce: Void = FileConverter.selfCheck()
    #endif

    // MARK: Step 1 — what to convert

    private var chooser: some View {
        HStack(spacing: 20) {
            ConverterIcon(size: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text("Convert")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.dropError ?? (dropTargeted
                     ? "Drop to convert."
                     : "Pick a type, or drop a file here. Nothing is uploaded."))
                    .font(.system(size: 12))
                    .foregroundStyle(model.dropError == nil ? .white.opacity(0.6) : Color(red: 1, green: 0.45, blue: 0.4))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    kindCard("Image", "photo", .image)
                    kindCard("Text", "doc.text", .text)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .transition(.opacity)
    }

    private func kindCard(_ title: String, _ symbol: String, _ kind: FileConverter.Kind) -> some View {
        Button { model.kind = kind; model.dropError = nil } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 104, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Step 2 — drop the file

    private var dropZone: some View {
        HStack(spacing: 14) {
            backButton
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(dropTargeted ? 0.1 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(dropTargeted ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: model.kind == .image ? "photo.badge.plus" : "doc.badge.plus")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(.white.opacity(dropTargeted ? 1 : 0.7))
                            .symbolEffect(.bounce, value: dropTargeted)
                        Text(model.kind == .image ? "Drop an image here" : "Drop a text document here")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(model.dropError ?? (model.kind == .image
                                                 ? "PNG, JPEG, HEIC, WebP, TIFF, GIF, BMP, RAW, PDF…"
                                                 : "TXT, Markdown, RTF, HTML, DOCX, DOC, ODT, PDF…"))
                            .font(.system(size: 11))
                            .foregroundStyle(model.dropError == nil ? .white.opacity(0.5) : Color(red: 1, green: 0.45, blue: 0.4))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                }
                .scaleEffect(dropTargeted ? 1.015 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dropTargeted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .transition(.opacity)
    }

    // MARK: Step 3 — pick the format and convert

    @ViewBuilder
    private var formatStep: some View {
        if let file = model.file, let source = model.sourceType {
            HStack(spacing: 16) {
                backButton
                VStack(spacing: 5) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                        .resizable()
                        .frame(width: 52, height: 52)
                    Text(file.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    badge(FileConverter.label(source))
                }
                .frame(width: 110)

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Convert to")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(model.targets, id: \.identifier) { type in
                            formatPill(type)
                        }
                    }
                    .disabled(model.phase == .converting)
                    actionRow
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch model.phase {
        case .idle:
            Button { model.convert() } label: {
                Label("Convert", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Self.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressStyle())
            .disabled(model.target == nil)
        case .converting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Converting…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
        case .done(let url):
            HStack(spacing: 8) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                pill("Show in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                pill("Convert another", "arrow.counterclockwise") { model.back() }
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    .lineLimit(2)
                pill("Try again", "arrow.clockwise") { model.phase = .idle }
            }
        }
    }

    private func formatPill(_ type: UTType) -> some View {
        let selected = model.target == type
        return Button {
            model.target = type
            if case .done = model.phase { model.phase = .idle }
            if case .failed = model.phase { model.phase = .idle }
        } label: {
            Text(FileConverter.label(type))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? AnyShapeStyle(Self.accent) : AnyShapeStyle(.white.opacity(0.1))))
                .foregroundStyle(selected ? .white : .white.opacity(0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.15)))
            .foregroundStyle(.white.opacity(0.85))
    }

    private var backButton: some View {
        Button { model.back() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.1)))
                .foregroundStyle(.white.opacity(0.8))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Back")
        .disabled(model.phase == .converting)
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.12)))
                .foregroundStyle(.white)
        }
        .buttonStyle(PressStyle())
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
