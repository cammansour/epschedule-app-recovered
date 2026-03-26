
import Foundation
import Combine

struct ClassRosterStudent: Identifiable, Decodable {
    var id: String { username }
    let firstname: String?
    let lastname: String?
    let preferred_name: String?
    let grade: Int?
    let username: String
    let email: String?
    let photo_url: String?
    
    var displayName: String {
        let first = preferred_name ?? firstname ?? ""
        let last = lastname ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }
}

struct ClassRosterResponse: Decodable {
    let period: String
    let teacher: String?
    let termId: Int
    let students: [ClassRosterStudent]
    
    enum CodingKeys: String, CodingKey {
        case period, teacher, students
        case termId = "term_id"
    }
}

struct EPSStudentSummary: Identifiable, Decodable {
    let id: String
    let name: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case name
        case username
    }

    init(id: String, name: String, username: String) {
        self.id = id
        self.name = name
        self.username = username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        id = username
    }
}

struct EPSStudentDetail: Decodable {
    let firstname: String?
    let lastname: String?
    let grade: Int?
    let email: String?
    let photoURL: URL?
    let raw: [String: Any]

    enum CodingKeys: String, CodingKey {
        case firstname
        case lastname
        case grade
        case email
        case photoURL = "photo_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        grade = try container.decodeIfPresent(Int.self, forKey: .grade)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)

        if let topLevel = try? JSONSerialization.jsonObject(
            with: decoder.singleValueContainer().decode(Data.self),
            options: []
        ) as? [String: Any] {
            raw = topLevel
        } else {
            raw = [:]
        }
    }
}

struct CurrentUserResponse: Codable {
    let username: String
    let email: String
    let photoURL: String?
    let schedule: Schedule
    
    enum CodingKeys: String, CodingKey {
        case username, email, schedule
        case photoURL = "photo_url"
    }
    
    init(username: String, email: String, photoURL: String?, schedule: Schedule) {
        self.username = username
        self.email = email
        self.photoURL = photoURL
        self.schedule = schedule
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decode(String.self, forKey: .email)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
    }
}

final class EPScheduleAPI: ObservableObject {
    static let shared = EPScheduleAPI()

    private let baseURL = URL(string: "https://www.epschedule.com")!

    @Published var lastSchedulePoll: Date?
    @Published var lastError: Error?
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: CurrentUserResponse?
    @Published var currentSchedule: Schedule?
    @Published var masterSchedule: [String: String]? // Date -> Schedule type
    @Published var sharePhoto: Bool? // Privacy setting for photo visibility

    private var pollTimer: Timer?
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: config)
    }()

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("epschedule_user_cache.json")
    }

    private init() {
        if let cached = Self.loadScheduleFromCache() {
            currentUser = cached
            currentSchedule = cached.schedule
            isAuthenticated = true
        }
        _ = hasAuthenticationCookies()
    }

    static func loadScheduleFromCache() -> CurrentUserResponse? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CurrentUserResponse.self, from: data)
    }

    func saveScheduleToCache(_ user: CurrentUserResponse) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private func deleteCachedSchedule() {
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    
    func hasAuthenticationCookies() -> Bool {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else {
            let wasAuth = isAuthenticated
            isAuthenticated = false
            if wasAuth != isAuthenticated {
            }
            return false
        }
        let hasAuth = cookies.contains { $0.name == "session" } || cookies.contains { $0.name == "token" }
        let wasAuth = isAuthenticated
        isAuthenticated = hasAuth
        if wasAuth != isAuthenticated {
        }
        return hasAuth
    }

    func startSchedulePolling(
        interval: TimeInterval = 60 * 5,
        onUpdate: @escaping (Schedule?) -> Void
    ) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchCurrentUserSchedule(onUpdate: onUpdate)
        }
        fetchCurrentUserSchedule(onUpdate: onUpdate)
    }

    func stopSchedulePolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func searchStudents(query: String, completion: @escaping (Result<[EPSStudentSummary], Error>) -> Void) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            completion(.success([]))
            return
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        let url = baseURL.appendingPathComponent("search/\(encoded)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required. Please log in."])))
                    }
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"])))
                    }
                    return
                }
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.success([]))
                }
                return
            }

            do {
                let results = try JSONDecoder().decode([EPSStudentSummary].self, from: data)
                DispatchQueue.main.async {
                    completion(.success(results))
                }
            } catch {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Failed to decode search results. Response: \(responseString)")
                }
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    func fetchStudentDetail(username: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let url = baseURL.appendingPathComponent("student/\(encoded)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.success([:]))
                }
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
                DispatchQueue.main.async {
                    completion(.success(json))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    func fetchCurrentUser(completion: @escaping (Result<CurrentUserResponse, Error>) -> Void) {
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            print("🍪 Cookies available: \(cookies.map { $0.name })")
        } else {
            print("⚠️ No cookies found for \(baseURL)")
        }
        
        let meURL = baseURL.appendingPathComponent("me")
        var request = URLRequest(url: meURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        print("📡 Trying /me endpoint...")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 404 {
                    print("⚠️ /me endpoint not found, falling back to HTML parsing...")
                    self?.fetchScheduleFromHTML(completion: completion)
                    return
                }
                
                if httpResponse.statusCode == 403 {
                    print("🔒 Not authenticated (403)")
                    let authError = NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
                    DispatchQueue.main.async {
                        self?.isAuthenticated = false
                        completion(.failure(authError))
                    }
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    print("⚠️ /me returned \(httpResponse.statusCode), falling back to HTML parsing...")
                    self?.fetchScheduleFromHTML(completion: completion)
                    return
                }
            }
            
            if let error = error {
                print("❌ Network error on /me: \(error.localizedDescription)")
                self?.fetchScheduleFromHTML(completion: completion)
                return
            }
            
            guard let data = data else {
                self?.fetchScheduleFromHTML(completion: completion)
                return
            }
            
            do {
                let userResponse = try JSONDecoder().decode(CurrentUserResponse.self, from: data)
                print("✅ Got schedule from /me for: \(userResponse.username)")
                DispatchQueue.main.async {
                    self?.currentUser = userResponse
                    self?.currentSchedule = userResponse.schedule
                    self?.lastSchedulePoll = Date()
                    self?.isAuthenticated = true
                    self?.saveScheduleToCache(userResponse)
                    completion(.success(userResponse))
                }
            } catch {
                print("❌ Failed to decode /me: \(error), falling back to HTML parsing...")
                self?.fetchScheduleFromHTML(completion: completion)
            }
        }.resume()
    }
    
    private func fetchScheduleFromHTML(completion: @escaping (Result<CurrentUserResponse, Error>) -> Void) {
        print("📡 Fetching schedule from HTML page...")
        
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            print("🍪 Sending these cookies:")
            for cookie in cookies {
                print("   - \(cookie.name): \(cookie.value.prefix(30))...")
            }
        } else {
            print("⚠️ NO cookies available for \(baseURL)")
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ Failed to load main page: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 HTTP Status: \(httpResponse.statusCode)")
                print("📥 Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 302 {
                    print("🔒 Not authenticated (status \(httpResponse.statusCode))")
                    let authError = NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
                    DispatchQueue.main.async {
                        self?.isAuthenticated = false
                        completion(.failure(authError))
                    }
                    return
                }
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                print("❌ No data or couldn't decode HTML")
                let noDataError = NSError(domain: "EPScheduleAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                DispatchQueue.main.async {
                    completion(.failure(noDataError))
                }
                return
            }
            
            if html.contains("SIGN IN") || html.contains("microsoftLogin") && !html.contains("var userSchedule") {
                print("🔒 Got login page instead of schedule page - not authenticated")
                let authError = NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Got login page - authentication required"])
                DispatchQueue.main.async {
                    self?.isAuthenticated = false
                    completion(.failure(authError))
                }
                return
            }
            
            print("📄 HTML length: \(html.count) characters")
            print("📄 Contains 'userSchedule': \(html.contains("userSchedule"))")
            
            guard let scheduleJSON = self?.extractJSON(from: html, variableName: "userSchedule") else {
                print("❌ Could not find userSchedule in HTML")
                print("📄 HTML preview: \(String(html.prefix(500)))")
                let parseError = NSError(domain: "EPScheduleAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not parse schedule from page - may not be logged in"])
                DispatchQueue.main.async {
                    completion(.failure(parseError))
                }
                return
            }
            
            print("📄 Found userSchedule JSON (first 300 chars): \(String(scheduleJSON.prefix(300)))")
            
            guard let scheduleData = scheduleJSON.data(using: .utf8) else {
                print("❌ Invalid JSON encoding")
                let parseError = NSError(domain: "EPScheduleAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON encoding"])
                DispatchQueue.main.async {
                    completion(.failure(parseError))
                }
                return
            }
            
            do {
                let schedule = try JSONDecoder().decode(Schedule.self, from: scheduleData)
                print("✅ Successfully decoded schedule!")
                print("   👤 Name: \(schedule.displayName)")
                print("   📧 Username: \(schedule.username ?? "unknown")")
                print("   🎓 Grade: \(schedule.computedGrade ?? -1)")
                print("   📚 Terms: \(schedule.classes.count)")
                if let firstTerm = schedule.classes.first {
                    print("   📖 Classes in first term: \(firstTerm.count)")
                    for (index, cls) in firstTerm.prefix(5).enumerated() {
                        print("      \(index+1). \(cls.period): \(cls.name)")
                    }
                }
                
                let userResponse = CurrentUserResponse(
                    username: schedule.username ?? "",
                    email: schedule.email ?? "",
                    photoURL: schedule.photoURL,
                    schedule: schedule
                )
                
                if let lunchJSON = self?.extractJSONArray(from: html, variableName: "lunches"),
                   let lunchData = lunchJSON.data(using: .utf8),
                   let lunchArray = try? JSONSerialization.jsonObject(with: lunchData) as? [[String: Any]] {
                    print("🍽️ Found \(lunchArray.count) lunch entries in HTML")
                    ScheduleService.shared.updateLunches(lunchArray)
                }
                
                if let daysJSON = self?.extractJSONArray(from: html, variableName: "days"),
                   let daysData = daysJSON.data(using: .utf8),
                   let daysArray = try? JSONSerialization.jsonObject(with: daysData) as? [Any],
                   daysArray.count >= 2 {
                    var dateMap: [String: String] = [:]
                    if let el0 = daysArray[0] as? [String: Any] {
                        for (k, v) in el0 { if let s = v as? String { dateMap[k] = s } }
                    }
                    if let el1 = daysArray[1] as? [String: Any] {
                        var dayTypes: [String: [[String: String]]] = [:]
                        for (typeName, slotsAny) in el1 {
                            if let slots = slotsAny as? [[String: String]] { dayTypes[typeName] = slots }
                        }
                        ScheduleService.shared.updateFullMasterSchedule(dateMap: dateMap, dayTypes: dayTypes)
                        print("📅 Parsed full master schedule from HTML (\(dateMap.count) days, \(dayTypes.count) types)")
                    }
                }
                
                DispatchQueue.main.async {
                    self?.currentUser = userResponse
                    self?.currentSchedule = schedule
                    self?.lastSchedulePoll = Date()
                    self?.isAuthenticated = true
                    self?.saveScheduleToCache(userResponse)
                    completion(.success(userResponse))
                }
            } catch {
                print("❌ Failed to decode schedule from HTML: \(error)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("   Key not found: \(key.stringValue) at \(context.codingPath)")
                    case .typeMismatch(let type, let context):
                        print("   Type mismatch: expected \(type) at \(context.codingPath)")
                    case .valueNotFound(let type, let context):
                        print("   Value not found: \(type) at \(context.codingPath)")
                    case .dataCorrupted(let context):
                        print("   Data corrupted: \(context)")
                    @unknown default:
                        print("   Unknown decoding error")
                    }
                }
                print("   JSON that failed: \(String(scheduleJSON.prefix(500)))")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func extractJSONArray(from html: String, variableName: String) -> String? {
        let pattern = "var \(variableName)\\s*=\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { return nil }
        let afterEquals = html[range.upperBound...]
        guard let start = afterEquals.firstIndex(of: "[") else { return nil }
        var depth = 0; var end: String.Index? = nil
        var inString = false; var escape = false
        for (i, ch) in afterEquals[start...].enumerated() {
            if escape { escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if ch == "\"" { inString = !inString; continue }
            if !inString {
                if ch == "[" { depth += 1 }
                else if ch == "]" { depth -= 1; if depth == 0 { end = afterEquals.index(start, offsetBy: i + 1); break } }
            }
        }
        guard let e = end else { return nil }
        return String(afterEquals[start..<e])
    }
    
    private func extractJSON(from html: String, variableName: String) -> String? {
        let pattern = "var \(variableName)\\s*=\\s*"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else {
            return nil
        }
        
        let afterEquals = html[range.upperBound...]
        
        guard let jsonStart = afterEquals.firstIndex(of: "{") else {
            return nil
        }
        
        var depth = 0
        var jsonEnd: String.Index?
        var inString = false
        var escapeNext = false
        
        for (index, char) in afterEquals[jsonStart...].enumerated() {
            let currentIndex = afterEquals.index(jsonStart, offsetBy: index)
            
            if escapeNext {
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inString = !inString
                continue
            }
            
            if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        jsonEnd = afterEquals.index(jsonStart, offsetBy: index + 1)
                        break
                    }
                }
            }
        }
        
        guard let end = jsonEnd else {
            return nil
        }
        
        return String(afterEquals[jsonStart..<end])
    }
    
    func fetchMasterSchedule(completion: @escaping (Result<[String: String], Error>) -> Void) {
        let url = baseURL.appendingPathComponent("api/master_schedule")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                let authError = NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
                DispatchQueue.main.async {
                    completion(.failure(authError))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.success([:]))
                }
                return
            }
            
            do {
                let days = try JSONDecoder().decode([String: String].self, from: data)
                DispatchQueue.main.async {
                    self?.masterSchedule = days
                    completion(.success(days))
                }
            } catch {
                print("Failed to decode master schedule: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func fetchClassRoster(period: String, termId: Int, completion: @escaping (Result<ClassRosterResponse, Error>) -> Void) {
        var components = URLComponents(url: baseURL.appendingPathComponent("class/\(period)"), resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "term_id", value: String(termId))]
        guard let url = components.url else {
            completion(.failure(NSError(domain: "EPScheduleAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "EPScheduleAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(ClassRosterResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(decoded)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    func downloadPass(username: String, completion: @escaping (Result<Data, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("api/pass/\(username)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "EPScheduleAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Pass not found for this user"])))
                }
                return
            }
            guard let data = data, !data.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "EPScheduleAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            DispatchQueue.main.async { completion(.success(data)) }
        }.resume()
    }
    
    func fetchTermStarts(completion: @escaping (Result<[String], Error>) -> Void) {
        let url = baseURL.appendingPathComponent("api/term_starts")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                print("⚠️ /api/term_starts not found, parsing from HTML...")
                self.parseTermStartsFromHTML(completion: completion)
                return
            }
            
            if let error = error {
                print("⚠️ Error fetching term starts: \(error), trying HTML parsing...")
                self.parseTermStartsFromHTML(completion: completion)
                return
            }
            
            guard let data = data else {
                self.parseTermStartsFromHTML(completion: completion)
                return
            }
            
            do {
                let termStarts = try JSONDecoder().decode([String].self, from: data)
                print("✅ Got term starts from API: \(termStarts)")
                DispatchQueue.main.async {
                    completion(.success(termStarts))
                }
            } catch {
                print("⚠️ Failed to decode term starts from API, trying HTML parsing...")
                self.parseTermStartsFromHTML(completion: completion)
            }
        }.resume()
    }
    
    private func parseTermStartsFromHTML(completion: @escaping (Result<[String], Error>) -> Void) {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.success([]))
                }
                return
            }
            
            guard let termStartsJSON = self.extractJSON(from: html, variableName: "termStarts") else {
                print("⚠️ Could not find termStarts in HTML")
                DispatchQueue.main.async {
                    completion(.success([]))
                }
                return
            }
            
            let cleaned = termStartsJSON.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let dateStrings = cleaned.split(separator: ",").map { 
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
            
            print("✅ Parsed term starts from HTML: \(dateStrings)")
            DispatchQueue.main.async {
                completion(.success(dateStrings))
            }
        }.resume()
    }

    private func fetchCurrentUserSchedule(onUpdate: @escaping (Schedule?) -> Void) {
        fetchCurrentUser { [weak self] result in
            switch result {
            case .failure(let error):
                self?.lastError = error
                onUpdate(nil)
            case .success(let userResponse):
                onUpdate(userResponse.schedule)
            }
        }
    }

    private func decodeSchedule(from json: [String: Any]) -> Schedule? {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Schedule.self, from: data)
        } catch {
            lastError = error
            return nil
        }
    }
    
    func fetchPrivacySettings(completion: @escaping (Result<Bool, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("privacy")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    }
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"])))
                    }
                    return
                }
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "EPScheduleAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sharePhoto = json["share_photo"] as? Bool {
                    DispatchQueue.main.async {
                        self?.sharePhoto = sharePhoto
                        completion(.success(sharePhoto))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func updatePrivacySettings(sharePhoto: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("privacy")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "share_photo=\(sharePhoto ? "true" : "false")"
        request.httpBody = bodyString.data(using: .utf8)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
                    }
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "EPScheduleAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"])))
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                self?.sharePhoto = sharePhoto
                completion(.success(()))
            }
        }.resume()
    }
    
    func clearUserData() {
        currentUser = nil
        currentSchedule = nil
        isAuthenticated = false
        sharePhoto = nil
        deleteCachedSchedule()
        
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }
}

