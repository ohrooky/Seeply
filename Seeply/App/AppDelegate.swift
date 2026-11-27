import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var viewers: [UUID: ViewerWindowController] = [:]
    private var settingsWindow: NSWindow?
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var openedBeforeLaunch = false
    private var languageSubscription: AnyCancellable?
    private var displayedLanguage: InterfaceLanguage?

    var activeViewer: ViewerWindowController? {
        (NSApp.keyWindow?.windowController as? ViewerWindowController)
            ?? (NSApp.mainWindow?.windowController as? ViewerWindowController)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        displayedLanguage = L10n.language
        languageSubscription = Preferences.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshLanguageIfNeeded() }
        }
        if !openedBeforeLaunch { newViewer() }
        NSApp.activate(ignoringOtherApps: true)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { Task { await ImagePipeline.shared.clear(); await MetadataService.shared.clear(); await PaletteService.shared.clear() } }
        source.resume()
        memoryPressure = source
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedBeforeLaunch = true
        let viewer = activeViewer.flatMap { $0.session.items.isEmpty ? $0 : nil } ?? newViewer()
        viewer.session.open(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newViewer() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @discardableResult
    func newViewer() -> ViewerWindowController {
        let viewer = ViewerWindowController()
        viewers[viewer.session.id] = viewer
        viewer.onClosed = { [weak self] id in self?.viewers.removeValue(forKey: id) }
        viewer.session.onDemo = { [weak viewer] in viewer?.openDemo() }
        viewer.session.onFileTypeSettings = { [weak self] in
            Preferences.shared.settingsTab = .fileTypes
            self?.showSettings(nil)
        }
        viewer.showWindow(nil)
        return viewer
    }

    @objc private func newWindow(_ sender: Any?) { newViewer() }
    @objc private func openImages(_ sender: Any?) { (activeViewer ?? newViewer()).openPanel(folder: false) }
    @objc private func openFolder(_ sender: Any?) { (activeViewer ?? newViewer()).openPanel(folder: true) }
    @objc private func openDemo(_ sender: Any?) { (activeViewer ?? newViewer()).openDemo() }
    @objc private func closeWindow(_ sender: Any?) {
        if let viewer = NSApp.keyWindow?.windowController as? ViewerWindowController { viewer.close() }
        else { NSApp.keyWindow?.close() }
    }
    @objc private func showAbout(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(sender) }

    @objc private func showSettings(_ sender: Any?) {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.text("Seeply Settings")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func viewerCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String, let viewer = activeViewer else { return }
        let session = viewer.session
        switch command {
        case "previous": session.navigate(-1)
        case "next": session.navigate(1)
        case "first": session.select(0)
        case "last": session.select(session.items.count - 1)
        case "fit": session.viewport.fit()
        case "actual": session.viewport.actualSize()
        case "zoomIn": session.viewport.setZoom(session.viewport.zoom * 1.25)
        case "zoomOut": session.viewport.setZoom(session.viewport.zoom / 1.25)
        case "rotate": session.rotate()
        case "windowFit": viewer.fitWindow()
        case "restoreWindow": viewer.restoreWindow()
        case "lightbox": viewer.toggleLightbox()
        case "frameless": viewer.toggleFrameless()
        case "fullscreen": viewer.toggleFullscreen()
        case "inspector": session.toggleInspector()
        case "summary": Preferences.shared.showSummary.toggle()
        case "palette": Preferences.shared.showPalette.toggle()
        case "filmstrip": session.showFilmstrip.toggle()
        case "grid": session.showGrid.toggle()
        case "reveal": session.revealInFinder()
        case "copyImage": session.copyImage()
        case "copyMetadata": if let metadata = session.metadata { Theme.copy(metadata.copyText(language: L10n.language)) }
        case "refresh": session.refresh()
        default: break
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.representedObject as? String else { return true }
        guard let viewer = activeViewer else { return false }
        let session = viewer.session
        let toggles: [String: Bool] = ["lightbox": session.isLightbox, "frameless": session.isFrameless,
                                      "fullscreen": session.isFullscreen, "inspector": session.showInspector,
                                      "filmstrip": session.showFilmstrip, "grid": session.showGrid,
                                      "summary": Preferences.shared.showSummary, "palette": Preferences.shared.showPalette]
        if let value = toggles[command] { menuItem.state = value ? .on : .off }
        if ["previous", "next", "first", "last", "grid"].contains(command) { return session.items.count > 1 }
        if command == "windowFit" { return session.image != nil && !session.isFullscreen }
        if command == "copyMetadata" { return session.metadata != nil }
        if ["rotate", "actual", "fit", "zoomIn", "zoomOut", "copyImage"].contains(command) { return session.image != nil }
        if ["reveal", "refresh"].contains(command) { return session.current != nil }
        return true
    }

    private func buildMenus() {
        let main = NSMenu()
        let appMenu = submenu("Seeply", in: main)
        item("About Seeply", action: #selector(showAbout), in: appMenu)
        appMenu.addItem(.separator())
        item("Settings…", key: ",", action: #selector(showSettings), in: appMenu)
        appMenu.addItem(.separator())
        let services = submenu("Services", in: appMenu)
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        let hide = item("Hide Seeply", key: "h", action: #selector(NSApplication.hide(_:)), in: appMenu); hide.target = NSApp
        let hideOthers = item("Hide Others", key: "h", modifiers: [.command, .option], action: #selector(NSApplication.hideOtherApplications(_:)), in: appMenu); hideOthers.target = NSApp
        let unhide = item("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), in: appMenu); unhide.target = NSApp
        appMenu.addItem(.separator())
        let quit = item("Quit Seeply", key: "q", action: #selector(NSApplication.terminate(_:)), in: appMenu); quit.target = NSApp

        let file = submenu("File", in: main)
        item("New Window", key: "n", action: #selector(newWindow), in: file)
        item("Open Images…", key: "o", action: #selector(openImages), in: file)
        item("Open Folder…", key: "o", modifiers: [.command, .shift], action: #selector(openFolder), in: file)
        item("Open Demo Images", action: #selector(openDemo), in: file)
        file.addItem(.separator())
        command("Reload", "refresh", key: "r", in: file)
        command("Show in Finder", "reveal", key: "r", modifiers: [.command, .shift], in: file)
        file.addItem(.separator())
        item("Close Window", key: "w", action: #selector(closeWindow), in: file)

        let edit = submenu("Edit", in: main)
        let copy = item("Copy", key: "c", action: #selector(NSText.copy(_:)), in: edit); copy.target = nil
        let selectAll = item("Select All", key: "a", action: #selector(NSText.selectAll(_:)), in: edit); selectAll.target = nil
        edit.addItem(.separator())
        command("Copy Displayed Image", "copyImage", key: "c", modifiers: [.command, .shift], in: edit)
        command("Copy Photo Details", "copyMetadata", key: "c", modifiers: [.command, .option], in: edit)

        let view = submenu("View", in: main)
        command("Fit Image to Window", "fit", key: "0", in: view)
        command("Actual Pixels (100%)", "actual", key: "1", in: view)
        command("Zoom In", "zoomIn", key: "=", in: view)
        command("Zoom Out", "zoomOut", key: "-", in: view)
        command("Rotate Clockwise", "rotate", key: "r", modifiers: [.command, .option], in: view)
        view.addItem(.separator())
        command("Fit Window to Image", "windowFit", key: "2", in: view)
        command("Restore Window Size", "restoreWindow", in: view)
        view.addItem(.separator())
        command("Lightbox", "lightbox", key: "l", in: view)
        command("Frameless", "frameless", key: "b", in: view)
        command("Full Screen", "fullscreen", key: "f", modifiers: [.command, .control], in: view)
        view.addItem(.separator())
        command("Photo Info", "inspector", key: "i", in: view)
        command("Quick EXIF", "summary", key: "i", modifiers: [.command, .shift], in: view)
        command("Color Palette", "palette", key: "p", modifiers: [.command, .shift], in: view)
        command("Filmstrip", "filmstrip", key: "t", in: view)
        command("Contact Sheet", "grid", key: "g", in: view)

        let window = submenu("Window", in: main)
        let minimize = item("Minimize", key: "m", action: #selector(NSWindow.performMiniaturize(_:)), in: window); minimize.target = nil
        let front = item("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), in: window); front.target = NSApp
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: L10n.text(title), action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(rawValue: "seeply.l10n." + title)
        let menu = NSMenu(title: L10n.text(title))
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    @discardableResult
    private func item(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command],
                      action: Selector, in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.text(title), action: action, keyEquivalent: key)
        item.identifier = NSUserInterfaceItemIdentifier(rawValue: "seeply.l10n." + title)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        menu.addItem(item)
        return item
    }

    private func refreshLanguageIfNeeded() {
        guard displayedLanguage != L10n.language else { return }
        displayedLanguage = L10n.language
        if let menu = NSApp.mainMenu { relabel(menu) }
        settingsWindow?.title = L10n.text("Seeply Settings")
        for viewer in viewers.values { viewer.refreshLocalization() }
    }

    private func relabel(_ menu: NSMenu) {
        let prefix = "seeply.l10n."
        for item in menu.items {
            if let identifier = item.identifier?.rawValue, identifier.hasPrefix(prefix) {
                item.title = L10n.text(String(identifier.dropFirst(prefix.count)))
                item.submenu?.title = item.title
            }
            // AppKit's dynamic Window and Services entries have no localization
            // identifier. Preserve them, their targets and all current menu state.
            if let submenu = item.submenu { relabel(submenu) }
        }
    }

    private func command(_ title: String, _ name: String, key: String = "",
                         modifiers: NSEvent.ModifierFlags = [.command], in menu: NSMenu) {
        let menuItem = item(title, key: key, modifiers: modifiers, action: #selector(viewerCommand), in: menu)
        menuItem.representedObject = name
    }
}
