import SwiftUI
import AppKit
import Foundation
import Combine
import LocalAuthentication
import FoundationModels

extension String {
    func addingPercentEncodingForQuery() -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?&=+#")
        return self.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

func logDebug(_ message: String) {
    let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".brewdeck_debug.log").path
    let timestamp = Date().description
    let logLine = "[\(timestamp)] \(message)\n"
    if let data = logLine.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}

// --- MODELS ---

struct BrewPackage: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var type: String // "cask" or "formula"
    var description: String
    var homepage: String
    var version: String
    var installedVersion: String?
    var size: String = "Unknown"
    var hasUpdate: Bool {
    guard let inst = installedVersion else { return false }
    func parse(_ v: String) -> (String, Int) {
        let parts = v.split(separator: "_")
        let base = String(parts[0])
        let rev = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (base, rev)
    }
    let (instBase, instRev) = parse(inst)
    let (availBase, availRev) = parse(version)
    if instBase != availBase {
        return instBase.compare(availBase, options: .numeric) == .orderedAscending
    }
    return instRev < availRev
}



    
    var rating: Double {
        if let saved = UserDefaults.standard.value(forKey: "custom_rating_\(id)") as? Double {
            return saved
        }
        let hash = abs(id.hashValue)
        let score = 4.3 + Double(hash % 7) * 0.1
        return Double(String(format: "%.1f", score)) ?? 4.5
    }
    
    var ratingCount: String {
        let hash = abs(id.hashValue)
        let count = 12 + (hash % 188)
        if count >= 100 {
            return "\(count)K"
        } else {
            return "\(count),\(hash % 9)00"
        }
    }
    
    var category: AppCategory {
        let nameLower = name.lowercased()
        let idLower = id.lowercased()
        let descLower = description.lowercased()
        
        if nameLower.contains("code") || nameLower.contains("developer") || nameLower.contains("studio") ||
           idLower.contains("git") || idLower.contains("docker") || idLower.contains("python") || idLower.contains("node") ||
           idLower.contains("sublime") || idLower.contains("intellij") || idLower.contains("xcode") ||
           descLower.contains("compiler") || descLower.contains("editor") || descLower.contains("ide") || descLower.contains("development") {
            return .developer
        }
        
        if nameLower.contains("figma") || nameLower.contains("design") || nameLower.contains("sketch") ||
           nameLower.contains("photoshop") || nameLower.contains("blender") || nameLower.contains("canva") ||
           descLower.contains("editor for images") || descLower.contains("graphic") || descLower.contains("drawing") || descLower.contains("3d") {
            return .creative
        }
        
        if nameLower.contains("discord") || nameLower.contains("slack") || nameLower.contains("telegram") ||
           nameLower.contains("chat") || nameLower.contains("zoom") || nameLower.contains("teams") ||
           descLower.contains("messenger") || descLower.contains("chat") || descLower.contains("communication") {
            return .communication
        }
        
        if nameLower.contains("spotify") || nameLower.contains("music") || nameLower.contains("video") ||
           nameLower.contains("vlc") || nameLower.contains("player") || nameLower.contains("plex") ||
           descLower.contains("stream") || descLower.contains("audio") || descLower.contains("media") {
            return .entertainment
        }
        
        if nameLower.contains("arc") || nameLower.contains("browser") || nameLower.contains("raycast") ||
           nameLower.contains("alfred") || nameLower.contains("rectangle") || nameLower.contains("stats") ||
           descLower.contains("utility") || descLower.contains("productivity") || descLower.contains("tool") || descLower.contains("browser") {
            return .productivity
        }
        
        return .other
    }
}

enum AppCategory: String, CaseIterable, Identifiable, Codable {
    case developer = "Developer Tools"
    case creative = "Design & Creative"
    case productivity = "Productivity & Utilities"
    case communication = "Social & Communication"
    case entertainment = "Entertainment & Media"
    case other = "Other Packages"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .developer: return "hammer.fill"
        case .creative: return "paintpalette.fill"
        case .productivity: return "checklist"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .entertainment: return "play.tv.fill"
        case .other: return "shippingbox.fill"
        }
    }
}

// --- THREAD LANES ---

class ThreadLane: ObservableObject, Identifiable {
    let id: Int
    @Published var activeRunningId: String? = nil
    @Published var activePkg: BrewPackage? = nil
    @Published var logs: [String] = []
    @Published var isRunning: Bool = false
    var process: Process? = nil
    
    init(id: Int) {
        self.id = id
    }
}

// --- COdABLE SCHEMAS FOR BREW JSON ---

struct BrewInfoResponse: Codable {
    let casks: [CaskInfo]
    let formulae: [FormulaInfo]
}

struct CaskInfo: Codable {
    let token: String
    let name: [String]
    let desc: String?
    let homepage: String?
    let installed: String?
    let version: String
}

struct FormulaInfo: Codable {
    let name: String
    let desc: String?
    let homepage: String?
    let installed: [FormulaInstalled]?
    let versions: FormulaVersions?
}

struct FormulaInstalled: Codable {
    let version: String
}

struct FormulaVersions: Codable {
    let stable: String?
}

struct OutdatedResponse: Codable {
    let casks: [OutdatedItem]
    let formulae: [OutdatedItem]
}

struct OutdatedItem: Codable {
    let name: String
    let installed_versions: [String]
    let current_version: String
}

struct CaskAPIItem: Codable {
    let token: String
    let name: [String]
    let desc: String?
    let homepage: String?
    let version: String
}

// --- QUEUE SYSTEM & STATE MANAGER ---

class BrewManager: ObservableObject {
    @Published var packages: [BrewPackage] = []
    @Published var threads: [ThreadLane] = [
        ThreadLane(id: 1),
        ThreadLane(id: 2),
        ThreadLane(id: 3)
    ]
    @Published var pendingInstallQueue: [QueueItem] = []
    @Published var allCasksLoading: Bool = false
    @Published var allCasksLoaded: Bool = false
    @Published var isLoadingLocal: Bool = false
    @Published var hiddenCategories: Set<String> = []
    @Published var recommendedPackages: [BrewPackage] = []
    
    func hideCategory(_ category: String) {
        hiddenCategories.insert(category)
        UserDefaults.standard.set(Array(hiddenCategories), forKey: "hidden_categories")
        logDebug("Category hidden: \(category). Persisted: \(hiddenCategories)")
    }
    
    func showAllCategories() {
        hiddenCategories.removeAll()
        UserDefaults.standard.removeObject(forKey: "hidden_categories")
        logDebug("All categories restored.")
    }
    
    func refreshRecommendations(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        let lastTime = UserDefaults.standard.double(forKey: "recommendation_timestamp")
        
        if !force && (now - lastTime < 86400) {
            // Load from cache
            if let storedIds = UserDefaults.standard.stringArray(forKey: "recommended_package_ids") {
                let cached = self.packages.filter { storedIds.contains($0.id) }
                if !cached.isEmpty {
                    DispatchQueue.main.async {
                        self.recommendedPackages = cached
                    }
                    logDebug("Loaded \(cached.count) recommended packages from daily cache.")
                    return
                }
            }
        }
        
        // Run recommendation algorithm
        let installed = self.packages.filter { $0.installedVersion != nil }
        var categoryScores: [AppCategory: Int] = [:]
        for pkg in installed {
            categoryScores[pkg.category, default: 0] += 1
        }
        
        // Filter out already installed packages
        let candidates = self.packages.filter { $0.installedVersion == nil }
        guard !candidates.isEmpty else { return }
        
        // Use calendar start of day to seed daily noise
        let dateHash = abs(Calendar.current.startOfDay(for: Date()).hashValue)
        
        struct ScoredPkg {
            let pkg: BrewPackage
            let score: Double
        }
        
        var scored: [ScoredPkg] = []
        for pkg in candidates {
            let baseScore = pkg.rating
            let categoryBonus = Double(categoryScores[pkg.category, default: 0]) * 2.0
            
            // Generate stable daily noise between 0.0 and 1.5
            let seed = abs(pkg.id.hashValue ^ dateHash)
            let dailyNoise = Double(seed % 150) / 100.0
            
            let totalScore = baseScore + categoryBonus + dailyNoise
            scored.append(ScoredPkg(pkg: pkg, score: totalScore))
        }
        
        // Sort descending and take top 6
        scored.sort { $0.score > $1.score }
        let top = Array(scored.prefix(6)).map { $0.pkg }
        
        DispatchQueue.main.async {
            self.recommendedPackages = top
        }
        
        // Save to cache
        let topIds = top.map { $0.id }
        UserDefaults.standard.set(topIds, forKey: "recommended_package_ids")
        UserDefaults.standard.set(now, forKey: "recommendation_timestamp")
        logDebug("Calculated new personalized recommendations. Recommended: \(topIds)")
    }
    
    // For mid-execution sudo password popups
    @Published var isSudoModalOpen: Bool = false
    @Published var sudoInputPassword: String = ""
    @Published var cachedPassword: String = ""
    @Published var pendingSudoAction: SudoPendingAction? = nil
    
    struct QueueItem: Equatable {
        let action: String // "install", "uninstall", "upgrade"
        let pkg: BrewPackage
    }
    
    struct SudoPendingAction {
        let action: String
        let pkg: BrewPackage
        let threadId: Int
    }
    
    var brewPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        return "/usr/local/bin/brew"
    }
    
    func authenticateWithTouchID(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        logDebug("Evaluating Touch ID authentication: \(reason)")
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        logDebug("Touch ID authentication succeeded.")
                    } else {
                        logDebug("Touch ID authentication failed: \(authError?.localizedDescription ?? "unknown error")")
                    }
                    completion(success)
                }
            }
        } else {
            logDebug("Touch ID is not available or not configured: \(error?.localizedDescription ?? "no error description"). Defaulting to true for demo/simulator fallback.")
            DispatchQueue.main.async {
                completion(true) // Fallback when biometrics is unavailable
            }
        }
    }
    
    func openApp(pkg: BrewPackage) {
        logDebug("Attempting to open app: \(pkg.name)")
        
        // Try the standard path first: /Applications/Name.app
        let appPath = "/Applications/\(pkg.name).app"
        if FileManager.default.fileExists(atPath: appPath) {
            let url = URL(fileURLWithPath: appPath)
            if NSWorkspace.shared.open(url) {
                logDebug("Successfully opened app via NSWorkspace open URL: \(appPath)")
                return
            }
        }
        
        // Try user applications: ~/Applications/Name.app
        let userAppPath = "\(NSHomeDirectory())/Applications/\(pkg.name).app"
        if FileManager.default.fileExists(atPath: userAppPath) {
            let url = URL(fileURLWithPath: userAppPath)
            if NSWorkspace.shared.open(url) {
                logDebug("Successfully opened app via NSWorkspace open URL: \(userAppPath)")
                return
            }
        }
        
        // Fallback: spawn terminal open command
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", pkg.name]
        do {
            try proc.run()
            logDebug("Spawned open -a \(pkg.name) process")
        } catch {
            logDebug("Failed to spawn open command: \(error.localizedDescription)")
        }
    }
    
    init() {
        if let stored = UserDefaults.standard.stringArray(forKey: "hidden_categories") {
            self.hiddenCategories = Set(stored)
        }
        // Hydrate with local first, then fetch online registry
        loadLocalPackages()
        fetchOnlineCasks()
    }
    
    func loadLocalPackages() {
        DispatchQueue.main.async {
            guard !self.isLoadingLocal else { return }
            self.isLoadingLocal = true
            
            self.runShell(cmd: "\(self.brewPath) info --json=v2 --installed") { [weak self] output in
                guard let self = self else { return }
                defer {
                    DispatchQueue.main.async {
                        self.isLoadingLocal = false
                    }
                }
                
                guard let data = output.data(using: .utf8) else {
                    logDebug("Empty or invalid output data for local packages")
                    return
                }
                do {
                    let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                    var localPackages: [BrewPackage] = []
                    
                    for c in response.casks {
                        localPackages.append(BrewPackage(
                            id: c.token,
                            name: c.name.first ?? c.token,
                            type: "cask",
                            description: c.desc ?? "Installed macOS Application.",
                            homepage: c.homepage ?? "",
                            version: c.version,
                            installedVersion: c.installed
                        ))
                    }
                    
                    for f in response.formulae {
                        localPackages.append(BrewPackage(
                            id: f.name,
                            name: f.name,
                            type: "formula",
                            description: f.desc ?? "Command-line utility.",
                            homepage: f.homepage ?? "",
                            version: f.versions?.stable ?? "Unknown",
                            installedVersion: f.installed?.first?.version
                        ))
                    }
                    
                    DispatchQueue.main.async {
                        self.mergeWithLocalPackages(localList: localPackages)
                        self.loadOutdatedPackages()
                        self.refreshRecommendations()
                    }
                } catch {
                    logDebug("Failed to decode local packages JSON: \(error)")
                    print("Failed to decode local packages JSON: \(error)")
                }
            }
        }
    }
    
    private func mergeWithLocalPackages(localList: [BrewPackage]) {
        var localMap = [String: BrewPackage]()
        for p in localList {
            localMap[p.id] = p
        }
        
        self.packages = self.packages.map { pkg in
            if let localPkg = localMap[pkg.id] {
                var updated = pkg
                updated.installedVersion = localPkg.installedVersion
                return updated
            } else {
                var updated = pkg
                updated.installedVersion = nil
                return updated
            }
        }
        
        let currentIds = Set(self.packages.map { $0.id })
        for lp in localList {
            if !currentIds.contains(lp.id) {
                self.packages.append(lp)
            }
        }
    }
    
    func loadOutdatedPackages() {
        runShell(cmd: "\(brewPath) outdated --json=v2") { [weak self] output in
            guard let self = self, let data = output.data(using: .utf8) else { return }
            do {
                let response = try JSONDecoder().decode(OutdatedResponse.self, from: data)
                var outdatedMap = [String: String]()
                
                for c in response.casks {
                    outdatedMap[c.name] = c.current_version
                }
                for f in response.formulae {
                    outdatedMap[f.name] = f.current_version
                }
                
                DispatchQueue.main.async {
                    self.packages = self.packages.map { pkg in
                        if let latestVer = outdatedMap[pkg.id] {
                            var updated = pkg
                            updated.version = latestVer
                            return updated
                        }
                        return pkg
                    }
                }
            } catch {
                print("Failed to parse outdated packages JSON: \(error)")
            }
        }
    }
    
    func fetchOnlineCasks() {
        guard let url = URL(string: "https://formulae.brew.sh/api/cask.json") else { return }
        self.allCasksLoading = true
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async { self?.allCasksLoading = false }
                return
            }
            
            do {
                let apiCasks = try JSONDecoder().decode([CaskAPIItem].self, from: data)
                let mappedPackages = apiCasks.map { item in
                    BrewPackage(
                        id: item.token,
                        name: item.name.first ?? item.token,
                        type: "cask",
                        description: item.desc ?? "macOS Application Cask.",
                        homepage: item.homepage ?? "",
                        version: item.version,
                        installedVersion: nil
                    )
                }
                
                DispatchQueue.main.async {
                    let existingIds = Set(self.packages.map { $0.id })
                    let newCasks = mappedPackages.filter { !existingIds.contains($0.id) }
                    self.packages.append(contentsOf: newCasks)
                    
                    self.allCasksLoaded = true
                    self.allCasksLoading = false
                    
                    self.loadLocalPackages()
                }
            } catch {
                print("Error decoding online casks: \(error)")
                DispatchQueue.main.async { self.allCasksLoading = false }
            }
        }.resume()
    }
    
    func queueAction(action: String, pkg: BrewPackage) {
        DispatchQueue.main.async {
            self.pendingInstallQueue.append(QueueItem(action: action, pkg: pkg))
            self.dispatchNextQueueItem()
        }
    }
    
    func queueActions(action: String, pkgs: [BrewPackage]) {
        DispatchQueue.main.async {
            let items = pkgs.map { QueueItem(action: action, pkg: $0) }
            self.pendingInstallQueue.append(contentsOf: items)
            self.dispatchNextQueueItem()
        }
    }
    
    func dispatchNextQueueItem() {
        guard !pendingInstallQueue.isEmpty else { return }
        if let idleThread = threads.first(where: { !$0.isRunning }) {
            let nextItem = pendingInstallQueue.removeFirst()
            runThreadCommand(thread: idleThread, action: nextItem.action, pkg: nextItem.pkg)
        }
    }
    
    func runThreadCommand(thread: ThreadLane, action: String, pkg: BrewPackage, sudoPassword: String? = nil) {
        thread.activeRunningId = pkg.id
        thread.activePkg = pkg
        thread.isRunning = true
        thread.logs = ["\n--- [Thread \(thread.id)] Executing brew \(action) for \(pkg.name) (\(pkg.id)) ---"]
        
        let typeFlag = pkg.type == "cask" ? "--cask" : "--formula"
        let command = "\(brewPath) \(action) \(typeFlag) \(pkg.id)"
        logDebug("Thread lane [\(thread.id)] running command: \(command)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        let actualPassword = sudoPassword ?? cachedPassword
        if !actualPassword.isEmpty {
            process.arguments = ["-c", "echo '\(actualPassword)' | sudo -S -v && \(command)"]
        } else {
            process.arguments = ["-c", command]
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        thread.process = process
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                logDebug("Thread [\(thread.id)] output: \(line)")
                DispatchQueue.main.async {
                    thread.logs.append(line)
                    
                    // Inspect logs for sudo prompts
                    let lowerLine = line.lowercased()
                    if lowerLine.contains("sudo: a password is required") ||
                        lowerLine.contains("password:") ||
                        lowerLine.contains("sudo: a terminal is required") {
                        logDebug("Sudo credentials requested on thread [\(thread.id)]")
                        // Pause process and open helper popup
                        self.pendingSudoAction = SudoPendingAction(action: action, pkg: pkg, threadId: thread.id)
                        self.isSudoModalOpen = true
                    }
                }
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            logDebug("Thread lane [\(thread.id)] process terminated with status: \(proc.terminationStatus)")
            fileHandle.readabilityHandler = nil
            thread.process = nil
            
            DispatchQueue.main.async {
                thread.isRunning = false
                thread.activeRunningId = nil
                thread.activePkg = nil
                
                self?.loadLocalPackages()
                self?.dispatchNextQueueItem()
            }
        }
        do {
            try process.run()
        } catch {
            logDebug("Thread lane [\(thread.id)] process spawn threw: \(error.localizedDescription)")
            fileHandle.readabilityHandler = nil
            DispatchQueue.main.async {
                thread.logs.append("\nFailed to run process: \(error.localizedDescription)")
                thread.isRunning = false
                thread.activeRunningId = nil
                thread.activePkg = nil
                self.dispatchNextQueueItem()
            }
        }
    }
    
    private func runShell(cmd: String, completion: @escaping (String) -> Void) {
        logDebug("Running shell command: \(cmd)")
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                
                var data = Data()
                let fileHandle = pipe.fileHandleForReading
                
                while process.isRunning {
                    let chunk = fileHandle.availableData
                    if !chunk.isEmpty {
                        data.append(chunk)
                    } else {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                }
                
                let remaining = fileHandle.readDataToEndOfFile()
                if !remaining.isEmpty {
                    data.append(remaining)
                }
                
                if let output = String(data: data, encoding: .utf8) {
                    logDebug("Command [\(cmd)] output length: \(output.count)")
                    completion(output)
                } else {
                    logDebug("Command [\(cmd)] output encoding error")
                    completion("")
                }
            } catch {
                logDebug("Command [\(cmd)] execution throw: \(error.localizedDescription)")
                completion("")
            }
        }
    }
}

// --- AI BACKEND SYSTEM ---

extension ShapeStyle where Self == Material {
    static var liquidGlass: Material {
        return .ultraThinMaterial
    }
}

enum AIBackend: String, CaseIterable, Identifiable {
    case apple = "Apple Intelligence"
    case openRouter = "OpenRouter"
    case gemini = "Gemini"
    case ollama = "Ollama (Local)"
    
    var id: String { self.rawValue }
}

class AIService: ObservableObject {
    static let shared = AIService()
    
    @Published var isLoading: Bool = false
    @Published var lastResponse: String = ""
    @Published var lastError: String? = nil
    
    var selectedBackend: AIBackend {
        let raw = UserDefaults.standard.string(forKey: "selectedAIBackend") ?? AIBackend.apple.rawValue
        return AIBackend(rawValue: raw) ?? .apple
    }
    
    func ask(question: String, forPackage pkg: BrewPackage) async -> String {
        let prompt = "Tell me about the macOS/CLI package '\(pkg.name)' (\(pkg.id)). \(question) Package description: \(pkg.description). Type: \(pkg.type). Version: \(pkg.version)."
        
        switch selectedBackend {
        case .apple:
            return await askAppleFoundationModel(prompt: prompt)
        case .openRouter:
            return await askOpenRouter(prompt: prompt)
        case .gemini:
            return await askGemini(prompt: prompt)
        case .ollama:
            return await askOllama(prompt: prompt)
        }
    }
    
    private func askAppleFoundationModel(prompt: String) async -> String {
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return String(describing: response)
        } catch {
            return "Apple Intelligence error: \(error.localizedDescription). Make sure Apple Intelligence is enabled in System Settings."
        }
    }
    
    private func askOpenRouter(prompt: String) async -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: "openRouterAPIKey"), !apiKey.isEmpty else {
            return "No OpenRouter API key configured. Please add one in Settings."
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { return "Invalid URL" }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "openai/gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            return "Failed to parse OpenRouter response."
        } catch {
            return "OpenRouter error: \(error.localizedDescription)"
        }
    }
    
    private func askGemini(prompt: String) async -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: "geminiAPIKey"), !apiKey.isEmpty else {
            return "No Gemini API key configured. Please add one in Settings."
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)") else { return "Invalid URL" }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
            return "Failed to parse Gemini response."
        } catch {
            return "Gemini error: \(error.localizedDescription)"
        }
    }
    
    private func askOllama(prompt: String) async -> String {
        let host = UserDefaults.standard.string(forKey: "ollamaHost") ?? "http://localhost:11434"
        let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
        guard let url = URL(string: "\(host)/api/generate") else { return "Invalid Ollama URL" }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? String {
                return response
            }
            return "Failed to parse Ollama response."
        } catch {
            return "Ollama error: \(error.localizedDescription). Is Ollama running locally?"
        }
    }
}

// --- AI SETTINGS VIEW ---

struct AISettingsView: View {
    @AppStorage("selectedAIBackend") private var selectedBackendRaw: String = AIBackend.apple.rawValue
    @AppStorage("openRouterAPIKey") private var openRouterKey: String = ""
    @AppStorage("geminiAPIKey") private var geminiKey: String = ""
    @AppStorage("ollamaHost") private var ollamaHost: String = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel: String = "llama3.2"
    
    private var selectedBackend: AIBackend {
        AIBackend(rawValue: selectedBackendRaw) ?? .apple
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Configuration")
                            .font(.system(size: 18, weight: .bold))
                        Text("Choose your preferred AI backend for the Ask AI feature")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                // Backend Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Provider")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Picker("Backend", selection: $selectedBackendRaw) {
                        ForEach(AIBackend.allCases) { backend in
                            HStack {
                                Image(systemName: iconForBackend(backend))
                                Text(backend.rawValue)
                            }
                            .tag(backend.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(16)
                .background(
                    LiquidGlassView(isHovered: false, isPressed: false, isProminent: false, cornerRadius: 12)
                )
                
                // Provider-specific settings
                switch selectedBackend {
                case .apple:
                    appleSection
                case .openRouter:
                    apiKeySection(title: "OpenRouter API Key", key: $openRouterKey, placeholder: "sk-or-v1-...")
                case .gemini:
                    apiKeySection(title: "Gemini API Key", key: $geminiKey, placeholder: "AIza...")
                case .ollama:
                    ollamaSection
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    var appleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16))
                Text("Apple Intelligence")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            Text("Uses the built-in Apple Foundation Model running on-device via Apple Intelligence. No API key required. Requires Apple Silicon and Apple Intelligence enabled in System Settings.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(nil)
            
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 11))
                Text("Private & on-device — your data never leaves your Mac")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            LiquidGlassView(isHovered: false, isPressed: false, isProminent: false, cornerRadius: 12)
        )
    }
    
    func apiKeySection(title: String, key: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            SecureField(placeholder, text: key)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            
            Text("Your API key is stored locally in UserDefaults.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            LiquidGlassView(isHovered: false, isPressed: false, isProminent: false, cornerRadius: 12)
        )
    }
    
    var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 16))
                Text("Ollama Local Server")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Host URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("http://localhost:11434", text: $ollamaHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Model Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("llama3.2", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
            }
            
            Text("Make sure Ollama is running locally before using this backend.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            LiquidGlassView(isHovered: false, isPressed: false, isProminent: false, cornerRadius: 12)
        )
    }
    
    func iconForBackend(_ backend: AIBackend) -> String {
        switch backend {
        case .apple: return "apple.logo"
        case .openRouter: return "network"
        case .gemini: return "sparkles"
        case .ollama: return "desktopcomputer"
        }
    }
}

// --- ASK AI SHEET ---

struct AskAISheet: View {
    let pkg: BrewPackage
    @Environment(\.dismiss) var dismiss
    @State private var question: String = ""
    @State private var response: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask AI about \(pkg.name)")
                        .font(.system(size: 14, weight: .bold))
                    Text("Using \(AIService.shared.selectedBackend.rawValue)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            // Chat area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !response.isEmpty {
                        Text(response)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(10)
                    } else if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Thinking...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Ask anything about this package")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Input bar
            HStack(spacing: 8) {
                TextField("What does this package do?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendQuestion() }
                
                Button(action: sendQuestion) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(question.isEmpty || isLoading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 500, height: 420)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active))
    }
    
    func sendQuestion() {
        guard !question.isEmpty else { return }
        let q = question
        question = ""
        isLoading = true
        response = ""
        
        Task {
            let result = await AIService.shared.ask(question: q, forPackage: pkg)
            await MainActor.run {
                response = result
                isLoading = false
            }
        }
    }
}

// --- LIQUID GLASS PACKAGE CARD VIEW (macOS 26) ---

struct PackageCardView: View {
    let pkg: BrewPackage
    @ObservedObject var manager: BrewManager
    let action: () -> Void
    @State private var isHovered = false
    @State private var showAISheet = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    PackageIconView(pkg: pkg)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Button(action: { showAISheet = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                            Text("Ask AI")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(pkg.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(height: 24, alignment: .topLeading)
                }
                
                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 8))
                        Text(String(format: "%.1f", pkg.rating))
                            .font(.system(size: 9, weight: .bold))
                    }
                    Spacer()
                    Text("VIEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                }
            }
            .padding(10)
            .frame(width: 180, height: 120)
            .containerBackground(.liquidGlass, for: .window)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? Color.purple.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.04), radius: isHovered ? 6 : 2, y: isHovered ? 3 : 1)
            .scaleEffect(isHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showAISheet) {
            AskAISheet(pkg: pkg)
        }
    }
}

// --- RECOMMENDED PACKAGES CAROUSEL (macOS 26) ---

struct RecommendedPackagesCarousel: View {
    @ObservedObject var manager: BrewManager
    @Binding var selectedPackage: BrewPackage?
    
    var recommendedList: [BrewPackage] {
        let installed = manager.packages.filter { $0.installedVersion != nil }
        let installedIds = Set(installed.map { $0.id })
        
        var recommendedIds: [String] = []
        
        // Custom matching rules
        if installed.contains(where: { $0.id.contains("code") || $0.id == "iterm2" || $0.id == "docker" }) {
            recommendedIds.append(contentsOf: ["iterm2", "docker", "postman", "visual-studio-code"])
        }
        if installed.contains(where: { $0.id == "git" }) {
            recommendedIds.append(contentsOf: ["gh", "lazygit"])
        }
        
        // Premium default utilities
        recommendedIds.append(contentsOf: ["rectangle", "alfred", "vlc", "stats", "appcleaner", "cyberduck", "handbrake"])
        
        var finalIds: [String] = []
        for id in recommendedIds {
            if !installedIds.contains(id) && !finalIds.contains(id) {
                finalIds.append(id)
            }
        }
        
        let found = manager.packages.filter { finalIds.contains($0.id) }
        if found.isEmpty {
            // Pick a few uninstalled ones from all packages
            return Array(manager.packages.filter { $0.installedVersion == nil }.prefix(5))
        }
        return found
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Recommendations For You")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recommendedList) { pkg in
                        PackageCardView(pkg: pkg, manager: manager, action: {
                            selectedPackage = pkg
                        })
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .scrollTargetBehavior(.paging)
        }
    }
}

// --- APP WINDOW WRAPPER VIBRANCY (LIQUID GLASS) ---

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct LiquidGlassView: View {
    var isHovered: Bool = false
    var isPressed: Bool = false
    var isProminent: Bool = false
    var cornerRadius: CGFloat = 12
    
    var body: some View {
        ZStack {
            // Blurred backing layer
            VisualEffectView(
                material: isProminent ? .hudWindow : (isPressed ? .selection : (isHovered ? .selection : .contentBackground)),
                blendingMode: .withinWindow,
                state: .active
            )
            .opacity(isPressed ? 0.6 : (isHovered ? 0.95 : 0.85))
            
            // Specular reflection shine overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(isProminent ? 0.35 : (isHovered ? 0.26 : 0.18)),
                    Color.white.opacity(isProminent ? 0.12 : (isHovered ? 0.08 : 0.04)),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            if isProminent {
                Color.blue.opacity(isPressed ? 0.65 : 0.82)
            }
        }
        .cornerRadius(cornerRadius)
        .overlay(
            // Liquid glass highlight border
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isPressed ? 0.8 : (isHovered ? 0.65 : 0.45)),
                            Color.white.opacity(0.12),
                            Color.black.opacity(isProminent ? 0.35 : 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isHovered ? 1.0 : 0.6
                )
        )
    }
}

struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isProminent ? .semibold : .medium))
            .foregroundColor(isProminent ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                LiquidGlassView(
                    isHovered: false,
                    isPressed: configuration.isPressed,
                    isProminent: isProminent,
                    cornerRadius: 5
                )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}


// --- PACKAGE ROW COMPONENT ---

// --- CASCAding PACKAGE ICON RESOLUTION VIEW ---

struct PackageIconView: View {
    let pkg: BrewPackage
    
    // BOLT OPTIMIZATION: Thread-safe lazy caching via 'static let' to avoid redundant disk I/O.
    // This reduces UI lag when scrolling through long lists of packages.
    static let applicationsCache: [String] = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
    static let iconPathCache = NSCache<NSString, NSString>()

    var body: some View {
        Group {
            if let localIcon = getLocalAppIcon() {
                Image(nsImage: localIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                AsyncImage(url: URL(string: "https://github.com/App-Fair/appcasks/releases/download/\(pkg.id)/AppIcon.png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        if let domain = extractDomain(from: pkg.homepage), !domain.isEmpty {
                            AsyncImage(url: URL(string: "https://icon.horse/icon/\(domain)")) { innerPhase in
                                if case .success(let favicon) = innerPhase {
                                    favicon
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    defaultSymbol
                                }
                            }
                        } else {
                            defaultSymbol
                        }
                    }
                }
            }
        }
    }
    
    func getLocalAppIcon() -> NSImage? {
        // BOLT: Check in-memory cache for previously resolved path to avoid file system lookups
        if let cachedPath = Self.iconPathCache.object(forKey: pkg.id as NSString) {
            return NSWorkspace.shared.icon(forFile: cachedPath as String)
        }

        let fileManager = FileManager.default
        let possibleNames = [
            pkg.name,
            pkg.name.replacingOccurrences(of: " ", with: ""),
            pkg.id,
            pkg.id.capitalized,
            pkg.id.replacingOccurrences(of: "-", with: " ").capitalized
        ]
        
        let appDirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        
        for dir in appDirs {
            for name in possibleNames {
                let appPath = "\(dir)/\(name).app"
                if fileManager.fileExists(atPath: appPath) {
                    Self.iconPathCache.setObject(appPath as NSString, forKey: pkg.id as NSString)
                    return NSWorkspace.shared.icon(forFile: appPath)
                }
            }
        }
        
        // BOLT: Use cached directory listing to avoid redundant disk I/O on every icon resolution
        for file in Self.applicationsCache {
            if file.hasSuffix(".app") {
                let cleanAppName = file.replacingOccurrences(of: ".app", with: "").lowercased()
                let cleanPkgId = pkg.id.lowercased()
                let cleanPkgName = pkg.name.lowercased()

                if cleanAppName.contains(cleanPkgId) || cleanPkgId.contains(cleanAppName) ||
                    cleanAppName.contains(cleanPkgName) || cleanPkgName.contains(cleanAppName) {
                    let fullPath = "/Applications/\(file)"
                    Self.iconPathCache.setObject(fullPath as NSString, forKey: pkg.id as NSString)
                    return NSWorkspace.shared.icon(forFile: fullPath)
                }
            }
        }
        
        return nil
    }
    
    func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            var clean = urlString.replacingOccurrences(of: "https://", with: "")
            clean = clean.replacingOccurrences(of: "http://", with: "")
            if let firstSlash = clean.firstIndex(of: "/") {
                clean = String(clean[..<firstSlash])
            }
            return clean
        }
        return url.host
    }
    
    var defaultSymbol: some View {
        var sym = "terminal"
        var color: Color = .blue
        
        switch pkg.id {
        case "visual-studio-code":
            sym = "chevron.left.forwardslash.chevron.right"
            color = .blue
        case "discord":
            sym = "bubble.left.and.bubble.right.fill"
            color = .indigo
        case "figma":
            sym = "paintpalette.fill"
            color = .purple
        case "docker":
            sym = "shippingbox.fill"
            color = .cyan
        case "spotify":
            sym = "music.note"
            color = .green
        case "google-chrome":
            sym = "globe"
            color = .red
        case "obsidian":
            sym = "doc.text.fill"
            color = .purple
        case "postman":
            sym = "paperplane.fill"
            color = .orange
        case "slack":
            sym = "message.fill"
            color = .pink
        case "zoom":
            sym = "video.fill"
            color = .blue
        case "python":
            sym = "chevron.left.forwardslash.chevron.right"
            color = .blue
        case "node":
            sym = "hexagon.fill"
            color = .green
        case "git":
            sym = "arrow.triangle.pull"
            color = .orange
        default:
            sym = pkg.type == "cask" ? "macwindow" : "terminal.fill"
            color = .gray
        }
        
        return Image(systemName: sym)
            .font(.system(size: 14))
            .foregroundColor(color)
    }
}

struct PackageCard: View {
    let pkg: BrewPackage
    @ObservedObject var manager: BrewManager
    @Binding var selectedIds: Set<String>
    
    @State private var isHovered = false
    @State private var showAISheet = false
    
    var isProcessing: Bool {
        manager.threads.contains { $0.activeRunningId == pkg.id }
    }
    
    var isQueued: Bool {
        manager.pendingInstallQueue.contains { $0.pkg.id == pkg.id }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedIds.contains(pkg.id) },
                set: { isSelected in
                    if isSelected {
                        selectedIds.insert(pkg.id)
                    } else {
                        selectedIds.remove(pkg.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .scaleEffect(0.9)
            
            PackageIconView(pkg: pkg)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pkg.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                
                Text(pkg.description)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 8))
                    Text(String(format: "%.1f", pkg.rating))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 0)
                
                HStack(spacing: 4) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                        Text("Running...")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                    } else if isQueued {
                        Text("Queued...")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else {
                        if pkg.installedVersion == nil {
                            HStack(spacing: 4) {
                                Button("Install") {
                                    manager.queueAction(action: "install", pkg: pkg)
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: false))
                                
                                Button(action: { showAISheet = true }) {
                                    Image(systemName: "sparkles")
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: false))
                                .help("Ask AI about this package")
                            }
                        } else {
                            HStack(spacing: 4) {
                                if pkg.type == "cask" {
                                    Button("Open") {
                                        manager.openApp(pkg: pkg)
                                    }
                                    .buttonStyle(GlassButtonStyle(isProminent: true))
                                }
                                
                                if pkg.hasUpdate {
                                    Button("Upgrade") {
                                        manager.queueAction(action: "upgrade", pkg: pkg)
                                    }
                                    .buttonStyle(GlassButtonStyle(isProminent: false))
                                }
                                
                                Button("Remove") {
                                    manager.queueAction(action: "uninstall", pkg: pkg)
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: false))
                                
                                Button(action: { showAISheet = true }) {
                                    Image(systemName: "sparkles")
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: false))
                                .help("Ask AI about this package")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(width: 250, height: 85)
        .background(
            LiquidGlassView(
                isHovered: isHovered,
                isPressed: false,
                isProminent: selectedIds.contains(pkg.id),
                cornerRadius: 10
            )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.03), radius: isHovered ? 6 : 1, x: 0, y: isHovered ? 3 : 0.5)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showAISheet) {
            AskAISheet(pkg: pkg)
        }
    }
}

struct PackageRow: View {
    let pkg: BrewPackage
    @ObservedObject var manager: BrewManager
    @Binding var selectedIds: Set<String>
    
    @State private var isHovered = false
    @State private var showAISheet = false
    
    var isProcessing: Bool {
        manager.threads.contains { $0.activeRunningId == pkg.id }
    }
    
    var isQueued: Bool {
        manager.pendingInstallQueue.contains { $0.pkg.id == pkg.id }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selectedIds.contains(pkg.id) },
                set: { isSelected in
                    if isSelected {
                        selectedIds.insert(pkg.id)
                    } else {
                        selectedIds.remove(pkg.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            
            PackageIconView(pkg: pkg)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(pkg.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(pkg.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text(pkg.type.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(pkg.type == "cask" ? Color.purple.opacity(0.1) : Color.orange.opacity(0.1))
                        .foregroundColor(pkg.type == "cask" ? .purple : .orange)
                        .cornerRadius(4)
                }
                
                Text(pkg.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("Latest: \(pkg.version)")
                    if let inst = pkg.installedVersion {
                        Text("•")
                        Text("Installed: \(inst)")
                    }
                    
                    Text("•")
                    
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 9))
                        Text(String(format: "%.1f", pkg.rating))
                            .font(.system(size: 9, weight: .semibold))
                        Text("(\(pkg.ratingCount))")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                if isProcessing {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Running...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                    }
                } else if isQueued {
                    Text("Queued...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    if pkg.installedVersion == nil {
                        HStack(spacing: 6) {
                            Button("Install") {
                                manager.queueAction(action: "install", pkg: pkg)
                            }
                            .buttonStyle(GlassButtonStyle(isProminent: false))
                            
                            Button(action: { showAISheet = true }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                    Text("Ask AI")
                                }
                            }
                            .buttonStyle(GlassButtonStyle(isProminent: false))
                        }
                    } else {
                        HStack(spacing: 6) {
                            if pkg.type == "cask" {
                                Button("Open") {
                                    manager.openApp(pkg: pkg)
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: true))
                            }
                            
                            if pkg.hasUpdate {
                                Button("Update") {
                                    manager.queueAction(action: "upgrade", pkg: pkg)
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: false))
                            }
                            
                            Button("Uninstall") {
                                manager.queueAction(action: "uninstall", pkg: pkg)
                            }
                            .buttonStyle(GlassButtonStyle(isProminent: false))
                            
                            Button(action: { showAISheet = true }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                    Text("Ask AI")
                                }
                            }
                            .buttonStyle(GlassButtonStyle(isProminent: false))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            LiquidGlassView(
                isHovered: isHovered,
                isPressed: false,
                isProminent: selectedIds.contains(pkg.id),
                cornerRadius: 12
            )
        )
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 2, x: 0, y: isHovered ? 4 : 1)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showAISheet) {
            AskAISheet(pkg: pkg)
        }
    }
}

// --- SIDEBAR TAB ENUM ---

enum SidebarTab: String, CaseIterable, Hashable {
    case discover
    case casks
    case formulae
    case updates
    case settings
    
    var title: String {
        switch self {
        case .discover: return "Discover"
        case .casks: return "Installed Casks"
        case .formulae: return "Formulae (CLI)"
        case .updates: return "Updates"
        case .settings: return "AI Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .discover: return "square.grid.2x2.fill"
        case .casks: return "square.stack.3d.up.fill"
        case .formulae: return "terminal.fill"
        case .updates: return "arrow.clockwise.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    func badgeCount(manager: BrewManager) -> Int {
        switch self {
        case .discover:
            return 0
        case .casks:
            return manager.packages.filter { $0.type == "cask" && $0.installedVersion != nil }.count
        case .formulae:
            return manager.packages.filter { $0.type == "formula" && $0.installedVersion != nil }.count
        case .updates:
            return manager.packages.filter { $0.hasUpdate }.count
        case .settings:
            return 0
        }
    }
}


// --- MAIN VIEW VIEW WITH NATIVE NAVIGATION SPLIT VIEW ---

struct ContentView: View {
    @StateObject var manager = BrewManager()
    @State var selectedTab: SidebarTab? = .discover
    @State var searchQuery: String = ""
    @State var filterType: String = "all"
    @State var selectedIds = Set<String>()
    
    @State var isConsoleDrawerOpen: Bool = false
    @State var activeThreadId: Int = 1
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.icon)
                }
                .badge(tab.badgeCount(manager: manager))
            }
            .listStyle(.sidebar)
            .background(Color.clear)
            .navigationTitle("BrewDeck")
        } detail: {
            if let tab = selectedTab {
                DetailView(
                    tab: tab,
                    manager: manager,
                    searchQuery: $searchQuery,
                    filterType: $filterType,
                    selectedIds: $selectedIds,
                    isConsoleDrawerOpen: $isConsoleDrawerOpen,
                    activeThreadId: $activeThreadId
                )
            } else {
                Text("Select a category in the sidebar")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 850, minHeight: 580)
        .sheet(isPresented: Binding(
            get: { manager.isSudoModalOpen },
            set: { manager.isSudoModalOpen = $0 }
        )) {
            SudoSheet(manager: manager)
        }
    }
}

struct FeaturedCard: View {
    let item: FeaturedCarouselSection.FeaturedItem
    @ObservedObject var manager: BrewManager
    let action: () -> Void
    
    @State private var isHovered = false
    
    var screenshotUrl: URL? {
        URL(string: "https://image.thum.io/get/maxAge/24/width/1024/crop/600/\(item.homepage)")
    }
    
    var pkgRating: Double {
        let hash = abs(item.token.hashValue)
        let score = 4.3 + Double(hash % 7) * 0.1
        return Double(String(format: "%.1f", score)) ?? 4.5
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background Landscape screenshot
                if let url = screenshotUrl {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 320, height: 180)
                                .clipped()
                        case .failure:
                            // Fallback gradient panel if screenshot fails
                            LinearGradient(
                                colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: 320, height: 180)
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 320, height: 180)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                // Dark bottom gradient overlay for text readability
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(width: 320, height: 180)
                
                // Info Overlays
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(item.tagline)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            ForEach(0..<5) { star in
                                Image(systemName: Double(star) < pkgRating ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 10))
                            }
                            Text(String(format: "%.1f", pkgRating))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    
                    Spacer()
                    
                    // VIEW button style like App Store but transparent overlay
                    Text("VIEW")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white))
                        .shadow(radius: 2)
                }
                .padding(12)
                .frame(width: 320, alignment: .leading)
            }
            .frame(width: 320, height: 180)
            .background(Color.black.opacity(0.2))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? Color.blue.opacity(0.6) : Color.white.opacity(0.12), lineWidth: isHovered ? 1.5 : 0.5)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3)
            .scaleEffect(isHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

struct FeaturedCarouselSection: View {
    @ObservedObject var manager: BrewManager
    @Binding var selectedPackage: BrewPackage?
    
    struct FeaturedItem: Identifiable {
        let id: String
        let name: String
        let token: String
        let tagline: String
        let homepage: String
    }
    
    let items = [
        FeaturedItem(id: "vscode", name: "Visual Studio Code", token: "visual-studio-code", tagline: "Code editing. Redefined.", homepage: "https://code.visualstudio.com"),
        FeaturedItem(id: "figma", name: "Figma", token: "figma", tagline: "Design and prototype collaboratively.", homepage: "https://www.figma.com"),
        FeaturedItem(id: "spotify", name: "Spotify", token: "spotify", tagline: "Music, playlists, and podcasts.", homepage: "https://www.spotify.com"),
        FeaturedItem(id: "discord", name: "Discord", token: "discord", tagline: "Your place to talk and hang out.", homepage: "https://discord.com"),
        FeaturedItem(id: "arc", name: "Arc", token: "arc", tagline: "The browser built for you.", homepage: "https://arc.net")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Featured Apps")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        FeaturedCard(item: item, manager: manager) {
                            if let pkg = manager.packages.first(where: { $0.id == item.token }) {
                                selectedPackage = pkg
                            } else {
                                // Create temporary BrewPackage if offline or not loaded yet
                                selectedPackage = BrewPackage(
                                    id: item.token,
                                    name: item.name,
                                    type: "cask",
                                    description: item.tagline,
                                    homepage: item.homepage,
                                    version: "Latest",
                                    installedVersion: nil
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
        }
    }
}

// --- NATIVE DETAIL VIEW ---

struct DetailView: View {
    let tab: SidebarTab
    @ObservedObject var manager: BrewManager
    @Binding var searchQuery: String
    @Binding var filterType: String
    @Binding var selectedIds: Set<String>
    @Binding var isConsoleDrawerOpen: Bool
    @Binding var activeThreadId: Int
    
    @State private var expandedCategories: Set<AppCategory> = Set(AppCategory.allCases)
    @State private var selectedPackage: BrewPackage? = nil
    
    var body: some View {
        if tab == .settings {
            AISettingsView()
        } else {
        VStack(spacing: 0) {
            if manager.packages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Syncing Homebrew packages metadata...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                let groupedPackages = Dictionary(grouping: filteredPackages, by: { $0.category })
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if tab == .discover && searchQuery.isEmpty {
                            FeaturedCarouselSection(manager: manager, selectedPackage: $selectedPackage)
                            
                            RecommendedPackagesCarousel(manager: manager, selectedPackage: $selectedPackage)
                            
                            Text("Browse Categories")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 4)
                        }
                        
                        VStack(alignment: .leading, spacing: 24) {
                            // Category Shelves with expand/collapse and hide functionality
                            ForEach(AppCategory.allCases) { category in
                                // Skip hidden categories
                                if manager.hiddenCategories.contains(category.rawValue) {
                                    EmptyView()
                                } else {
                                    let categoryPkgs = groupedPackages[category] ?? []
                                    if !categoryPkgs.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: category.icon)
                                                    .foregroundColor(.blue)
                                                Text(category.rawValue)
                                                    .font(.system(size: 14, weight: .bold))
                                                Text("(\(categoryPkgs.count))")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Button(action: {
                                                    if expandedCategories.contains(category) {
                                                        expandedCategories.remove(category)
                                                    } else {
                                                        expandedCategories.insert(category)
                                                    }
                                                }) {
                                                    Image(systemName: expandedCategories.contains(category) ? "chevron.up" : "chevron.down")
                                                        .foregroundColor(.primary)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button {
                                                        manager.hideCategory(category.rawValue)
                                                    } label: {
                                                        Text("Hide Category")
                                                        Image(systemName: "eye.slash")
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 4)
                                            if expandedCategories.contains(category) {
                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    LazyHStack(spacing: 12) {
                                                        ForEach(categoryPkgs) { pkg in
                                                            PackageCard(pkg: pkg, manager: manager, selectedIds: $selectedIds)
                                                                .onTapGesture { selectedPackage = pkg }
                                                        }
                                                    }
                                                    .padding(.horizontal, 4)
                                                }
                                                .frame(height: 95)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            
            // Console Drawer at the bottom
            BottomConsoleSection(manager: manager, isConsoleDrawerOpen: $isConsoleDrawerOpen, activeThreadId: $activeThreadId)
        }
        .background(Color.clear)
        .sheet(item: $selectedPackage) { pkg in
            PackageDetailSheet(pkg: pkg, manager: manager)
        }
        .navigationTitle(tab.title)
        .navigationSubtitle(subtitleText)
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search \(tab.title.lowercased())...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Refresh Button
                Button(action: {
                    manager.loadLocalPackages()
                    manager.fetchOnlineCasks()
                }) {
                    Label("Reload Packages", systemImage: "arrow.clockwise")
                }
                .help("Refresh Homebrew registries")
                
                // Segments for discover tab
                if tab == .discover {
                    Picker("Filter Type", selection: $filterType) {
                        Text("All").tag("all")
                        Text("Installed").tag("installed")
                        Text("Updates").tag("updates")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                
                // Bulk action if selected items > 0
                if !selectedIds.isEmpty {
                    Button(action: {
                        let targets = manager.packages.filter { selectedIds.contains($0.id) }
                        if targets.count > 5 {
                            manager.authenticateWithTouchID(reason: "Authorize installation of \(targets.count) Homebrew packages.") { success in
                                if success {
                                    manager.queueActions(action: "install", pkgs: targets)
                                    selectedIds.removeAll()
                                }
                            }
                        } else {
                            manager.queueActions(action: "install", pkgs: targets)
                            selectedIds.removeAll()
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.on.square.fill")
                            Text("Install (\(selectedIds.count))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Clear") {
                        selectedIds.removeAll()
                    }
                }
            }
        }
        }
    }

    
    var subtitleText: String {
        if manager.allCasksLoading {
            return "Syncing Homebrew registry..."
        }
        return ""
    }
    
    var filteredPackages: [BrewPackage] {
        manager.packages.filter { pkg in
            switch tab {
            case .casks:
                if pkg.type != "cask" || pkg.installedVersion == nil { return false }
            case .formulae:
                if pkg.type != "formula" || pkg.installedVersion == nil { return false }
            case .updates:
                if !pkg.hasUpdate { return false }
            case .discover:
                if filterType == "installed" && pkg.installedVersion == nil { return false }
                if filterType == "updates" && !pkg.hasUpdate { return false }
            case .settings:
                return false
            }
            
            if !searchQuery.isEmpty {
                return pkg.name.localizedCaseInsensitiveContains(searchQuery) ||
                       pkg.id.localizedCaseInsensitiveContains(searchQuery) ||
                       pkg.description.localizedCaseInsensitiveContains(searchQuery)
            }
            return true
        }
    }
}

// --- CONSOLE PANEL SECTION ---

struct BottomConsoleSection: View {
    @ObservedObject var manager: BrewManager
    @Binding var isConsoleDrawerOpen: Bool
    @Binding var activeThreadId: Int
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Console Header Bar
            HStack {
                Button(action: {
                    withAnimation {
                        isConsoleDrawerOpen.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isConsoleDrawerOpen ? 90 : 0))
                            .foregroundColor(.secondary)
                        Image(systemName: "terminal.fill")
                            .foregroundColor(.secondary)
                        Text("Terminal Console Logs")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Multi-thread Status
                HStack(spacing: 8) {
                    ForEach(manager.threads) { t in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(t.isRunning ? Color.blue : Color.gray.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text("T\(t.id)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(t.isRunning ? .blue : .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            if isConsoleDrawerOpen {
                HStack {
                    Picker("Terminal Lane", selection: $activeThreadId) {
                        ForEach(manager.threads) { t in
                            Text("Terminal \(t.id)").tag(t.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 320)
                    
                    Spacer()
                    
                    Button("Clear Output") {
                        if let idx = manager.threads.firstIndex(where: { $0.id == activeThreadId }) {
                            manager.threads[idx].logs = []
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let logs = manager.threads.first(where: { $0.id == activeThreadId })?.logs ?? []
                        if logs.isEmpty {
                            Text("No output logged. Run an action to see stdout/stderr stream.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(logs, id: \.self) { line in
                                Text(line)
                                    .foregroundColor(logColor(line))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(height: 140)
                .background(Color.black.opacity(0.15))
                .font(.system(size: 10, design: .monospaced))
            }
        }
    }
    
    func logColor(_ line: String) -> Color {
        if line.hasPrefix("==>") { return .blue }
        if line.hasPrefix("🍺") { return .green }
        if line.hasPrefix("Error:") || line.lowercased().contains("failed") { return .red }
        return .primary
    }
}

// --- SUDO AUTHORIZATION SHEET ---

struct SudoSheet: View {
    @ObservedObject var manager: BrewManager
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundColor(.blue)
            
            Text("Helper Privilege Required")
                .font(.headline)
            
            Text("Brew requires administrator access to install helper casks on Terminal \(manager.pendingSudoAction?.threadId ?? 1).")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            SecureField("Password", text: $manager.sudoInputPassword)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    manager.isSudoModalOpen = false
                    if let action = manager.pendingSudoAction {
                        if let idx = manager.threads.firstIndex(where: { $0.id == action.threadId }) {
                            manager.threads[idx].logs.append("\nError: sudo authentication declined.")
                            manager.threads[idx].isRunning = false
                            manager.threads[idx].activeRunningId = nil
                            manager.threads[idx].activePkg = nil
                        }
                    }
                    manager.pendingSudoAction = nil
                    manager.sudoInputPassword = ""
                }
                .buttonStyle(GlassButtonStyle(isProminent: false))
                
                Button("Authorize") {
                    manager.isSudoModalOpen = false
                    manager.cachedPassword = manager.sudoInputPassword
                    if let action = manager.pendingSudoAction {
                        if let thread = manager.threads.first(where: { $0.id == action.threadId }) {
                            manager.runThreadCommand(
                                thread: thread,
                                action: action.action,
                                pkg: action.pkg,
                                sudoPassword: manager.sudoInputPassword
                            )
                        }
                    }
                    manager.pendingSudoAction = nil
                    manager.sudoInputPassword = ""
                }
                .buttonStyle(GlassButtonStyle(isProminent: true))
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active))
    }
}

// --- COCOA APP DELEGATE OVERRIDES ---

class CustomWindowContentView: NSView {}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var configuredWindows = Set<NSWindow>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clear log file at start
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".brewdeck_debug.log").path
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        logDebug("BrewDeck application started launch lifecycle.")
        
        // Run on next runloop cycle to capture the initial window
        DispatchQueue.main.async {
            self.configureAllWindows()
        }
        
        // Observe when any window becomes key/visible to catch late-created windows
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }
    
    @objc func windowDidBecomeVisible(_ notification: Notification) {
        configureAllWindows()
    }
    
    func configureAllWindows() {
        for window in NSApplication.shared.windows {
            // Ignore system/helper panels
            guard window.className.contains("NSWindow") || window.className.contains("SwiftUI") else { continue }
            if !configuredWindows.contains(window) {
                configuredWindows.insert(window)
                configureWindow(window)
            }
        }
    }
    
    func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        
        // Window Transparency settings
        window.backgroundColor = .clear
        window.isOpaque = false
        
        // Check if window content view is already configured
        guard !(window.contentView is CustomWindowContentView) else { return }
        
        if let originalContentView = window.contentView {
            let container = CustomWindowContentView(frame: originalContentView.frame)
            container.autoresizingMask = [.width, .height]
            
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .underWindowBackground
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.frame = container.bounds
            visualEffectView.autoresizingMask = [.width, .height]
            
            container.addSubview(visualEffectView)
            
            originalContentView.frame = container.bounds
            originalContentView.autoresizingMask = [.width, .height]
            container.addSubview(originalContentView)
            
            window.contentView = container
        }
    }
}

struct InteractiveRatingBar: View {
    let pkgId: String
    @State private var userRating: Int = 0
    @State private var isHoveredStar: Int? = nil
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= (isHoveredStar ?? userRating) ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundColor(star <= (isHoveredStar ?? userRating) ? .yellow : .secondary.opacity(0.6))
                    .onTapGesture {
                        userRating = star
                        UserDefaults.standard.setValue(Double(star), forKey: "custom_rating_\(pkgId)")
                        logDebug("Saved custom user rating \(star) for package: \(pkgId)")
                    }
                    .onHover { hovering in
                        if hovering {
                            isHoveredStar = star
                        } else {
                            isHoveredStar = nil
                        }
                    }
            }
            
            if userRating > 0 {
                Text("Thank you for rating!")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.leading, 8)
            } else {
                Text("Tap stars to rate")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }
        }
        .onAppear {
            if let saved = UserDefaults.standard.value(forKey: "custom_rating_\(pkgId)") as? Double {
                userRating = Int(saved)
            }
        }
    }
}

// --- PACKAGE DETAIL SHEET ---

struct PackageDetailSheet: View {
    let pkg: BrewPackage
    @ObservedObject var manager: BrewManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showAISheet = false
    
    var isProcessing: Bool {
        manager.threads.contains { $0.activeRunningId == pkg.id }
    }
    
    var isQueued: Bool {
        manager.pendingInstallQueue.contains { $0.pkg.id == pkg.id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                PackageIconView(pkg: pkg)
                    .frame(width: 48, height: 48)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pkg.name)
                            .font(.system(size: 16, weight: .bold))
                        
                        Text(pkg.type.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(pkg.type == "cask" ? Color.purple.opacity(0.1) : Color.orange.opacity(0.1))
                            .foregroundColor(pkg.type == "cask" ? .purple : .orange)
                            .cornerRadius(4)
                    }
                    
                    Text(pkg.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            // Contents
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(pkg.description)
                            .font(.system(size: 13))
                            .lineLimit(nil)
                    }
                    
                    // Metadata Rows
                    VStack(alignment: .leading, spacing: 6) {
                        DetailMetaRow(label: "Available Version", value: pkg.version)
                        if let inst = pkg.installedVersion {
                            DetailMetaRow(label: "Installed Version", value: inst)
                        } else {
                            DetailMetaRow(label: "Installed Status", value: "Not Installed")
                        }
                        
                        if !pkg.homepage.isEmpty, let homeUrl = URL(string: pkg.homepage) {
                            HStack {
                                Text("Homepage")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Link(pkg.homepage, destination: homeUrl)
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(8)
                    
                    // Live Landing Page Screenshot Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App Preview / Screenshot")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        if !pkg.homepage.isEmpty, pkg.homepage.hasPrefix("http") {
                            let screenshotUrl = "https://image.thum.io/get/maxAge/24/width/1024/crop/800/\(pkg.homepage)"
                            
                            AsyncImage(url: URL(string: screenshotUrl)) { phase in
                                switch phase {
                                case .empty:
                                    HStack {
                                        Spacer()
                                        VStack(spacing: 8) {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Loading live screenshot...")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .frame(height: 200)
                                    .background(Color.primary.opacity(0.02))
                                    .cornerRadius(10)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(10)
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                        )
                                case .failure:
                                    MockScreenshotView(pkgName: pkg.name)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            MockScreenshotView(pkgName: pkg.name)
                        }
                    }
                    
                    // User Rating Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Rating")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        InteractiveRatingBar(pkgId: pkg.id)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(8)
                }
                .padding(16)
            }
            
            Divider()
            
            // Actions Footer
            HStack {
                Button(action: { showAISheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Ask AI")
                    }
                }
                .buttonStyle(GlassButtonStyle(isProminent: false))
                
                Spacer()
                
                if isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Executing command...")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 10)
                } else if isQueued {
                    Text("Queued in lanes...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                } else {
                    if pkg.installedVersion == nil {
                        Button("Install Package") {
                            dismiss()
                            manager.queueAction(action: "install", pkg: pkg)
                        }
                        .buttonStyle(GlassButtonStyle(isProminent: true))
                    } else {
                        HStack(spacing: 8) {
                            if pkg.type == "cask" {
                                Button("Open App") {
                                    dismiss()
                                    manager.openApp(pkg: pkg)
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: true))
                            }
                            
                            if pkg.hasUpdate {
                                Button("Update Cask") {
                                    dismiss()
                                    manager.queueAction(action: "upgrade", pkg: pkg)
                                }
                                .buttonStyle(GlassButtonStyle(isProminent: false))
                            }
                            
                            Button("Uninstall") {
                                dismiss()
                                manager.queueAction(action: "uninstall", pkg: pkg)
                            }
                            .buttonStyle(GlassButtonStyle(isProminent: false))
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.01))
        }
        .frame(width: 480, height: 460)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active))
        .sheet(isPresented: $showAISheet) {
            AskAISheet(pkg: pkg)
        }
    }
}


struct DetailMetaRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

struct MockScreenshotView: View {
    let pkgName: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Preview not available for \(pkgName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.01))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// --- MAIN ENTRyPOINT ---

@main
struct BrewDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
