
import Foundation
import Combine

class ScheduleService: ObservableObject {
    static let shared = ScheduleService()
    
    private let baseURL = "https://www.epschedule.com"
    private var masterSchedule: MasterSchedule?
    private var scheduleData: [String: Schedule] = [:]
    private var termRanges: [(start: Date, end: Date)] = []
    private var teacherNameCache: [String: String] = [:] // Cache: username -> full name
    
    @Published var isLoading = false
    @Published var error: Error?
    
    private init() {
        loadLocalData()
        rebuildTermRangesForCurrentSchoolYear()
    }
    
    private func rebuildTermRangesForCurrentSchoolYear() {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let startYear = (month >= 7) ? year : (year - 1)
        var comp = DateComponents()
        comp.calendar = calendar
        
        var ranges: [(Date, Date)] = []
        comp.year = startYear; comp.month = 9; comp.day = 3
        let fallStart = calendar.date(from: comp)!
        comp.month = 11; comp.day = 21
        let fallEnd = calendar.date(from: comp)!
        ranges.append((fallStart, fallEnd))
        comp.month = 12; comp.day = 2; comp.year = startYear
        let winterStart = calendar.date(from: comp)!
        comp.month = 3; comp.day = 6; comp.year = startYear + 1
        let winterEnd = calendar.date(from: comp)!
        ranges.append((winterStart, winterEnd))
        comp.month = 3; comp.day = 10; comp.year = startYear + 1
        let springStart = calendar.date(from: comp)!
        comp.month = 6; comp.day = 12
        let springEnd = calendar.date(from: comp)!
        ranges.append((springStart, springEnd))
        
        termRanges = ranges
        print("📅 Term ranges: Fall \(fallStart)–\(fallEnd), Winter \(winterStart)–\(winterEnd), Spring \(springStart)–\(springEnd)")
    }
    
    func updateMasterSchedule(_ days: [String: String]) {
        let existingTypes = masterSchedule?.dayTypes ?? [:]
        masterSchedule = MasterSchedule(days: days, dayTypes: existingTypes)
        print("📅 Updated master schedule with \(days.count) days from API")
    }
    
    func updateFullMasterSchedule(dateMap: [String: String], dayTypes: [String: [[String: String]]]) {
        var parsed: [String: [DaySlot]] = [:]
        for (typeName, slots) in dayTypes {
            parsed[typeName] = slots.compactMap { dict in
                guard let period = dict["period"], let times = dict["times"] else { return nil }
                return DaySlot(period: period, times: times)
            }
        }
        masterSchedule = MasterSchedule(days: dateMap, dayTypes: parsed)
        print("📅 Updated full master schedule: \(dateMap.count) days, \(parsed.count) day types")
    }
    
    private var lunchCache: [String: String] = [:]
    
    func updateLunches(_ lunches: [[String: Any]]) {
        for lunch in lunches {
            guard let day = lunch["day"] as? Int,
                  let month = lunch["month"] as? Int,
                  let year = lunch["year"] as? Int else { continue }
            let dateKey = String(format: "%04d-%02d-%02d", year, month, day)
            let summary = lunch["summary"] as? String
            lunchCache[dateKey] = summary
        }
        print("🍽️ Cached \(lunchCache.count) lunch entries")
    }
    
    func getLunchMenu(for dateString: String) -> String? {
        return lunchCache[dateString]
    }
    
    func refreshTermRangesIfNeeded() {
        rebuildTermRangesForCurrentSchoolYear()
    }
    
    func updateTermStarts(_ termStarts: [String]) {
        rebuildTermRangesForCurrentSchoolYear()
    }
    
    func loadLocalData() {
        var url: URL?
        if let bundleUrl = Bundle.main.url(forResource: "master_schedule", withExtension: "json", subdirectory: "data") {
            url = bundleUrl
        } else if let bundleUrl = Bundle.main.url(forResource: "master_schedule", withExtension: "json") {
            url = bundleUrl
        } else {
            let possiblePaths = [
                "/Users/cammansour/Desktop/desk/EPSCHEDULE APP/data/master_schedule.json",
                "/Users/cammansour/Desktop/desk/EPSCHEDULE APP/epschedule/epschedule/data/master_schedule.json",
                "/Users/cammansour/Desktop/EPSCHEDULE APP/data/master_schedule.json",
                "/Users/cammansour/Desktop/EPSCHEDULE APP/epschedule/epschedule/data/master_schedule.json"
            ]
            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    url = URL(fileURLWithPath: path)
                    break
                }
            }
        }
        
        guard let url = url else {
            print("⚠️ Master schedule file not found")
            masterSchedule = MasterSchedule(days: [:], dayTypes: [:])
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
                  jsonArray.count >= 2 else {
                masterSchedule = MasterSchedule(days: [:], dayTypes: [:])
                return
            }
            
            var dateMap: [String: String] = [:]
            if let el0 = jsonArray[0] as? [String: Any] {
                for (k, v) in el0 {
                    if let s = v as? String { dateMap[k] = s }
                }
            }
            
            var dayTypes: [String: [DaySlot]] = [:]
            if let el1 = jsonArray[1] as? [String: Any] {
                for (typeName, slotsAny) in el1 {
                    if let slots = slotsAny as? [[String: String]] {
                        dayTypes[typeName] = slots.compactMap { dict in
                            guard let p = dict["period"], let t = dict["times"] else { return nil }
                            return DaySlot(period: p, times: t)
                        }
                    }
                }
            }
            
            masterSchedule = MasterSchedule(days: dateMap, dayTypes: dayTypes)
            print("✅ Loaded master schedule: \(dateMap.count) days, \(dayTypes.count) day types")
        } catch {
            print("❌ Error loading master schedule: \(error)")
            masterSchedule = MasterSchedule(days: [:], dayTypes: [:])
        }
    }
    
    func getScheduleType(for date: Date) -> String? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let normalizedDate = calendar.date(from: components) else {
            return nil
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: normalizedDate)
        
        return masterSchedule?.days[dateString]
    }
    
    func getDaySchedule(for date: Date, userSchedule: Schedule) -> DaySchedule {
        let scheduleTypeName = getScheduleType(for: date)
        let termID = getTermID(for: date)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: date)
        
        let noSchoolKeywords = ["Break", "No School", "Convocation", "Orientations", "Conferences", "PDD", "Presidents", "Voices", "Veterans", "Student Led"]
        let isNoSchool = scheduleTypeName == nil ||
            noSchoolKeywords.contains(where: { scheduleTypeName?.contains($0) == true })
        
        guard !isNoSchool, let typeName = scheduleTypeName else {
            return DaySchedule(date: date, scheduleType: scheduleTypeName, periods: [],
                               lunch: nil, isNoSchool: true,
                               allDayEvent: scheduleTypeName, termId: termID)
        }
        
        let slots = masterSchedule?.dayTypes[typeName] ?? []
        
        let termClasses: [Class] = termID < userSchedule.classes.count ? userSchedule.classes[termID] : []
        let classByPeriod: [String: Class] = Dictionary(termClasses.map { ($0.period.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        
        let grade = userSchedule.computedGrade ?? 12
        let isUS = grade >= 9
        
        var periods: [PeriodEntry] = []
        var lunch: LunchInfo? = nil
        let standardPeriods = Set(["A","B","C","D","E","F","G","H","O"])
        
        for slot in slots {
            let p = slot.period
            let times = slot.times
            
            if isUS && p.contains("MS") { continue }
            if !isUS && p.contains("US") { continue }
            
            if p == "O" { continue }
            
            if standardPeriods.contains(p.uppercased()) {
                if let cls = classByPeriod[p.uppercased()] {
                    let teacherName = getTeacherDisplayName(for: cls.teacherUsername)
                    periods.append(PeriodEntry(
                        period: p.uppercased(),
                        className: cls.name,
                        teacher: teacherName,
                        room: cls.room,
                        time: "\(p) Period: \(times)",
                        image: nil
                    ))
                } else {
                    periods.append(PeriodEntry(
                        period: p.uppercased(),
                        className: "Free Period",
                        teacher: nil,
                        room: nil,
                        time: "\(p) Period: \(times)",
                        image: nil
                    ))
                }
            } else if p.contains("Lunch") {
                let menu = getLunchMenu(for: dateString)
                lunch = LunchInfo(date: dateString, menu: menu)
                periods.append(PeriodEntry(
                    period: "LUNCH",
                    className: "Lunch",
                    teacher: nil,
                    room: menu,
                    time: times,
                    image: nil
                ))
            } else if p.lowercased().contains("advisory") || p.lowercased().contains("assembly") ||
                       p.lowercased().contains("class meeting") || p.lowercased().contains("us flex") ||
                       p.lowercased().contains("us community") || p.lowercased().contains("seminars") ||
                       p.lowercased().contains("clubs") {
                var mbRoom: String? = nil
                let dayActivities = ICSParser.getMiddleBandActivities(for: date)
                if let activity = dayActivities.first(where: { $0.summary.lowercased().contains(p.lowercased().replacingOccurrences(of: " - us", with: "")) }) {
                    mbRoom = activity.location
                }
                periods.append(PeriodEntry(
                    period: "MB",
                    className: p.replacingOccurrences(of: " - US", with: "").replacingOccurrences(of: " - MS", with: ""),
                    teacher: nil,
                    room: mbRoom,
                    time: times,
                    image: nil
                ))
            }
        }
        
        if lunch == nil {
            let menu = getLunchMenu(for: dateString)
            lunch = LunchInfo(date: dateString, menu: menu)
        }
        
        return DaySchedule(
            date: date,
            scheduleType: typeName,
            periods: periods,
            lunch: lunch,
            isNoSchool: false,
            allDayEvent: nil,
            termId: termID
        )
    }
    
    private func getPeriodsFromRange(_ range: String, schedule: Schedule, date: Date) -> [PeriodEntry] {
        let termID = getTermID(for: date)
        
        print("   getPeriodsFromRange: range=\(range), termID=\(termID)")
        
        guard termID < schedule.classes.count else {
            print("   ⚠️ Term ID \(termID) is out of range (schedule has \(schedule.classes.count) terms)")
            return []
        }
        
        let classes = schedule.classes[termID]
        print("   Using term \(termID) which has \(classes.count) classes")
        print("   Classes in term \(termID): \(classes.map { "\($0.period): \($0.name)" })")
        
        var periods: [PeriodEntry] = []
        
        if range.contains("-") {
            let components = range.split(separator: "-")
            if components.count == 2,
               let start = components.first?.uppercased(),
               let end = components.last?.uppercased(),
               let startChar = start.first,
               let endChar = end.first,
               let startAscii = startChar.asciiValue,
               let endAscii = endChar.asciiValue,
               let aAscii = Character("A").asciiValue {
                
                let startIndex = Int(startAscii - aAscii)
                let endIndex = Int(endAscii - aAscii)
                
                let minIndex = min(startIndex, endIndex)
                let maxIndex = max(startIndex, endIndex)
                let isReverse = startIndex > endIndex
                
                for i in minIndex...maxIndex {
                    let actualIndex = isReverse ? (maxIndex - (i - minIndex)) : i
                    let periodAsciiValue = aAscii + UInt8(actualIndex)
                    guard periodAsciiValue >= Character("A").asciiValue! && 
                          periodAsciiValue <= Character("Z").asciiValue! else {
                        continue
                    }
                    
                    if let periodScalar = UnicodeScalar(UInt32(periodAsciiValue)) {
                        let periodLetter = String(Character(periodScalar))
                        if let classInfo = classes.first(where: { $0.period.uppercased() == periodLetter }) {
                            let teacherName = getTeacherDisplayName(for: classInfo.teacherUsername)
                            periods.append(PeriodEntry(
                                period: periodLetter,
                                className: classInfo.name,
                                teacher: teacherName,
                                room: classInfo.room,
                                time: nil,
                                image: nil
                            ))
                        } else {
                            periods.append(PeriodEntry(
                                period: periodLetter,
                                className: "Free Period",
                                teacher: nil,
                                room: nil,
                                time: nil,
                                image: nil
                            ))
                        }
                    }
                }
            }
        } else {
            let periodLetter = range.uppercased()
            if let classInfo = classes.first(where: { $0.period.uppercased() == periodLetter }) {
                let teacherName = getTeacherDisplayName(for: classInfo.teacherUsername)
                periods.append(PeriodEntry(
                    period: periodLetter,
                    className: classInfo.name,
                    teacher: teacherName,
                    room: classInfo.room,
                    time: nil,
                    image: nil
                ))
            }
        }
        
        return periods
    }
    
    func getTermID(for date: Date) -> Int {
        let calendar = Calendar.current
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        guard let normalized = calendar.date(from: comp) else { return 0 }
        
        if termRanges.isEmpty { rebuildTermRangesForCurrentSchoolYear() }
        guard termRanges.count >= 3 else { return 0 }
        
        for (index, range) in termRanges.enumerated() {
            if normalized >= range.start && normalized <= range.end {
                return index
            }
        }
        return 2
    }
    
    func getTeacherName(for username: String, completion: @escaping (String?) -> Void) {
        if let cachedName = teacherNameCache[username] {
            completion(cachedName)
            return
        }
        
        EPScheduleAPI.shared.fetchStudentDetail(username: username) { result in
            switch result {
            case .success(let json):
                let firstName = json["firstname"] as? String ?? ""
                let lastName = json["lastname"] as? String ?? ""
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                
                if !fullName.isEmpty {
                    self.teacherNameCache[username] = fullName
                    print("👤 Fetched teacher name: \(username) -> \(fullName)")
                    completion(fullName)
                } else {
                    completion(nil)
                }
            case .failure(let error):
                print("⚠️ Failed to fetch teacher name for \(username): \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
    func prefetchTeacherNames(from schedule: Schedule, completion: @escaping () -> Void) {
        var teacherUsernames: Set<String> = []
        
        for termClasses in schedule.classes {
            for classInfo in termClasses {
                if let username = classInfo.teacherUsername, !username.isEmpty {
                    teacherUsernames.insert(username)
                }
            }
        }
        
        let toFetch = teacherUsernames.filter { teacherNameCache[$0] == nil }
        
        guard !toFetch.isEmpty else {
            completion()
            return
        }
        
        print("👤 Pre-fetching \(toFetch.count) teacher names...")
        let group = DispatchGroup()
        
        for username in toFetch {
            group.enter()
            getTeacherName(for: username) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("✅ Finished pre-fetching teacher names")
            completion()
        }
    }
    
    func getTeacherDisplayName(for username: String?) -> String? {
        guard let username = username, !username.isEmpty else { return nil }
        return teacherNameCache[username] ?? username
    }
}

