import Foundation

enum InterfaceLanguage: String, Sendable, CaseIterable, Hashable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    static func systemDefault(preferredLanguages: [String]) -> Self {
        // The user's primary language decides. A secondary Chinese preference
        // must not turn an English/Japanese/etc. primary language into Chinese.
        guard let primary = preferredLanguages.first else { return .english }
        let parts = primary.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
        guard let language = parts.first, ["zh", "cmn", "yue"].contains(String(language)) else { return .english }
        if parts.count > 1, parts[1].count == 4 {
            return parts[1] == "hant" ? .traditionalChinese : .english
        }
        return parts.dropFirst().contains(where: { ["tw", "hk", "mo"].contains(String($0)) }) ? .traditionalChinese : .english
    }
}

enum LanguagePreference: String, CaseIterable, Identifiable, Sendable, Hashable {
    case system
    case traditionalChinese = "zh-Hant"
    case english = "en"
    var id: String { rawValue }

    func resolved(preferredLanguages: [String]) -> InterfaceLanguage {
        switch self {
        case .system: return .systemDefault(preferredLanguages: preferredLanguages)
        case .traditionalChinese: return .traditionalChinese
        case .english: return .english
        }
    }
}

/// Locale-neutral text for cached metadata and asynchronous errors. Literal
/// filenames, camera names and raw EXIF values are never treated as translations.
enum DisplayText: Sendable, Equatable {
    case literal(String)
    case key(String, [String: String] = [:])

    var identifier: String {
        switch self { case .literal(let text): return "raw:" + text; case .key(let key, _): return key }
    }

    func resolved(in language: InterfaceLanguage) -> String {
        switch self {
        case .literal(let text): return text
        case .key(let key, let arguments): return StringCatalog.text(key, language: language, arguments: arguments)
        }
    }

    static func error(_ error: Error) -> Self {
        (error as? any PresentableError)?.displayText ?? .literal(error.localizedDescription)
    }
}

protocol PresentableError: LocalizedError {
    var displayText: DisplayText { get }
}

extension PresentableError {
    var errorDescription: String? { displayText.resolved(in: .english) }
}

/// English is the source language and the unconditional fallback. These are
/// manual localizations, declared by CFBundleLocalizations in Info.plist.
enum StringCatalog {
    static let traditionalChinese: [String: String] = [
        "General": "一般", "Language": "語系", "Follow System": "跟隨系統",
        "Traditional Chinese": "繁體中文", "English": "English",
        "Traditional Chinese is used for a Traditional Chinese system; English otherwise.": "繁體中文系統使用繁中，其餘系統語言使用英文。",
        "Seeply Settings": "Seeply 設定", "Viewing": "看圖", "Canvas background": "畫布背景",
        "Graphite": "石墨灰", "Black": "純黑", "Paper": "紙白",
        "Allow small images to fill the window": "允許將小圖片放大至視窗",
        "Keep zoom when changing images": "換圖時保留縮放倍率",
        "Loop from the last image to the first": "最後一張接回第一張",
        "Show the EXIF summary": "在畫面下方顯示拍攝摘要",
        "Show the color palette": "顯示主色調色票", "Cache": "快取",
        "Image caches are kept in memory only.": "影像快取只保留在記憶體中。",
        "Clearing…": "正在清除…", "Cleared": "已清除", "Clear Cache": "清除快取",
        "About Seeply": "關於 Seeply", "Settings…": "設定…", "Services": "服務",
        "Hide Seeply": "隱藏 Seeply", "Hide Others": "隱藏其他", "Show All": "全部顯示", "Quit Seeply": "結束 Seeply",
        "File": "檔案", "New Window": "新增視窗", "Open Images…": "開啟圖片…",
        "Open Folder…": "開啟資料夾…", "Open Demo Images": "開啟示範圖片", "Reload": "重新讀取",
        "Show in Finder": "在 Finder 顯示", "Close Window": "關閉視窗", "Edit": "編輯",
        "Copy": "複製", "Select All": "全選", "Copy Displayed Image": "複製目前顯示的圖片",
        "Copy Photo Details": "複製拍攝資訊", "View": "顯示", "Fit Image to Window": "圖片縮放至視窗",
        "Actual Pixels (100%)": "原始像素 100%", "Zoom In": "放大", "Zoom Out": "縮小",
        "Rotate Clockwise": "順時針旋轉", "Fit Window to Image": "視窗配合圖片", "Restore Window Size": "還原視窗大小",
        "Lightbox": "Lightbox", "Frameless": "Frameless", "Full Screen": "全螢幕", "Photo Info": "照片資訊",
        "Quick EXIF": "簡易 EXIF", "Color Palette": "主色調色票", "Filmstrip": "縮圖列", "Contact Sheet": "縮圖總覽",
        "Window": "視窗", "Minimize": "縮到最小", "Bring All to Front": "全部移至最前",
        "Palette": "主色調", "Analyzing…": "分析中…", "No colors to display": "沒有可顯示的色彩",
        "Currently unavailable": "暫時無法顯示", "Copy All Color Codes": "複製全部色碼",
        "Hide Color Palette": "隱藏主色調色票", "Photo color palette": "照片主色調色票",
        "Copied {hex}": "已複製 {hex}", "{hex} · ~{percent}% · Click to copy": "{hex} · 約 {percent}% · 點擊複製",
        "{hex}, click to copy color code": "{hex}，點擊複製色碼",
        "Hide Info · I": "隱藏資訊 · I", "All Metadata": "所有中繼資料", "Reading details…": "正在讀取資訊…",
        "Open an image to see its details.": "開啟圖片後，即可查看拍攝資訊。",
        "Aperture": "光圈", "Shutter": "快門", "ISO": "ISO",
        "Image viewing area": "照片檢視區",
        "Arrow keys navigate; 0 fits the image, 1 shows actual pixels, I opens photo info.": "方向鍵換圖，0 縮放至視窗，1 原始像素，I 顯示拍攝資訊。",
        "Close Window · ⌘W": "關閉視窗 · ⌘W", "Open Images · ⌘O": "開啟圖片 · ⌘O",
        "Previous Image · ←": "上一張 · ←", "Next Image · →": "下一張 · →",
        "Fit Image to Window · 0": "圖片縮放至視窗 · 0", "Photo Info · I": "照片資訊 · I",
        "Fit Image to Window    0": "圖片縮放至視窗    0", "Actual Pixels (100%)    1": "原始像素 100%    1",
        "Fit Window to Image    W": "視窗配合圖片    W", "Rotate Clockwise    R": "順時針旋轉    R",
        "Toggle Full Screen    F": "切換全螢幕    F", "Filmstrip    T": "縮圖列    T", "Contact Sheet    G": "縮圖總覽    G",
        "Quick EXIF    E": "簡易 EXIF    E", "Color Palette    P": "主色調色票    P", "More Options": "更多選項",
        "Browse This Folder": "瀏覽同資料夾",
        "Decoding resolution is limited for this large image to control memory use.": "大型影像已限制解碼解析度，以控制記憶體用量。",
        "← → Navigate": "← → 換圖", "{name}, current image": "{name}，目前圖片",
        "1 image": "1 張圖片", "{count} images": "{count} 張圖片", "Back to Image · Esc": "返回看圖 · Esc",
        "Unable to read the dropped files. Try dropping them again, or choose Open Images.": "無法讀取拖入的檔案。請重新拖放，或使用「開啟圖片」。",
        "Unable to Open Image": "無法開啟圖片", "Close": "關閉", "Choose Again…": "重新選取…",
        "Open a photo.": "打開一張照片。", "Drop a photo or folder and let the image take center stage.": "拖入照片或資料夾，讓影像成為主角。",
        "Open Images": "開啟圖片", "Open Folder": "開啟資料夾", "Try the demo images": "先看看示範圖片",
        "Open": "開啟", "Navigate": "換圖", "Info": "資訊", "IMAGE VIEWER": "圖片瀏覽器",
        "Grant access to a folder to browse its images with the arrow keys.": "授權資料夾後，即可使用方向鍵瀏覽其中的圖片。",
        "Select one or more images.": "選取一張或多張圖片。",
        "The demo images could not be found. Reinstall the app, or use Open Images to view your own photos.": "找不到內建示範圖片。請重新安裝應用程式，或使用「開啟圖片」瀏覽自己的照片。",
        "Unable to decode “{name}”. This format may be unsupported by this version of macOS, or the file may be damaged.": "無法解碼「{name}」。這個格式可能不受目前 macOS 支援，或檔案已損壞。",
        "Unable to read “{name}”. Check that it still exists and grant access to its folder again.": "無法讀取「{name}」。請確認檔案仍然存在，並重新授權所在資料夾。",
        "This folder contains no images that can be displayed.": "這個資料夾內沒有可顯示的圖片。",
        "The color palette is temporarily unavailable for this photo.": "暫時無法分析這張照片的主色調。",
        "Auto": "自動", "Manual": "手動", "Fired": "已閃光", "Did not fire": "未閃光",
        "Unspecified": "未指定", "Average": "平均", "Center-weighted": "中央重點", "Spot": "點測光",
        "Multi-spot": "多點", "Multi-segment": "多分區", "Partial": "局部", "Other": "其他", "Mode {mode}": "模式 {mode}",
        "Equipment": "器材", "Camera": "相機", "Lens": "鏡頭", "Capture": "拍攝",
        "Focal length": "焦距", "35mm equiv.": "等效焦距", "Exp. comp.": "曝光補償", "White bal.": "白平衡",
        "Metering": "測光", "Flash": "閃光燈", "Captured": "拍攝時間", "Image & File": "影像與檔案",
        "File name": "檔名", "Dimensions": "尺寸", "File size": "大小", "Format": "格式",
        "Color profile": "色彩描述檔", "Bit depth": "位元深度", "Location": "位置", "Latitude": "緯度", "Longitude": "經度",
        "{label}: {value}": "{label}：{value}",
        "File Types": "檔案類型", "Select None": "全不選", "Common Images": "常見圖片", "RAW Only": "只看 RAW",
        "Other RAW": "其他 RAW", "Other supported formats": "其他支援格式",
        "Only selected formats are included when opening files or browsing folders.": "開啟檔案或瀏覽資料夾時，只讀取已勾選的格式。",
        "Changes apply to all open windows and are saved automatically.": "變更會立即套用至所有視窗，並自動保存。",
        "Format support depends on macOS.": "實際可開啟的格式取決於 macOS 支援。",
        "{count} of {total} types selected": "已選取 {count} / {total} 種類型",
        "No file types selected.": "尚未選取任何檔案類型。",
        "No images match your file types": "沒有符合所選格式的圖片",
        "Choose different file types in Settings to continue browsing.": "請在設定調整檔案類型，繼續瀏覽。",
        "File Type Settings…": "檔案類型設定…", "Show All Types": "顯示所有類型",
        "Select one or more enabled image types.": "選取一張或多張已啟用格式的圖片。",
        "Additional image formats supported by macOS.": "macOS 支援的其他影像格式。"
    ]

    static func text(_ key: String, language: InterfaceLanguage, arguments: [String: String] = [:]) -> String {
        let template = language == .traditionalChinese ? traditionalChinese[key] ?? key : key
        // Scan the template once: braces inside filenames or other argument values
        // are copied literally and can never become a second formatting operation.
        var result = ""
        var remainder = template[...]
        while let start = remainder.firstIndex(of: "{"), let end = remainder[start...].firstIndex(of: "}") {
            result += remainder[..<start]
            let name = String(remainder[remainder.index(after: start)..<end])
            result += arguments[name] ?? String(remainder[start...end])
            remainder = remainder[remainder.index(after: end)...]
        }
        result += remainder
        return result
    }
}
