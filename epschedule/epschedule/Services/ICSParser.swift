
import Foundation

struct ICSEvent {
    let summary: String
    let location: String?
    let startDate: Date
    let endDate: Date
    let category: String?
}

class ICSParser {
    static func parseICSFile(at url: URL) -> [ICSEvent] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        
        var events: [ICSEvent] = []
        var currentEvent: [String: String] = [:]
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed == "BEGIN:VEVENT" {
                currentEvent = [:]
            } else if trimmed == "END:VEVENT" {
                if let event = parseEvent(from: currentEvent) {
                    events.append(event)
                }
                currentEvent = [:]
            } else if trimmed.contains(":") {
                let components = trimmed.split(separator: ":", maxSplits: 1)
                if components.count == 2 {
                    let key = String(components[0])
                    let value = String(components[1])
                    currentEvent[key] = value
                }
            }
        }
        
        allEvents = events
        
        return events
    }
    
    private static func parseEvent(from dict: [String: String]) -> ICSEvent? {
        guard let summary = dict["SUMMARY"] else { return nil }
        
        let cleanSummary = summary.replacingOccurrences(
            of: "\\s*\\[Day\\s+\\d+\\s+of\\s+\\d+\\]",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        
        let location = dict["LOCATION"]
        let category = dict["CATEGORIES"]
        
        var startDate: Date?
        var endDate: Date?
        
        for key in dict.keys {
            if key.hasPrefix("DTSTART") {
                startDate = parseICSDate(dict[key] ?? "")
                break
            }
        }
        
        for key in dict.keys {
            if key.hasPrefix("DTEND") {
                endDate = parseICSDate(dict[key] ?? "")
                break
            }
        }
        
        guard let start = startDate, let end = endDate else { return nil }
        
        return ICSEvent(
            summary: cleanSummary,
            location: location,
            startDate: start,
            endDate: end,
            category: category
        )
    }
    
    private static func parseICSDate(_ dateString: String) -> Date? {
        let cleanString = dateString.replacingOccurrences(of: "Z", with: "")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        
        return formatter.date(from: cleanString)
    }
    
    static func convertToSchedule(events: [ICSEvent]) -> Schedule {
        let excludedClasses = ["Chamber Choir"]
        
        let periodMapping: [String: String] = [
            "Calculus": "A",
            "US History": "B",
            "United States History": "B",
            "American Literature": "D",
            "Advanced Biology": "E",
            "Physics": "F",
            "Spanish 4": "G",
            "Spanish": "G"
        ]
        
        func simplifyName(_ name: String) -> String {
            var simplified = name
            
            if simplified.contains("Eaglecon") {
                return "Eaglecon"
            }
            if simplified.contains("Class Meeting") || simplified.contains("Assembly") {
                return "Assembly"
            }
            if simplified.contains("Advisory") {
                return "Advisory"
            }
            if simplified.contains("Clubs") || simplified.contains("Activities") {
                return "Clubs"
            }
            if simplified.contains("US Flex") || simplified.contains("Flex") {
                return "US Flex"
            }
            if simplified.contains("AI Ethics") {
                return "AI Ethics"
            }
            if simplified.contains("Seminars") || simplified.contains("Office Hours") {
                return "Seminars"
            }
            
            simplified = simplified.replacingOccurrences(of: " - US", with: "")
            simplified = simplified.replacingOccurrences(of: " - MS", with: "")
            
            return simplified
        }
        
        var classMap: [String: (name: String, location: String?, category: String?)] = [:]
        
        for event in events {
            let eventName = event.summary
            if excludedClasses.contains(where: { eventName.contains($0) }) {
                continue
            }
            
            let classKey = event.category ?? event.summary
            
            if classMap[classKey] == nil {
                let simplifiedName = simplifyName(event.summary)
                classMap[classKey] = (
                    name: simplifiedName,
                    location: event.location,
                    category: event.category
                )
            }
        }
        
        var classes: [Class] = []
        let periodOrder = ["A", "B", "C", "D", "E", "F", "G", "H"]
        
        for (classKey, classInfo) in classMap {
            var period: String? = nil
            
            if let category = classInfo.category, let mappedPeriod = periodMapping[category] {
                period = mappedPeriod
            }
            else {
                for (key, mappedPeriod) in periodMapping {
                    if classInfo.name.contains(key) || classKey.contains(key) {
                        period = mappedPeriod
                        break
                    }
                }
            }
            
            if let period = period {
                classes.append(Class(
                    period: period,
                    name: classInfo.name,
                    teacher: nil, // Not in ICS file
                    room: classInfo.location,
                    termID: 0 // Default to fall term
                ))
            }
        }
        
        
        let existingPeriods = Set(classes.map { $0.period })
        if !existingPeriods.contains("C") {
            classes.append(Class(
                period: "C",
                name: "Free Period",
                teacher: nil,
                room: nil,
                termID: 0
            ))
        }
        if !existingPeriods.contains("H") {
            classes.append(Class(
                period: "H",
                name: "Free Period",
                teacher: nil,
                room: nil,
                termID: 0
            ))
        }
        
        classes.sort { periodOrder.firstIndex(of: $0.period) ?? 99 < periodOrder.firstIndex(of: $1.period) ?? 99 }
        
        
        if let advisoryInfo = classMap["Advisory"] {
        }
        
        return Schedule(
            grade: 12,
            classes: [classes, classes, classes], // Same classes for all trimesters for now
            username: "cammansour"
        )
    }
    
    static var allEvents: [ICSEvent] = []
    
    static func getMiddleBandActivities(for date: Date) -> [ICSEvent] {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
        let middleBandKeywords = ["Advisory", "Assembly", "Clubs", "US Flex", "AI Ethics", "Seminars", "Class Meeting"]
        
        return allEvents.filter { event in
            let eventComponents = calendar.dateComponents([.year, .month, .day], from: event.startDate)
            return eventComponents.year == dateComponents.year &&
                   eventComponents.month == dateComponents.month &&
                   eventComponents.day == dateComponents.day &&
                   middleBandKeywords.contains { event.summary.contains($0) }
        }
    }
}

