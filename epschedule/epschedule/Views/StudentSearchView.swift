
import SwiftUI

struct StudentSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var api = EPScheduleAPI.shared

    @State private var query = ""
    @State private var results: [EPSStudentSummary] = []
    @State private var isLoading = false
    @State private var selectedStudent: EPSStudentSummary?
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private let bg = Color(red: 0.09, green: 0.11, blue: 0.14)
    private let cardBg = Color(red: 0.21, green: 0.24, blue: 0.28)
    private let textPrimary = Color.white
    private let textSecondary = Color(red: 0.75, green: 0.78, blue: 0.82)
    private let textTertiary = Color(red: 0.65, green: 0.68, blue: 0.72)

    var body: some View {
        NavigationView {
            ZStack {
                bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if !api.isAuthenticated && query.isEmpty {
                        Text("Please log in to search for students.")
                            .font(.system(size: 14))
                            .foregroundColor(textTertiary)
                            .padding(.top, 24)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                            .padding(.top, 24)
                    } else if results.isEmpty && !query.isEmpty && !isLoading {
                        Text("No students found")
                            .foregroundColor(textTertiary)
                            .font(.system(size: 14))
                            .padding(.top, 24)
                    }

                    if !results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, student in
                                Button {
                                    selectedStudent = student
                                } label: {
                                    Text(student.name)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < results.count - 1 {
                                    Divider()
                                        .background(textTertiary.opacity(0.15))
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(cardBg)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Search Students")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(cardBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(item: $selectedStudent) { student in
                StudentDetailSheet(username: student.username)
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(textTertiary)
                .font(.system(size: 16))

            TextField("", text: $query)
                .foregroundColor(textPrimary)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, newValue in
                    searchTask?.cancel()

                    if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        results = []
                        isLoading = false
                        return
                    }

                    isLoading = true
                    errorMessage = nil
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled else { return }

                        api.searchStudents(query: newValue) { result in
                            guard !Task.isCancelled else { return }
                            isLoading = false
                            switch result {
                            case .success(let students):
                                results = Array(students.prefix(5))
                                errorMessage = nil
                            case .failure(let error):
                                results = []
                                let nsError = error as NSError
                                if nsError.code == 403 {
                                    errorMessage = "Authentication required. Please log in first."
                                } else {
                                    errorMessage = "Error: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(textTertiary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBg)
        )
    }
}

struct StudentDetailSheet: View {
    let username: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var api = EPScheduleAPI.shared
    @State private var detail: [String: Any]?
    @State private var isLoading = false

    private let bg = Color(red: 0.09, green: 0.11, blue: 0.14)
    private let cardBg = Color(red: 0.21, green: 0.24, blue: 0.28)
    private let textPrimary = Color.white
    private let textSecondary = Color(red: 0.75, green: 0.78, blue: 0.82)
    private let textTertiary = Color(red: 0.65, green: 0.68, blue: 0.72)

    var body: some View {
        NavigationView {
            ZStack {
                bg.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(textPrimary)
                } else if let detail {
                    StudentDetailContent(
                        detail: detail,
                        bg: bg,
                        cardBg: cardBg,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        textTertiary: textTertiary
                    )
                } else {
                    Text("Unable to load student details.")
                        .foregroundColor(textSecondary)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(cardBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
            .onAppear(perform: load)
        }
    }

    private func load() {
        isLoading = true
        api.fetchStudentDetail(username: username) { result in
            switch result {
            case .success(let json):
                detail = json
                prefetchTeacherNames(from: json) {
                    isLoading = false
                }
            case .failure:
                detail = nil
                isLoading = false
            }
        }
    }

    private func prefetchTeacherNames(from json: [String: Any], completion: @escaping () -> Void) {
        guard let classes = json["classes"] as? [[Any]] else {
            completion()
            return
        }
        var usernames: Set<String> = []
        for term in classes {
            guard let termClasses = term as? [[String: Any]] else { continue }
            for cls in termClasses {
                if let tu = cls["teacher_username"] as? String, !tu.isEmpty {
                    usernames.insert(tu)
                }
            }
        }
        let scheduleService = ScheduleService.shared
        let toFetch = usernames.filter { scheduleService.getTeacherDisplayName(for: $0) == $0 }
        guard !toFetch.isEmpty else { completion(); return }

        let group = DispatchGroup()
        for u in toFetch {
            group.enter()
            scheduleService.getTeacherName(for: u) { _ in group.leave() }
        }
        group.notify(queue: .main) { completion() }
    }
}

private struct StudentDetailContent: View {
    let detail: [String: Any]
    let bg: Color
    let cardBg: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    @StateObject private var scheduleService = ScheduleService.shared
    @StateObject private var api = EPScheduleAPI.shared
    @State private var resolvedAdvisorName: String?
    @State private var tappedPeriod: String?
    @State private var tappedClassName: String?
    @State private var showingRoster = false

    private var photoURL: URL? {
        if let urlString = detail["photo_url"] as? String {
            return URL(string: urlString)
        }
        return nil
    }

    private var fullName: String {
        let preferred = detail["preferred_name"] as? String
        let first = preferred ?? (detail["firstname"] as? String ?? "")
        let last = detail["lastname"] as? String ?? ""
        let combined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? "Unknown Student" : combined
    }

    private var studentUsername: String {
        detail["username"] as? String ?? ""
    }

    private var email: String {
        detail["email"] as? String ?? studentUsername
    }

    private var gradYear: Int? {
        detail["gradyear"] as? Int
    }

    private var advisor: String? {
        detail["advisor"] as? String
    }

    private var currentTermClasses: [[String: Any]] {
        guard let classes = detail["classes"] as? [[Any]] else { return [] }
        let termID = scheduleService.getTermID(for: Date())
        guard termID < classes.count, let term = classes[termID] as? [[String: Any]] else {
            if let first = classes.first as? [[String: Any]] { return first }
            return []
        }
        return term
    }

    private var myClasses: [Class] {
        guard let sched = api.currentUser?.schedule else { return [] }
        let termID = scheduleService.getTermID(for: Date())
        guard termID < sched.classes.count else { return [] }
        return sched.classes[termID]
    }

    private func isSharedClass(_ cls: [String: Any]) -> Bool {
        let period = (cls["period"] as? String ?? "").uppercased()
        let name = cls["name"] as? String ?? ""
        let teacher = cls["teacher_username"] as? String ?? ""
        return myClasses.contains { mine in
            mine.period.uppercased() == period &&
            mine.name == name &&
            (mine.teacherUsername ?? "") == teacher
        }
    }

    private static let periodTimes: [String: String] = [
        "A": "8:30-9:40", "B": "9:55-11:05", "C": "11:10-12:20", "D": "12:25-1:35",
        "E": "8:30-9:40", "F": "9:55-11:05", "G": "12:25-1:35", "H": "1:50-3:00"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                profileHeader
                    .padding(.bottom, 8)

                ForEach(currentTermClasses.indices, id: \.self) { idx in
                    let cls = currentTermClasses[idx]
                    let shared = isSharedClass(cls)
                    if shared {
                        Button {
                            tappedPeriod = cls["period"] as? String ?? ""
                            tappedClassName = cls["name"] as? String ?? "Class"
                            showingRoster = true
                        } label: {
                            classCard(cls, showChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        classCard(cls, showChevron: false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showingRoster) {
            if let period = tappedPeriod {
                NavigationView {
                    ClassRosterView(
                        period: PeriodEntry(
                            period: period,
                            className: tappedClassName ?? "Class",
                            teacher: nil, room: nil, time: nil, image: nil
                        ),
                        termId: scheduleService.getTermID(for: Date())
                    )
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 8) {
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 20)
                            .fill(cardBg)
                    }
                }
                .frame(width: 130, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            Text(fullName)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(textPrimary)

            if let gy = gradYear {
                Text("Class of \(String(gy))")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(textSecondary)
            }

            if let adv = advisor, !adv.isEmpty {
                Text("Advisor: \(resolvedAdvisorName ?? adv)")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(textSecondary)
                    .onAppear {
                        if resolvedAdvisorName == nil {
                            scheduleService.getTeacherName(for: adv) { fullName in
                                if let name = fullName {
                                    resolvedAdvisorName = name
                                }
                            }
                        }
                    }
            }

            if !email.isEmpty {
                Button {
                    let addr = email.contains("@") ? email : "\(email)@eastsideprep.org"
                    if let url = URL(string: "mailto:\(addr)"), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Email (click)")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func classCard(_ cls: [String: Any], showChevron: Bool = false) -> some View {
        let period = cls["period"] as? String ?? ""
        let name = cls["name"] as? String ?? "Class"
        let teacherUsername = cls["teacher_username"] as? String
        let teacher = cls["teacher"] as? String
        let room = cls["room"] as? String
        let isFreePeriod = name.lowercased().contains("free")
        let isAdvisory = period.lowercased().contains("adv") || name.lowercased().contains("advisory")

        let timeStr: String = {
            if isAdvisory { return "Advisory Period" }
            if let t = Self.periodTimes[period.uppercased()] {
                return "\(period) Period: \(t)"
            }
            return "\(period) Period"
        }()

        let teacherDisplay: String? = {
            if isFreePeriod { return nil }
            if let tu = teacherUsername {
                return scheduleService.getTeacherDisplayName(for: tu)
            }
            return teacher
        }()

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeStr)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(textTertiary)
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(textPrimary)
                    .lineLimit(1)
                if isFreePeriod {
                    EmptyView()
                } else {
                    if let t = teacherDisplay {
                        Text(t)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(textSecondary)
                            .lineLimit(1)
                    }
                    if let r = room, !r.isEmpty {
                        Text(r)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textTertiary)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBg)
        )
    }
}

