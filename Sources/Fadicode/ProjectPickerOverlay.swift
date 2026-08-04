import SwiftUI

/// Full-screen overlay listing projects from common directories.
/// Shown on new terminal — user picks a project and the terminal cd's there.
struct ProjectPickerOverlay: View {
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var currentPath: String
    @State private var projects: [ProjectEntry] = []
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isSearchFocused: Bool

    private let projectRoots: [String]

    /// Whether the current directory is one of the top-level project roots.
    /// At root level, clicking a directory selects it (cd into terminal).
    /// Deeper levels keep the drill-down behavior.
    private var isAtProjectRoot: Bool {
        projectRoots.contains(currentPath)
    }

    init(onSelect: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        let roots = ProjectRootSettings.roots()
        self.projectRoots = roots
        self._currentPath = State(initialValue: roots.first ?? FileManager.default.homeDirectoryForCurrentUser.path)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .onTapGesture { onDismiss() }
                .accessibilityLabel(String(localized: "projectPicker.a11y.dismissBackdrop", defaultValue: "Dismiss project picker"))
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                // Breadcrumb
                breadcrumb
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    TextField(String(localized: "projectPicker.search", defaultValue: "Search projects..."), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isSearchFocused)
                        .onSubmit { confirmSelection() }
                        .accessibilityLabel(String(localized: "projectPicker.a11y.searchField", defaultValue: "Search projects"))
                        .accessibilityAddTraits(.isSearchField)
                        .accessibilityValue(searchText.isEmpty
                            ? String(localized: "projectPicker.a11y.searchEmpty", defaultValue: "No filter applied")
                            : String(localized: "projectPicker.a11y.searchActive \(filteredProjects.count)", defaultValue: "\(filteredProjects.count) results for \(searchText)"))
                }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Project list
                if isLoading {
                    Spacer()
                    ProgressView()
                        .accessibilityLabel(String(localized: "projectPicker.a11y.loading", defaultValue: "Loading projects"))
                    Text(String(localized: "projectPicker.loading", defaultValue: "Scanning directory\u{2026}"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    Text(String(localized: "projectPicker.error.title", defaultValue: "Unable to load projects"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.top, 6)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 2)
                    Button(String(localized: "projectPicker.error.retry", defaultValue: "Retry")) {
                        loadProjects()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 8)
                    Spacer()
                } else if filteredProjects.isEmpty {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    if searchText.isEmpty {
                        Text(String(localized: "projectPicker.empty.title", defaultValue: "No projects found"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.top, 6)
                        Text(String(localized: "projectPicker.empty.subtitle \(currentPath)", defaultValue: "No items in \(currentPath)"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 2)
                    } else {
                        Text(String(localized: "projectPicker.empty.noResults", defaultValue: "No matching projects"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.top, 6)
                        Text(String(localized: "projectPicker.empty.noResultsHint \(searchText)", defaultValue: "No results for \"\(searchText)\""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { index, entry in
                                    projectRow(entry, isSelected: index == selectedIndex)
                                        .id(entry.id)
                                        .onTapGesture(count: 2) {
                                            // Double-click: always drill into directory
                                            if entry.isDirectory {
                                                navigateInto(entry)
                                            }
                                        }
                                        .onTapGesture {
                                            if entry.isDirectory {
                                                if isAtProjectRoot {
                                                    // At root: single-click opens project in terminal
                                                    selectProject(entry)
                                                } else {
                                                    // Deeper: single-click drills into folder
                                                    navigateInto(entry)
                                                }
                                            } else {
                                                selectProject(entry)
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .onChange(of: selectedIndex) { idx in
                            if let entry = filteredProjects[safe: idx] {
                                proxy.scrollTo(entry.id)
                            }
                        }
                    }
                }

                // Hint
                HStack {
                    Text(isAtProjectRoot
                        ? String(localized: "projectPicker.hint.openProject", defaultValue: "↵ Open project")
                        : String(localized: "projectPicker.hint.select", defaultValue: "↵ Select"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(String(localized: "projectPicker.hint.navigate", defaultValue: "↑↓ Navigate"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if isAtProjectRoot {
                        Text(String(localized: "projectPicker.hint.drillDown", defaultValue: "Tab Enter folder"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    if !isAtProjectRoot {
                        Text(String(localized: "projectPicker.hint.goBack", defaultValue: "⌫ Go back"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Text(String(localized: "projectPicker.hint.dismiss", defaultValue: "Esc Dismiss"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "projectPicker.a11y.hints", defaultValue: "Keyboard shortcuts: Return to select, arrow keys to navigate, Tab to enter folder, Backspace to go back, Escape to dismiss"))
            }
            .frame(width: 480, height: 400)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "projectPicker.a11y.container", defaultValue: "Project picker"))
            .accessibilityAction(.escape) { onDismiss() }
        }
        .onAppear {
            loadProjects()
            isSearchFocused = true
        }
        .onChange(of: currentPath) { _ in loadProjects() }
        .onChange(of: searchText) { _ in
            // Reset selection when search text changes so the highlight stays in bounds
            selectedIndex = 0
        }
        // Keyboard navigation — follows the same pattern as the command palette
        .backport.onKeyPress(.downArrow) { _ in
            moveSelection(by: 1)
            return .handled
        }
        .backport.onKeyPress(.upArrow) { _ in
            moveSelection(by: -1)
            return .handled
        }
        .backport.onKeyPress(.escape) { _ in
            onDismiss()
            return .handled
        }
        .backport.onKeyPress(.return) { _ in
            confirmSelection()
            return .handled
        }
        .backport.onKeyPress(.tab) { _ in
            // Tab drills into a directory without selecting it
            if let entry = filteredProjects[safe: selectedIndex], entry.isDirectory {
                navigateInto(entry)
                return .handled
            }
            return .ignored
        }
        .backport.onKeyPress(.delete) { _ in
            // Backspace navigates up when search is empty
            if searchText.isEmpty && !isAtProjectRoot {
                navigateUp()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Subviews

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            let components = breadcrumbComponents
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                Button(component.name) {
                    currentPath = component.path
                    selectedIndex = 0
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: index == components.count - 1 ? .semibold : .regular))
                .foregroundColor(index == components.count - 1 ? .primary : .secondary)
                .accessibilityLabel(String(localized: "projectPicker.a11y.breadcrumb \(component.name)", defaultValue: "Navigate to \(component.name)"))
                .accessibilityAddTraits(index == components.count - 1 ? .isSelected : [])
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "projectPicker.a11y.breadcrumbNav", defaultValue: "Breadcrumb navigation"))
    }

    private func projectRow(_ entry: ProjectEntry, isSelected: Bool) -> some View {
        let itemType = entry.isDirectory
            ? String(localized: "projectPicker.a11y.folder", defaultValue: "Folder")
            : String(localized: "projectPicker.a11y.file", defaultValue: "File")
        let action = entry.isDirectory
            ? (isAtProjectRoot
                ? String(localized: "projectPicker.a11y.actionOpen", defaultValue: "Activate to open project")
                : String(localized: "projectPicker.a11y.actionEnter", defaultValue: "Activate to enter folder"))
            : String(localized: "projectPicker.a11y.actionSelect", defaultValue: "Activate to select")

        return HStack(spacing: 10) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(entry.isDirectory ? .blue : .secondary)
                .font(.system(size: 14))
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let date = entry.modDate {
                    Text(date, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if entry.isDirectory {
                Image(systemName: isAtProjectRoot ? "terminal" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(itemType): \(entry.name)")
        .accessibilityHint(action)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Data

    private var filteredProjects: [ProjectEntry] {
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var breadcrumbComponents: [(name: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = currentPath
        var components: [(name: String, path: String)] = []
        while path != home && path != "/" {
            let name = (path as NSString).lastPathComponent
            components.insert((name: name, path: path), at: 0)
            path = (path as NSString).deletingLastPathComponent
        }
        components.insert((name: "~", path: home), at: 0)
        return components
    }

    private func loadProjects() {
        isLoading = true
        errorMessage = nil
        projects = []

        let fm = FileManager.default
        let path = currentPath

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let contents = try fm.contentsOfDirectory(atPath: path)
                let entries = contents
                    .filter { !$0.hasPrefix(".") }
                    .compactMap { name -> ProjectEntry? in
                        let fullPath = (path as NSString).appendingPathComponent(name)
                        var isDir: ObjCBool = false
                        guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { return nil }
                        let attrs = try? fm.attributesOfItem(atPath: fullPath)
                        let modDate = attrs?[.modificationDate] as? Date
                        return ProjectEntry(
                            name: name,
                            path: fullPath,
                            isDirectory: isDir.boolValue,
                            modDate: modDate
                        )
                    }
                    .sorted { ($0.modDate ?? .distantPast) > ($1.modDate ?? .distantPast) }

                DispatchQueue.main.async {
                    projects = entries
                    selectedIndex = 0
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    projects = []
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func navigateInto(_ entry: ProjectEntry) {
        currentPath = entry.path
        searchText = ""
        selectedIndex = 0
    }

    private func selectProject(_ entry: ProjectEntry) {
        onSelect(entry.path)
    }

    private func confirmSelection() {
        guard let entry = filteredProjects[safe: selectedIndex] else { return }
        if entry.isDirectory {
            if isAtProjectRoot {
                selectProject(entry)
            } else {
                navigateInto(entry)
            }
        } else {
            selectProject(entry)
        }
    }

    private func moveSelection(by delta: Int) {
        let count = filteredProjects.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func navigateUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != currentPath else { return }
        currentPath = parent
        searchText = ""
        selectedIndex = 0
    }
}

// MARK: - Model

private struct ProjectEntry: Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    let modDate: Date?
    var id: String { path }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
