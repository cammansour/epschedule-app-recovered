
import SwiftUI

struct ClassRosterView: View {
    let period: PeriodEntry
    let termId: Int

    init(period: PeriodEntry, termId: Int) {
        self.period = period
        self.termId = termId
    }
    @StateObject private var api = EPScheduleAPI.shared
    @State private var roster: ClassRosterResponse?
    @State private var loading = true
    @State private var error: String?
    @State private var selectedUsername: String?
    @State private var showingProfile = false

    private let bg = Color(red: 0.09, green: 0.11, blue: 0.14)
    private let cardBg = Color(red: 0.21, green: 0.24, blue: 0.28)
    private let placeholder = Color(red: 0.45, green: 0.48, blue: 0.52)
    private let textPrimary = Color.white
    private let textSecondary = Color(red: 0.75, green: 0.78, blue: 0.82)

    private var studentList: [ClassRosterStudent] {
        roster?.students ?? []
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if loading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            } else if let err = error {
                Text(err)
                    .font(.system(size: 15))
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(studentList) { student in
                            Button {
                                selectedUsername = student.username
                                showingProfile = true
                            } label: {
                                studentCell(student)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(period.className)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.12, green: 0.15, blue: 0.20), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingProfile) {
            if let username = selectedUsername {
                StudentDetailSheet(username: username)
            }
        }
        .task {
            api.fetchClassRoster(period: period.period, termId: termId) { result in
                loading = false
                switch result {
                case .success(let r):
                    roster = r
                case .failure(let e):
                    error = e.localizedDescription
                }
            }
        }
    }

    private func studentCell(_ student: ClassRosterStudent) -> some View {
        VStack(spacing: 6) {
            if let urlStr = student.photo_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderIcon(student)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                placeholderIcon(student)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(student.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBg)
        )
    }

    private func placeholderIcon(_ student: ClassRosterStudent) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(placeholder)
            Image(systemName: "person.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(Color(red: 0.65, green: 0.68, blue: 0.72))
        }
    }
}
