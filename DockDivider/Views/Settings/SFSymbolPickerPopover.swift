//
//  SFSymbolPickerPopover.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI
import AppKit

// MARK: - SF Symbol Category Model

struct SFSymbolCategory: Identifiable, Equatable {
    let key: String
    let label: String
    let icon: String
    var id: String { key }
}

// MARK: - Native System SF Symbols Catalog

final class SFSymbolCatalog {
    static let shared = SFSymbolCatalog()

    let categories: [SFSymbolCategory]
    let allSymbols: [String]
    let symbolsByCategory: [String: [String]]
    let searchKeywordsBySymbol: [String: [String]]

    private static let excludedLocaleSuffixes: Set<String> = [
        "ar", "bn", "el", "gu", "he", "hi", "ja", "km", "kn",
        "ko", "LA", "ml", "mr", "my", "or", "pa", "ru", "si",
        "ta", "te", "th", "ur", "zh", "hant", "hans"
    ]

    private static let categoryDisplayLabels: [String: String] = [
        "all": "All",
        "dock_curated": "Dock Picks",
        "whatsnew": "What's New",
        "communication": "Communication",
        "weather": "Weather",
        "maps": "Maps",
        "objectsandtools": "Objects & Tools",
        "devices": "Devices",
        "cameraandphotos": "Camera & Photos",
        "gaming": "Gaming",
        "connectivity": "Connectivity",
        "transportation": "Transportation",
        "automotive": "Automotive",
        "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security",
        "human": "Human",
        "home": "Home",
        "fitness": "Fitness",
        "nature": "Nature",
        "editing": "Editing",
        "textformatting": "Text",
        "media": "Media",
        "keyboard": "Keyboard",
        "commerce": "Commerce",
        "time": "Time",
        "health": "Health",
        "shapes": "Shapes",
        "arrows": "Arrows",
        "indices": "Indices",
        "math": "Math"
    ]

    static let curatedDockSymbols: [String] = [
        // Developer & Terminal
        "terminal.fill", "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces",
        "hammer.fill", "wrench.and.screwdriver.fill", "cpu.fill", "memorychip.fill",
        "server.rack", "network", "externaldrive.fill", "ant.fill", "ladybug.fill",
        // Folders & Workspaces
        "folder.fill", "folder", "folder.badge.gearshape", "tray.full.fill",
        "archivebox.fill", "doc.text.fill", "book.closed.fill", "bookmark.fill",
        "briefcase.fill", "building.2.fill", "graduationcap.fill", "calendar",
        // Creative, Media & Music
        "paintbrush.pointed.fill", "paintpalette.fill", "swatchpalette.fill", "photo.fill",
        "camera.fill", "video.fill", "film.fill", "music.note", "music.quarternote.3",
        "headphones", "mic.fill", "guitars.fill", "waveform",
        // Gaming & Entertainment
        "gamecontroller.fill", "dice.fill", "puzzlepiece.extension.fill", "trophy.fill",
        "flag.checkered", "tv.fill", "play.tv.fill",
        // Communication & Social
        "bubble.left.and.bubble.right.fill", "message.fill", "envelope.fill", "paperplane.fill",
        "phone.fill", "video.bubble.left.fill", "at", "number", "globe", "safari.fill",
        // AI, Sparkles & Badges
        "sparkles", "wand.and.stars", "brain.head.profile", "bolt.fill", "flame.fill",
        "star.fill", "heart.fill", "crown.fill", "diamond.fill", "seal.fill",
        "shield.lefthalf.filled", "lock.fill", "key.fill",
        // Dividers, Shapes & Separators
        "line.diagonal", "poweron", "circle.fill", "circle", "square.fill", "capsule.portrait.fill",
        "ellipsis", "ellipsis.circle.fill", "grid", "square.grid.2x2.fill"
    ]

    private init() {
        let coreGlyphsPath = "/System/Library/CoreServices/CoreGlyphs.bundle"
        let bundle = Bundle(path: coreGlyphsPath)

        // 1. Load all symbols from name_availability.plist
        var loadedSymbols: [String] = []
        if let availURL = bundle?.url(forResource: "name_availability", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: availURL),
           let symbolsDict = dict["symbols"] as? [String: Any] {
            loadedSymbols = symbolsDict.keys
                .filter { name in
                    if let lastComponent = name.split(separator: ".").last,
                       Self.excludedLocaleSuffixes.contains(String(lastComponent)) {
                        return false
                    }
                    return true
                }
                .sorted()
        }

        if loadedSymbols.isEmpty {
            loadedSymbols = Self.curatedDockSymbols
        }
        self.allSymbols = loadedSymbols

        // 2. Load symbol -> categories mapping from symbol_categories.plist
        var catMap: [String: [String]] = [
            "dock_curated": Self.curatedDockSymbols
        ]
        if let symCatURL = bundle?.url(forResource: "symbol_categories", withExtension: "plist"),
           let symCatDict = NSDictionary(contentsOf: symCatURL) as? [String: [String]] {
            for symbol in loadedSymbols {
                if let cats = symCatDict[symbol] {
                    for cat in cats {
                        catMap[cat, default: []].append(symbol)
                    }
                }
            }
        }

        // 3. Load categories list from categories.plist
        var loadedCategories: [SFSymbolCategory] = [
            SFSymbolCategory(key: "dock_curated", label: "Dock Picks", icon: "sparkles"),
            SFSymbolCategory(key: "all", label: "All Symbols", icon: "square.grid.2x2")
        ]
        if let catsURL = bundle?.url(forResource: "categories", withExtension: "plist"),
           let catsArray = NSArray(contentsOf: catsURL) as? [[String: String]] {
            for entry in catsArray {
                guard let key = entry["key"],
                      key != "all",
                      key != "multicolor",
                      key != "variablecolor",
                      key != "whatsnew",
                      let symbolsInCat = catMap[key],
                      !symbolsInCat.isEmpty else {
                    continue
                }
                let icon = entry["icon"] ?? "square.grid.2x2"
                let label = Self.categoryDisplayLabels[key] ?? entry["label"] ?? key.capitalized
                loadedCategories.append(SFSymbolCategory(key: key, label: label, icon: icon))
            }
        }
        self.categories = loadedCategories
        self.symbolsByCategory = catMap

        // 4. Load semantic search keywords from symbol_search.plist
        if let searchURL = bundle?.url(forResource: "symbol_search", withExtension: "plist"),
           let searchDict = NSDictionary(contentsOf: searchURL) as? [String: [String]] {
            self.searchKeywordsBySymbol = searchDict
        } else {
            self.searchKeywordsBySymbol = [:]
        }
    }

    func symbols(inCategory categoryKey: String, matching query: String) -> [String] {
        let baseList: [String]
        if categoryKey == "all" {
            baseList = allSymbols
        } else {
            baseList = symbolsByCategory[categoryKey] ?? allSymbols
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return baseList }

        let terms = trimmed.split(separator: " ").map(String.init)
        // Search across all symbols when typing a query in Dock Picks so users find any system symbol immediately
        let searchPool = (categoryKey == "dock_curated") ? allSymbols : baseList

        return searchPool.filter { symbol in
            let lowerSymbol = symbol.lowercased()
            let keywords = searchKeywordsBySymbol[symbol] ?? []
            return terms.allSatisfy { term in
                lowerSymbol.contains(term) || keywords.contains(where: { $0.lowercased().contains(term) })
            }
        }
    }
}

// MARK: - SF Symbol Picker Popover View

struct SFSymbolPickerPopover: View {
    @Binding var selectedSymbol: String
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var selectedCategoryKey: String = "dock_curated"

    private var catalog: SFSymbolCatalog { SFSymbolCatalog.shared }
    private let gridColumns = [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 6)]

    private var filteredSymbols: [String] {
        catalog.symbols(inCategory: selectedCategoryKey, matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search \(catalog.allSymbols.count) macOS SF Symbols (e.g. code, folder, music)…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .accessibilityLabel("Search SF Symbols")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Category Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(catalog.categories) { category in
                        let isSelected = selectedCategoryKey == category.key
                        Button {
                            selectedCategoryKey = category.key
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 11))
                                Text(category.label)
                                    .font(.caption)
                                    .fontWeight(isSelected ? .semibold : .regular)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .help("Show \(category.label) symbols")
                        .accessibilityLabel("\(category.label) symbols")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            // Symbol Grid
            if filteredSymbols.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("No symbols matching “\(searchText)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        ForEach(filteredSymbols, id: \.self) { symbol in
                            let isCurrent = (selectedSymbol == symbol)
                            Button {
                                selectedSymbol = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 16))
                                    .frame(width: 38, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(isCurrent ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(symbol)
                            .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            // Footer with Selected Symbol Name & Done Button
            HStack {
                if !selectedSymbol.isEmpty {
                    Image(systemName: selectedSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(selectedSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(filteredSymbols.count) symbols")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 430, height: 380)
    }
}
