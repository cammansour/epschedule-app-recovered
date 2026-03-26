
import Foundation

struct Schedule: Codable {
    var grade: Int?
    var gradyear: Int?
    var classes: [[Class]]
    var username: String?
    var firstname: String?
    var lastname: String?
    var preferredName: String?
    var email: String?
    var photoURL: String?
    var earlyDismissal: Bool?
    var sid: String? // Can be number or string in JSON
    var advisor: String?
    
    enum CodingKeys: String, CodingKey {
        case grade, gradyear, classes, username, firstname, lastname, email, sid, advisor
        case preferredName = "preferred_name"
        case photoURL = "photo_url"
        case earlyDismissal = "early_dismissal"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        grade = try container.decodeIfPresent(Int.self, forKey: .grade)
        gradyear = try container.decodeIfPresent(Int.self, forKey: .gradyear)
        classes = try container.decode([[Class]].self, forKey: .classes)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        preferredName = try container.decodeIfPresent(String.self, forKey: .preferredName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        earlyDismissal = try container.decodeIfPresent(Bool.self, forKey: .earlyDismissal)
        advisor = try container.decodeIfPresent(String.self, forKey: .advisor)
        
        if let sidString = try? container.decodeIfPresent(String.self, forKey: .sid) {
            sid = sidString
        } else if let sidInt = try? container.decodeIfPresent(Int.self, forKey: .sid) {
            sid = String(sidInt)
        } else {
            sid = nil
        }
    }
    
    init(
        grade: Int? = nil,
        gradyear: Int? = nil,
        classes: [[Class]],
        username: String? = nil,
        firstname: String? = nil,
        lastname: String? = nil,
        preferredName: String? = nil,
        email: String? = nil,
        photoURL: String? = nil,
        earlyDismissal: Bool? = nil,
        sid: String? = nil,
        advisor: String? = nil
    ) {
        self.grade = grade
        self.gradyear = gradyear
        self.classes = classes
        self.username = username
        self.firstname = firstname
        self.lastname = lastname
        self.preferredName = preferredName
        self.email = email
        self.photoURL = photoURL
        self.earlyDismissal = earlyDismissal
        self.sid = sid
        self.advisor = advisor
    }
    
    var displayName: String {
        let first = preferredName ?? firstname ?? ""
        let last = lastname ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }
    
    var computedGrade: Int? {
        if let g = grade {
            return g
        }
        guard let gradyear = gradyear else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())
        let schoolYear = currentMonth >= 7 ? currentYear + 1 : currentYear
        return 12 - (gradyear - schoolYear)
    }
}

struct Class: Codable, Identifiable {
    var id: String { "\(period)-\(termID)" }
    var period: String
    var name: String
    var teacher: String?
    var teacherUsername: String?
    var room: String?
    var department: String?
    var termID: Int
    
    enum CodingKeys: String, CodingKey {
        case period, name, teacher, room, department
        case teacherUsername = "teacher_username"
    }
    
    init(period: String, name: String, teacher: String? = nil, teacherUsername: String? = nil, room: String? = nil, department: String? = nil, termID: Int = 0) {
        self.period = period
        self.name = name
        self.teacher = teacher
        self.teacherUsername = teacherUsername
        self.room = room
        self.department = department
        self.termID = termID
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(String.self, forKey: .period)
        name = try container.decode(String.self, forKey: .name)
        teacher = try container.decodeIfPresent(String.self, forKey: .teacher)
        teacherUsername = try container.decodeIfPresent(String.self, forKey: .teacherUsername)
        room = try container.decodeIfPresent(String.self, forKey: .room)
        department = try container.decodeIfPresent(String.self, forKey: .department)
        termID = 0 // Will be set from context
    }
    
    var teacherDisplayName: String? {
        teacher ?? teacherUsername
    }
}

struct PeriodEntry: Identifiable {
    var id: String { "\(period)-\(className)-\(time ?? "")" }
    var period: String
    var className: String
    var teacher: String?
    var room: String?
    var time: String?
    var image: String?
}

struct DaySchedule {
    var date: Date
    var scheduleType: String? // e.g., "A-D_Mon", "E-H_Tue"
    var periods: [PeriodEntry]
    var lunch: LunchInfo?
    var isNoSchool: Bool
    var allDayEvent: String?
    var termId: Int
}

struct LunchInfo: Codable {
    var date: String
    var menu: String?
}

struct MasterSchedule: Codable {
    var days: [String: String] // Date string -> Schedule type name
    var dayTypes: [String: [DaySlot]] // Schedule type name -> ordered array of slots
}

struct DaySlot: Codable {
    let period: String  // e.g. "E", "Lunch (US)", "Advisory - US"
    let times: String   // e.g. "08:30-09:40"
}

