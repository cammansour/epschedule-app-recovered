
import SwiftUI

private enum DashboardStyle {
    static let background = Color(red: 0.09, green: 0.11, blue: 0.14)
    static let headerBar = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let cardBackground = Color(red: 0.21, green: 0.24, blue: 0.28)
    static let circlePlaceholder = Color(red: 0.45, green: 0.48, blue: 0.52)
    static let datePillBackground = Color(red: 0.35, green: 0.40, blue: 0.48)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.75, green: 0.78, blue: 0.82)
    static let textTertiary = Color(red: 0.65, green: 0.68, blue: 0.72)
}

struct ScheduleView: View {
    @StateObject private var scheduleService = ScheduleService.shared
    @StateObject private var studentManager = StudentInfoManager()
    @StateObject private var api = EPScheduleAPI.shared
    @State private var selectedDate = Date()
    @State private var showingSettings = false
    @State private var daySchedule: DaySchedule?
    @State private var userSchedule: Schedule?
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var previousDaySchedule: DaySchedule?
    @State private var nextDaySchedule: DaySchedule?
    @State private var showingSearch = false
    @State private var showingDatePicker = false
    
    var body: some View {
        NavigationView {
            ZStack {
                DashboardStyle.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    dashboardHeaderView
                        .zIndex(1)
                    
                    GeometryReader { geometry in
                        ZStack {
                            HStack(spacing: 0) {
                                if let prevSchedule = previousDaySchedule {
                                    dayContentView(schedule: prevSchedule)
                                        .frame(width: geometry.size.width)
                                }
                                
                                if let schedule = daySchedule {
                                    dayContentView(schedule: schedule)
                                        .frame(width: geometry.size.width)
                                } else {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .tint(DashboardStyle.textPrimary)
                                        .frame(width: geometry.size.width)
                                }
                                
                                if let nextSchedule = nextDaySchedule {
                                    dayContentView(schedule: nextSchedule)
                                        .frame(width: geometry.size.width)
                                }
                            }
                            .offset(x: -geometry.size.width + dragOffset)
                        }
                        .clipped()
                        .gesture(
                            DragGesture(minimumDistance: 15)
                                .onChanged { value in
                                    if abs(value.translation.width) > abs(value.translation.height) {
                                        isDragging = true
                                        dragOffset = value.translation.width
                                        
                                        if dragOffset > 50 && previousDaySchedule == nil {
                                            loadPreviousDaySchedule()
                                        } else if dragOffset < -50 && nextDaySchedule == nil {
                                            loadNextDaySchedule()
                                        }
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    let screenWidth = geometry.size.width
                                    
                                    if abs(value.translation.width) > abs(value.translation.height) {
                                        if value.translation.width > 100 {
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                dragOffset = screenWidth
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                dragOffset = 0
                                                previousDay()
                                            }
                                        } else if value.translation.width < -100 {
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                dragOffset = -screenWidth
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                dragOffset = 0
                                                nextDay()
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                dragOffset = 0
                                            }
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )
                    }
                    .blur(radius: showingDatePicker ? 18 : 0)
                }
                .allowsHitTesting(!showingDatePicker)
                
                if showingDatePicker {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.25)) {
                                showingDatePicker = false
                            }
                        }
                    
                    VStack(spacing: 0) {
                        CalendarSheetView(
                            selectedDate: $selectedDate,
                            isPresented: $showingDatePicker,
                            background: DashboardStyle.background,
                            cardBackground: DashboardStyle.cardBackground,
                            textPrimary: DashboardStyle.textPrimary,
                            textSecondary: DashboardStyle.textSecondary
                        )
                        .padding(.top, 80)
                        .padding(.horizontal, 16)
                        
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSearch) {
                StudentSearchView()
            }
            .preferredColorScheme(.dark)
            .task {
                initializeSelectedDate()
                await loadScheduleFromAPI()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                scheduleService.refreshTermRangesIfNeeded()
                initializeSelectedDate()
                updateSchedule()
                updateAdjacentSchedules()
            }
            .onChange(of: selectedDate) { _ in
                updateSchedule()
                updateAdjacentSchedules()
            }
        }
    }
    
    private func initializeSelectedDate() {
        let calendar = Calendar.current
        var today = Date()
        let weekday = calendar.component(.weekday, from: today)
        
        if weekday == 7 {
            today = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        }
        else if weekday == 1 {
            today = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        
        selectedDate = today
    }
    
    @MainActor
    private func loadScheduleFromAPI() async {
        print("📅 ========================================")
        print("📅 Starting schedule fetch from EPSchedule API...")
        print("📅 ========================================")
        
        let hasAuth = api.hasAuthenticationCookies()
        print("🔐 Has authentication cookies: \(hasAuth)")
        
        api.fetchCurrentUser { result in
            switch result {
            case .success(let userResponse):
                print("🎉 ========================================")
                print("🎉 SUCCESS! Got real schedule!")
                print("🎉 User: \(userResponse.username)")
                print("🎉 Name: \(userResponse.schedule.displayName)")
                print("🎉 Schedule has \(userResponse.schedule.classes.count) terms")
                for (index, termClasses) in userResponse.schedule.classes.enumerated() {
                    let termName = index == 0 ? "Fall" : (index == 1 ? "Winter" : "Spring")
                    print("   Term \(index) (\(termName)): \(termClasses.count) classes")
                    for cls in termClasses.prefix(3) {
                        print("     - \(cls.period): \(cls.name)")
                    }
                }
                print("🎉 ========================================")
                self.userSchedule = userResponse.schedule
                
                self.scheduleService.prefetchTeacherNames(from: userResponse.schedule) {
                    self.updateSchedule()
                    self.updateAdjacentSchedules()
                }
                
            case .failure(let error):
                print("❌ ========================================")
                print("❌ FAILED to fetch schedule!")
                print("❌ Error: \(error.localizedDescription)")
                print("❌ Falling back to MOCK schedule")
                print("❌ ========================================")
                self.createMockSchedule()
                self.updateSchedule()
                self.updateAdjacentSchedules()
            }
        }
        
        api.fetchMasterSchedule { result in
            switch result {
            case .success(let days):
                print("✅ Got master schedule with \(days.count) days")
                self.scheduleService.updateMasterSchedule(days)
                self.updateSchedule()
                self.updateAdjacentSchedules()
                
            case .failure(let error):
                print("⚠️ Failed to fetch master schedule: \(error.localizedDescription)")
            }
        }
        
        api.fetchTermStarts { result in
            switch result {
            case .success(let termStarts):
                print("✅ Got term start dates: \(termStarts)")
                self.scheduleService.updateTermStarts(termStarts)
                self.updateSchedule()
                self.updateAdjacentSchedules()
                
            case .failure(let error):
                print("⚠️ Failed to fetch term starts: \(error.localizedDescription)")
            }
        }
    }
    
    private func createMockSchedule() {
        let mockClasses: [[Class]] = [
            [
                Class(period: "A", name: "English Literature", teacher: "Smith", room: "101", termID: 0),
                Class(period: "B", name: "Calculus", teacher: "Johnson", room: "205", termID: 0),
                Class(period: "C", name: "Physics", teacher: "Williams", room: "301", termID: 0),
                Class(period: "D", name: "History", teacher: "Brown", room: "150", termID: 0),
                Class(period: "E", name: "Spanish", teacher: "Garcia", room: "220", termID: 0),
                Class(period: "F", name: "Art", teacher: "Davis", room: "400", termID: 0),
                Class(period: "G", name: "PE", teacher: "Miller", room: "Gym", termID: 0),
                Class(period: "H", name: "Study Hall", teacher: nil, room: "Library", termID: 0)
            ],
            [
                Class(period: "A", name: "English Literature", teacher: "Smith", room: "101", termID: 1),
                Class(period: "B", name: "Calculus", teacher: "Johnson", room: "205", termID: 1),
                Class(period: "C", name: "Physics", teacher: "Williams", room: "301", termID: 1),
                Class(period: "D", name: "History", teacher: "Brown", room: "150", termID: 1),
                Class(period: "E", name: "Spanish", teacher: "Garcia", room: "220", termID: 1),
                Class(period: "F", name: "Art", teacher: "Davis", room: "400", termID: 1),
                Class(period: "G", name: "PE", teacher: "Miller", room: "Gym", termID: 1),
                Class(period: "H", name: "Study Hall", teacher: nil, room: "Library", termID: 1)
            ],
            [
                Class(period: "A", name: "English Literature", teacher: "Smith", room: "101", termID: 2),
                Class(period: "B", name: "Calculus", teacher: "Johnson", room: "205", termID: 2),
                Class(period: "C", name: "Physics", teacher: "Williams", room: "301", termID: 2),
                Class(period: "D", name: "History", teacher: "Brown", room: "150", termID: 2),
                Class(period: "E", name: "Spanish", teacher: "Garcia", room: "220", termID: 2),
                Class(period: "F", name: "Art", teacher: "Davis", room: "400", termID: 2),
                Class(period: "G", name: "PE", teacher: "Miller", room: "Gym", termID: 2),
                Class(period: "H", name: "Study Hall", teacher: nil, room: "Library", termID: 2)
            ]
        ]
        
        userSchedule = Schedule(
            grade: 12, 
            classes: mockClasses, 
            username: studentManager.studentInfo.studentID,
            firstname: "Demo",
            lastname: "User (API not connected)"
        )
    }
    
    private var dashboardHeaderView: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(DashboardStyle.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(DashboardStyle.cardBackground)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showingDatePicker = true
                    }
                } label: {
                    Text(formattedDatePill(selectedDate))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DashboardStyle.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(DashboardStyle.datePillBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button { showingSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(DashboardStyle.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(DashboardStyle.cardBackground)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            
            if let schedule = daySchedule, let scheduleType = schedule.scheduleType {
                let displayType = scheduleType.split(separator: "_").first.map(String.init) ?? scheduleType
                Text(displayType)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DashboardStyle.textPrimary)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(DashboardStyle.headerBar)
    }
    
    private func dayContentView(schedule: DaySchedule) -> some View {
        VStack(spacing: 0) {
            if schedule.isNoSchool {
                noSchoolView(schedule: schedule)
            } else {
                scheduleContentView(schedule: schedule)
            }
        }
        .background(DashboardStyle.background)
    }
    
    private func scheduleContentView(schedule: DaySchedule) -> some View {
        GeometryReader { geo in
            let count = schedule.periods.count
            let totalSpacing = CGFloat(max(count - 1, 0)) * 8
            let verticalPadding: CGFloat = 10 + 10
            let cardHeight = max(50, (geo.size.height - verticalPadding - totalSpacing) / CGFloat(max(count, 1)))
            
            VStack(spacing: 8) {
                ForEach(Array(schedule.periods.enumerated()), id: \.element.id) { _, period in
                    if period.period == "LUNCH" {
                        LunchCard(lunch: schedule.lunch ?? LunchInfo(date: "", menu: period.room))
                            .frame(height: cardHeight)
                    } else {
                        PeriodCard(period: period, scheduleType: schedule.scheduleType, termId: schedule.termId)
                            .frame(height: cardHeight)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }
    
    private func noSchoolView(schedule: DaySchedule) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(DashboardStyle.cardBackground)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "building.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .foregroundColor(DashboardStyle.textSecondary)
            }
            
            VStack(spacing: 8) {
                Text(schedule.allDayEvent ?? "No School")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DashboardStyle.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("Enjoy your day off!")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DashboardStyle.textSecondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    private func previousDay() {
        let calendar = Calendar.current
        var newDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        
        let weekday = calendar.component(.weekday, from: newDate)
        if weekday == 1 {
            newDate = calendar.date(byAdding: .day, value: -2, to: newDate) ?? newDate
        }
        
        selectedDate = newDate
    }
    
    private func nextDay() {
        let calendar = Calendar.current
        var newDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        
        let weekday = calendar.component(.weekday, from: newDate)
        if weekday == 7 {
            newDate = calendar.date(byAdding: .day, value: 2, to: newDate) ?? newDate
        }
        
        selectedDate = newDate
    }
    
    private func skipWeekends(direction: Int) {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        
        if direction > 0 && weekday == 7 { // Saturday
            selectedDate = calendar.date(byAdding: .day, value: 2, to: selectedDate) ?? selectedDate
        } else if direction < 0 && weekday == 1 { // Sunday
            selectedDate = calendar.date(byAdding: .day, value: -2, to: selectedDate) ?? selectedDate
        }
    }
    
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, M/d"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    private func formattedDatePill(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    private func updateSchedule() {
        if userSchedule == nil {
            createMockSchedule()
        }
        
        guard let schedule = userSchedule else {
            let fallbackClasses: [[Class]] = [[], [], []]
            userSchedule = Schedule(classes: fallbackClasses, username: studentManager.studentInfo.studentID)
            daySchedule = scheduleService.getDaySchedule(for: selectedDate, userSchedule: userSchedule!)
            updateAdjacentSchedules()
            return
        }
        
        daySchedule = scheduleService.getDaySchedule(for: selectedDate, userSchedule: schedule)
        updateAdjacentSchedules()
    }
    
    private func updateAdjacentSchedules() {
        guard let schedule = userSchedule else { return }
        
        let calendar = Calendar.current
        
        if let prevDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
            previousDaySchedule = scheduleService.getDaySchedule(for: prevDate, userSchedule: schedule)
        }
        
        if let nextDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
            nextDaySchedule = scheduleService.getDaySchedule(for: nextDate, userSchedule: schedule)
        }
    }
    
    private func loadPreviousDaySchedule() {
        guard let schedule = userSchedule else { return }
        let calendar = Calendar.current
        if let prevDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
            previousDaySchedule = scheduleService.getDaySchedule(for: prevDate, userSchedule: schedule)
        }
    }
    
    private func loadNextDaySchedule() {
        guard let schedule = userSchedule else { return }
        let calendar = Calendar.current
        if let nextDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
            nextDaySchedule = scheduleService.getDaySchedule(for: nextDate, userSchedule: schedule)
        }
    }
}

private struct CalendarSheetView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    let background: Color
    let cardBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    
    @State private var monthAnchor: Date = Date()
    @State private var showingMonthPicker = false
    
    private let calendar = Calendar.current
    private let scheduleService = ScheduleService.shared
    
    private let noSchoolKeywords = ["Break", "No School", "Convocation", "Orientations", "Conferences", "PDD", "Presidents", "Voices", "Veterans", "Student Led", "EBC"]
    
    private func isNoSchoolDay(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return true }
        guard let scheduleType = scheduleService.getScheduleType(for: date) else { return true }
        return noSchoolKeywords.contains(where: { scheduleType.contains($0) })
    }
    
    var body: some View {
        calendarCard
            .onAppear {
                monthAnchor = firstOfMonth(for: selectedDate)
            }
    }
    
    private var calendarCard: some View {
        VStack(spacing: 14) {
            header
            
            if showingMonthPicker {
                monthYearPicker
            } else {
                Button {
                    selectedDate = startOfDay(Date())
                    monthAnchor = firstOfMonth(for: selectedDate)
                } label: {
                    Text("Today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(cardBackground.opacity(0.55))
                        .overlay(
                            Capsule()
                                .stroke(textSecondary.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                
                weekdayRow
                
                monthGrid
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.11, green: 0.13, blue: 0.17).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showingMonthPicker.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(monthTitle(for: monthAnchor))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(textPrimary)
                    Image(systemName: showingMonthPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textSecondary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                monthAnchor = addMonths(monthAnchor, -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textPrimary)
                    .frame(width: 36, height: 36)
                    .background(cardBackground.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Button {
                monthAnchor = addMonths(monthAnchor, 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textPrimary)
                    .frame(width: 36, height: 36)
                    .background(cardBackground.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var monthYearPicker: some View {
        let months = Calendar.current.shortMonthSymbols
        let currentYear = calendar.component(.year, from: Date())
        let years = Array((currentYear - 2)...(currentYear + 2))
        let selectedMonth = calendar.component(.month, from: monthAnchor)
        let selectedYear = calendar.component(.year, from: monthAnchor)
        
        return VStack(spacing: 16) {
            HStack(spacing: 0) {
                ForEach(years, id: \.self) { year in
                    Button {
                        var comps = calendar.dateComponents([.year, .month], from: monthAnchor)
                        comps.year = year
                        if let newDate = calendar.date(from: comps) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                monthAnchor = newDate
                            }
                        }
                    } label: {
                        Text(String(year))
                            .font(.system(size: 14, weight: year == selectedYear ? .bold : .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundColor(year == selectedYear ? textPrimary : textSecondary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                year == selectedYear
                                    ? Color(red: 0.2, green: 0.35, blue: 0.65).opacity(0.5)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
            LazyVGrid(columns: monthColumns, spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        var comps = calendar.dateComponents([.year, .month], from: monthAnchor)
                        comps.month = month
                        if let newDate = calendar.date(from: comps) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                monthAnchor = newDate
                                showingMonthPicker = false
                            }
                        }
                    } label: {
                        Text(months[month - 1])
                            .font(.system(size: 15, weight: month == selectedMonth ? .bold : .medium))
                            .foregroundColor(month == selectedMonth ? textPrimary : textSecondary.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                month == selectedMonth
                                    ? Color(red: 0.2, green: 0.35, blue: 0.65).opacity(0.5)
                                    : cardBackground.opacity(0.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var weekdayRow: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return HStack {
            ForEach(symbols.indices, id: \.self) { idx in
                Text(symbols[idx].uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(textSecondary.opacity(0.75))
                    .frame(maxWidth: .infinity, minHeight: 18)
            }
        }
    }
    
    private var monthGrid: some View {
        let days = daysInMonthGrid(for: monthAnchor)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(days, id: \.id) { day in
                Button {
                    guard let date = day.date else { return }
                    selectedDate = startOfDay(date)
                } label: {
                    CalendarDayCell(
                        label: day.label,
                        isCurrentMonth: day.isCurrentMonth,
                        isSelected: day.isSelected,
                        isNoSchool: day.isNoSchool,
                        background: background,
                        cardBackground: cardBackground,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary
                    )
                }
                .buttonStyle(.plain)
                .disabled(day.date == nil)
            }
        }
    }
    
    private func daysInMonthGrid(for month: Date) -> [CalendarDay] {
        let first = firstOfMonth(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        
        let firstWeekday = calendar.component(.weekday, from: first)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let total = offset + range.count
        let paddedTotal = Int(ceil(Double(total) / 7.0)) * 7
        
        var result: [CalendarDay] = []
        result.reserveCapacity(paddedTotal)
        
        for i in 0..<paddedTotal {
            let dayIndex = i - offset + 1
            if dayIndex < 1 {
                result.append(.empty)
            } else if dayIndex > range.count {
                result.append(.empty)
            } else {
                if let date = calendar.date(byAdding: .day, value: dayIndex - 1, to: first) {
                    result.append(makeDay(for: date, isCurrentMonth: true))
                } else {
                    result.append(.empty)
                }
            }
        }
        return result
    }
    
    private func makeDay(for date: Date, isCurrentMonth: Bool) -> CalendarDay {
        let day = calendar.component(.day, from: date)
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let noSchool = isNoSchoolDay(date)
        return CalendarDay(date: date, label: "\(day)", isCurrentMonth: isCurrentMonth, isSelected: selected, isNoSchool: noSchool)
    }
    
    private func monthTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale.current
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
    
    private func firstOfMonth(for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }
    
    private func addMonths(_ date: Date, _ delta: Int) -> Date {
        calendar.date(byAdding: .month, value: delta, to: date) ?? date
    }
    
    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

private struct CalendarDayCell: View {
    let label: String
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isNoSchool: Bool
    let background: Color
    let cardBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(circleFill)
                .frame(width: 36, height: 36)
            
            if isSelected {
                Circle()
                    .stroke(textPrimary.opacity(0.9), lineWidth: 2)
                    .frame(width: 36, height: 36)
            }
            
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(textColor)
                .frame(width: 36, height: 36)
        }
        .opacity(label.isEmpty ? 0.0 : 1.0)
    }
    
    private var circleFill: Color {
        if !isCurrentMonth || label.isEmpty {
            return .clear
        }
        if isNoSchool {
            return Color(red: 0.12, green: 0.18, blue: 0.35)
        }
        return Color.white.opacity(0.08)
    }
    
    private var textColor: Color {
        if label.isEmpty { return .clear }
        if isCurrentMonth { return textPrimary }
        return textSecondary.opacity(0.35)
    }
}

private struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    let label: String
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isNoSchool: Bool
    
    static let empty = CalendarDay(date: nil, label: "", isCurrentMonth: false, isSelected: false, isNoSchool: false)
}

struct PeriodCard: View {
    let period: PeriodEntry
    var scheduleType: String?
    var termId: Int = 0
    
    @State private var isShowingRoster = false
    
    private var isMiddleBand: Bool { period.period == "MB" }
    private var isFreePeriod: Bool {
        period.className.lowercased().contains("free") || (period.teacher == nil && period.room == nil && !isMiddleBand)
    }
    private var canShowRoster: Bool { !isMiddleBand }
    
    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture {
                if canShowRoster {
                    isShowingRoster = true
                }
            }
            .background(
                NavigationLink(
                    destination: ClassRosterView(period: period, termId: termId),
                    isActive: $isShowingRoster
                ) { EmptyView() }
                .opacity(0)
                .allowsHitTesting(false)
            )
    }
    
    private var cardContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(DashboardStyle.circlePlaceholder)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                if let timeLine = period.time {
                    Text(timeLine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(DashboardStyle.textTertiary)
                }
                Text(period.className)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DashboardStyle.textPrimary)
                    .lineLimit(1)
                if isMiddleBand {
                    let detail = [period.teacher, period.room].compactMap { $0 }.joined(separator: " • ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DashboardStyle.textSecondary)
                            .lineLimit(1)
                    }
                } else if isFreePeriod {
                    Text("–")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DashboardStyle.textSecondary)
                } else {
                    if let teacher = period.teacher {
                        Text(teacher)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DashboardStyle.textSecondary)
                            .lineLimit(1)
                    }
                    if let room = period.room {
                        Text(room)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(DashboardStyle.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            if canShowRoster {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DashboardStyle.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DashboardStyle.cardBackground)
        )
    }
}

struct LunchCard: View {
    let lunch: LunchInfo
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(DashboardStyle.circlePlaceholder)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Lunch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DashboardStyle.textPrimary)
                Text(lunch.menu ?? "Check cafeteria for today's menu")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DashboardStyle.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DashboardStyle.cardBackground)
        )
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

