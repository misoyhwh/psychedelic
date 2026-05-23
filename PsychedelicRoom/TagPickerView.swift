import SwiftUI

struct TagPickerView: View {
    @Environment(AppModel.self) private var appModel

    @State private var query: String = ""
    @State private var suggestions: [IllustServerTag] = []
    @State private var popularByNamespace: [String: [IllustServerTag]] = [:]
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedNamespace: String = "character"

    private let namespaces: [String] = ["character", "series", "general", "artist"]
    private let popularPerNamespace: Int = 90  // 30 → 90 (各カテゴリ 3 倍表示)
    private let gridColumns: [GridItem] = [GridItem(.adaptive(minimum: 140), spacing: 6)]

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tag.fill")
                Text("タグ選択")
                    .font(.title2)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await loadPopular() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("人気タグを再読み込み")
            }

            selectedTagsSection

            Divider()

            TextField("タグを検索 (例: frieren, miku)", text: $query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    runSearch(newValue)
                }

            if let err = loadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            ScrollView {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResultsSection
                } else {
                    popularSection
                }
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 600)
        .task {
            if popularByNamespace.isEmpty {
                await loadPopular()
            }
        }
    }

    // MARK: - Sections

    private var selectedTagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("選択中 (\(selectedSet.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !selectedSet.isEmpty {
                    Button("すべて解除") {
                        appModel.illustServerLastTags = ""
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            if selectedSet.isEmpty {
                Text("検索/人気タグから選択してください。メインウィンドウの「サーバ検索」で適用されます。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 6) {
                    ForEach(selectedSet.sorted(), id: \.self) { tag in
                        chip(label: tag, selected: true) {
                            toggleTag(tag)
                        }
                    }
                }
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // カテゴリ切替タブ
            Picker("カテゴリ", selection: $selectedNamespace) {
                ForEach(namespaces, id: \.self) { ns in
                    Text(tabLabel(for: ns)).tag(ns)
                }
            }
            .pickerStyle(.segmented)

            // 選択中カテゴリのタグ表示
            let currentTags = popularByNamespace[selectedNamespace] ?? []
            HStack {
                Text(displayName(for: selectedNamespace))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("(\(currentTags.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            if currentTags.isEmpty {
                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("読み込み中…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("このカテゴリのタグはまだありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 6) {
                    ForEach(currentTags) { tag in
                        let key = tagKey(tag)
                        chip(
                            label: "\(tag.name) (\(tag.count))",
                            selected: selectedSet.contains(key)
                        ) {
                            toggleTag(key)
                        }
                    }
                }
            }

            if popularByNamespace.values.allSatisfy({ $0.isEmpty }) && !isLoading {
                Text("人気タグが取得できませんでした。サーバ URL を確認してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tabLabel(for ns: String) -> String {
        switch ns {
        case "character": return "キャラ"
        case "series": return "シリーズ"
        case "general": return "一般"
        case "artist": return "作者"
        default: return ns
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if suggestions.isEmpty && !isLoading {
                Text("該当なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 6) {
                ForEach(suggestions) { tag in
                    let key = tagKey(tag)
                    chip(
                        label: "\(tag.namespace):\(tag.name) (\(tag.count))",
                        selected: selectedSet.contains(key)
                    ) {
                        toggleTag(key)
                    }
                }
            }
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                }
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .secondary)
    }

    // MARK: - State helpers

    private var selectedSet: Set<String> {
        Set(appModel.illustServerLastTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        )
    }

    private func tagKey(_ tag: IllustServerTag) -> String {
        "\(tag.namespace):\(tag.name)"
    }

    private func toggleTag(_ key: String) {
        var set = selectedSet
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
        appModel.illustServerLastTags = set.sorted().joined(separator: ", ")
    }

    private func displayName(for ns: String) -> String {
        switch ns {
        case "character": return "キャラクター (character)"
        case "series": return "シリーズ (series)"
        case "general": return "一般 (general)"
        case "artist": return "作者 (artist)"
        default: return ns
        }
    }

    // MARK: - Networking

    private func loadPopular() async {
        guard let client = IllustServerClient.from(host: appModel.illustServerHost) else {
            loadError = "サーバ URL が無効です"
            return
        }
        isLoading = true
        loadError = nil

        // 並列で 4 namespace を取得
        async let character = (try? await client.popularTags(namespace: "character", limit: popularPerNamespace)) ?? []
        async let series = (try? await client.popularTags(namespace: "series", limit: popularPerNamespace)) ?? []
        async let general = (try? await client.popularTags(namespace: "general", limit: popularPerNamespace)) ?? []
        async let artist = (try? await client.popularTags(namespace: "artist", limit: popularPerNamespace)) ?? []

        let result: [String: [IllustServerTag]] = await [
            "character": character,
            "series": series,
            "general": general,
            "artist": artist,
        ]
        popularByNamespace = result
        isLoading = false
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }
        guard let client = IllustServerClient.from(host: appModel.illustServerHost) else {
            loadError = "サーバ URL が無効です"
            return
        }
        searchTask = Task {
            // 250ms デバウンス
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                let tags = try await client.suggestTags(query: trimmed, limit: 50)
                if !Task.isCancelled {
                    suggestions = tags
                }
            } catch {
                if !Task.isCancelled {
                    // 個別の検索失敗はトップレベルエラーにせず黙って空に
                    suggestions = []
                }
            }
        }
    }
}
