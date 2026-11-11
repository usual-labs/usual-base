import Foundation

/// The sidebar's icons: one per kind of file, and the icons a folder can wear.
enum FileIcons {
    static let folder = "lucide.folder"

    /// The icon for a file, from its extension.
    static func file(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return byExtension[ext] ?? "lucide.file"
    }

    /// A folder's icon: the one chosen for it if it's still offered, otherwise the default.
    static func folder(chosen: String?) -> String {
        guard let chosen, folderChoices.contains(where: { $0.icon == chosen }) else { return folder }
        return chosen
    }

    /// The icons offered for a folder, with their names in the menu. The first is the default.
    static let folderChoices: [(icon: String, title: String)] = [
        ("lucide.folder", "Folder"),
        ("lucide.code-xml", "Code"),
        ("lucide.calendar", "Calendar"),
        ("lucide.list-todo", "Tasks"),
        ("lucide.book-open", "Book"),
        ("lucide.flask-conical", "Research"),
        ("lucide.lightbulb", "Ideas"),
        ("lucide.pen-line", "Writing"),
        ("lucide.layout-grid", "Project"),
        ("lucide.wrench", "Tools"),
        ("lucide.rocket", "Launch"),
        ("lucide.target", "Goals"),
        ("lucide.briefcase", "Work"),
        ("lucide.wallet", "Money"),
        ("lucide.receipt", "Receipts"),
        ("lucide.landmark", "Bank and Tax"),
        ("lucide.house", "Home"),
        ("lucide.users", "People"),
        ("lucide.graduation-cap", "Learning"),
        ("lucide.globe", "Web"),
        ("lucide.bot", "Agents"),
        ("lucide.image", "Images"),
        ("lucide.inbox", "Inbox"),
        ("lucide.archive", "Archive"),
        ("lucide.lock", "Private"),
        ("lucide.heart", "Personal"),
        ("lucide.star", "Star"),
        ("lucide.music", "Music"),
        ("lucide.film", "Film"),
        ("lucide.camera", "Photos"),
        ("lucide.palette", "Design"),
        ("lucide.gamepad-2", "Games"),
        ("lucide.dumbbell", "Fitness"),
        ("lucide.utensils", "Food"),
        ("lucide.coffee", "Coffee"),
        ("lucide.leaf", "Nature"),
        ("lucide.paw-print", "Pets"),
        ("lucide.bike", "Travel"),
        ("lucide.map", "Places"),
        ("lucide.shopping-cart", "Shopping"),
        ("lucide.gift", "Gifts"),
        ("lucide.terminal", "Terminal"),
        ("lucide.database", "Data"),
        ("lucide.cloud", "Cloud"),
        ("lucide.chart-line", "Charts"),
        ("lucide.newspaper", "News"),
        ("lucide.mail", "Mail"),
        ("lucide.phone", "Contacts"),
    ]

    private static let byExtension: [String: String] = {
        var map: [String: String] = [:]
        func add(_ icon: String, _ extensions: String) {
            for ext in extensions.split(separator: " ") { map[String(ext)] = icon }
        }
        add("lucide.file-text", "md markdown")
        add("lucide.file-type", "pdf")
        add("lucide.file-pen-line", "txt rtf doc docx pages odt")
        add("lucide.file-image", "png jpg jpeg gif heic webp svg tif tiff bmp")
        add("lucide.file-video-camera", "mov mp4 m4v avi mkv webm")
        add("lucide.file-music", "mp3 m4a wav aiff flac ogg")
        add("lucide.file-spreadsheet", "csv tsv xls xlsx numbers ods")
        add("lucide.file-json", "json")
        add("lucide.file-braces", "yaml yml toml xml plist")
        add(
            "lucide.file-code",
            "swift js mjs ts tsx jsx py rb go rs c h cpp m java kt sh zsh bash html css scss sql")
        add("lucide.file-archive", "zip tar gz tgz bz2 xz 7z rar dmg")
        return map
    }()
}
