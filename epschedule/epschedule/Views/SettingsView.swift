
import SwiftUI
import PassKit

private enum ProfileStyle {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let cardBackground = Color(red: 0.22, green: 0.22, blue: 0.23)
    static let placeholder = Color(red: 0.45, green: 0.48, blue: 0.52)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.75, green: 0.78, blue: 0.82)
    static let textTertiary = Color(red: 0.65, green: 0.68, blue: 0.72)
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var api = EPScheduleAPI.shared
    @StateObject private var scheduleService = ScheduleService.shared
    @State private var showingPassSheet = false
    @State private var barcodeImage: UIImage?
    @State private var fetchedPhotoURL: URL?
    
    private var schedule: Schedule? { api.currentUser?.schedule }
    private var studentName: String { schedule?.displayName ?? "Student" }
    private var rawStudentID: String { (schedule?.sid ?? "").trimmingCharacters(in: .whitespaces) }
    
    private var gradYearPrefix: String? {
        if let gy = schedule?.gradyear { return String(gy) }
        let id = rawStudentID
        if id.count >= 8, id.allSatisfy({ $0.isNumber }) { return String(id.prefix(4)) }
        return nil
    }
    
    private var studentID: String {
        let prefix = gradYearPrefix ?? "0000"
        let id = rawStudentID
        if gradYearPrefix != nil, id.count >= 8 { return prefix + String(id.suffix(4)) }
        return prefix + id
    }
    
    private var displayID: String {
        let gy = gradYearPrefix ?? ""
        let sid = rawStudentID
        if !gy.isEmpty && !sid.isEmpty { return gy + sid }
        if !sid.isEmpty { return sid }
        return studentID
    }
    
    private var barcodeValue: String { displayID }
    
    private var classOfText: String? {
        guard let gy = schedule?.gradyear else { return nil }
        return "Class of \(gy)"
    }
    
    private var advisorText: String? {
        guard let a = schedule?.advisor, !a.isEmpty else { return nil }
        return "Advisor: \(a)"
    }
    
    private var photoURL: URL? {
        if let s = api.currentUser?.photoURL, let u = URL(string: s) { return u }
        if let s = schedule?.photoURL, let u = URL(string: s) { return u }
        return fetchedPhotoURL
    }
    
    private var studentInfo: StudentInfo {
        StudentInfo(name: studentName, studentID: studentID, barcode: barcodeValue)
    }
    
    private var currentTermID: Int { scheduleService.getTermID(for: Date()) }
    
    private var currentTermClasses: [Class] {
        guard let schedule = schedule, currentTermID < schedule.classes.count else { return [] }
        return schedule.classes[currentTermID]
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ProfileStyle.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Student Information")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ProfileStyle.textTertiary)
                                .padding(.horizontal, 16)
                            
                            studentInformationCard
                                .padding(.horizontal, 16)
                        }
                        .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Privacy")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ProfileStyle.textTertiary)
                                .padding(.horizontal, 16)
                            
                            if api.sharePhoto != nil {
                                privacySharePhotoRow
                                    .padding(.horizontal, 16)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Student ID Card")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ProfileStyle.textTertiary)
                                .padding(.horizontal, 16)
                            
                            if !displayID.isEmpty, let barcode = barcodeImage {
                                VStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white)
                                            .frame(height: 130)
                                        Image(uiImage: barcode)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 90)
                                            .padding(.horizontal, 18)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    
                                    Text("Barcode:  \(displayID)")
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundColor(ProfileStyle.textTertiary)
                                        .padding(.bottom, 6)
                                }
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 16).fill(ProfileStyle.cardBackground))
                                .padding(.horizontal, 16)
                                
                                Button(action: { showingPassSheet = true }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "wallet.pass.fill")
                                            .foregroundColor(ProfileStyle.textPrimary)
                                        Text("Add to Apple Wallet")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(ProfileStyle.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(ProfileStyle.textTertiary)
                                    }
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(ProfileStyle.cardBackground))
                                }
                                .buttonStyle(.plain)
                                .disabled(!PKAddPassesViewController.canAddPasses())
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ProfileStyle.textTertiary)
                                .padding(.horizontal, 16)
                            
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(ProfileStyle.textSecondary)
                                Text("Version")
                                    .foregroundColor(ProfileStyle.textSecondary)
                                Spacer()
                                Text(appVersionString)
                                    .foregroundColor(ProfileStyle.textTertiary)
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(ProfileStyle.cardBackground))
                            .padding(.horizontal, 16)
                        }
                        
                        Button {
                            api.clearUserData()
                            dismiss()
                        } label: {
                            Text("Log Out")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 18).fill(ProfileStyle.cardBackground))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ProfileStyle.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(ProfileStyle.cardBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(ProfileStyle.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingPassSheet) {
                PassKitAddView(username: schedule?.username ?? "")
            }
            .onAppear {
                updateBarcode()
                scheduleService.refreshTermRangesIfNeeded()
                api.fetchPrivacySettings { _ in }
                loadOwnPhoto()
            }
            .onChange(of: api.currentUser?.schedule.sid) { _ in updateBarcode() }
        }
    }
    
    private var gradientIcon: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.purple]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(studentName.prefix(1)).uppercased())
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 110, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var studentInformationCard: some View {
        VStack(spacing: 12) {
            if let url = photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    default:
                        gradientIcon
                    }
                }
            } else {
                gradientIcon
            }
            
            Text(studentName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ProfileStyle.textPrimary)
            
            Text("ID: \(displayID)")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(ProfileStyle.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ProfileStyle.cardBackground))
    }
    
    private var privacySharePhotoRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.cyan)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Share Photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ProfileStyle.textPrimary)
                Text("Allow others to see your photo")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ProfileStyle.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { api.sharePhoto ?? false },
                set: { newValue in
                    api.updatePrivacySettings(sharePhoto: newValue) { _ in }
                }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(ProfileStyle.cardBackground))
    }
    
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "1.0.0"
    }
    
    private var profileImagePlaceholder: some View {
        Group {
            if let url = photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        placeholderContent
                    @unknown default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var placeholderContent: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(ProfileStyle.placeholder)
    }
    
    private static func periodTimeLabel(period: String) -> String {
        let times: [String: String] = [
            "A": "8:30-9:40", "B": "9:55-11:05", "C": "11:10-12:20", "D": "12:25-1:35",
            "E": "8:30-9:40", "F": "9:55-11:05", "G": "12:25-1:35", "H": "1:50-3:00"
        ]
        let time = times[period.uppercased()] ?? ""
        return time.isEmpty ? "\(period) Period" : "\(period) Period: \(time)"
    }
    
    private func profileClassCard(_ cls: Class) -> some View {
        let teacherName = scheduleService.getTeacherDisplayName(for: cls.teacherUsername) ?? cls.teacher ?? ""
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.periodTimeLabel(period: cls.period))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(ProfileStyle.textTertiary)
                Text(cls.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ProfileStyle.textPrimary)
                    .lineLimit(1)
                if !teacherName.isEmpty {
                    Text(teacherName)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(ProfileStyle.textSecondary)
                }
                if let room = cls.room, !room.isEmpty {
                    Text(room)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(ProfileStyle.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ProfileStyle.textTertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(ProfileStyle.cardBackground))
    }
    
    private func openEmail(_ email: String) {
        let urlString = "mailto:\(email)"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func updateBarcode() {
        barcodeImage = BarcodeService.shared.generateBarcode(from: barcodeValue)
    }

    private func loadOwnPhoto() {
        if photoURL != nil { return }
        guard let username = schedule?.username, !username.isEmpty else { return }
        api.fetchStudentDetail(username: username) { result in
            if case .success(let json) = result,
               let urlStr = json["photo_url"] as? String,
               let url = URL(string: urlStr) {
                fetchedPhotoURL = url
            }
        }
    }
}

struct PassKitView: UIViewControllerRepresentable {
    let studentInfo: StudentInfo
    
    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        let viewController = PKAddPassesViewController()
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {
    }
}

struct StudentIDCardView: View {
    let studentInfo: StudentInfo
    @State private var barcodeImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(uiColor: .systemGroupedBackground),
                        Color.blue.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 20) {
                            ZStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(height: 120)
                                .cornerRadius(20, corners: [.topLeft, .topRight])
                                
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.3))
                                            .frame(width: 70, height: 70)
                                        
                                        Text(String(studentInfo.name.prefix(1)))
                                            .font(.system(size: 32, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Student ID Card")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                            
                            VStack(spacing: 16) {
                                Text(studentInfo.name)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                Text("ID: \(studentInfo.studentID)")
                                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                Divider()
                                    .padding(.horizontal)
                                
                                if let barcode = barcodeImage {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white)
                                            .frame(height: 140)
                                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                        
                                        Image(uiImage: barcode)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 120)
                                            .padding()
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(uiColor: .systemBackground))
                                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal)
                        
                        VStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            
                            Text("To add to Apple Wallet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("You'll need to set up Pass Type IDs in your Apple Developer account and configure pass signing.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Student ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .onAppear {
                barcodeImage = BarcodeService.shared.generateBarcode(from: studentInfo.barcode)
            }
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct PassKitAddView: UIViewControllerRepresentable {
    let username: String
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIViewController {
        let hostVC = UIViewController()
        hostVC.view.backgroundColor = .systemBackground
        
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        hostVC.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: hostVC.view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: hostVC.view.centerYAnchor)
        ])
        
        EPScheduleAPI.shared.downloadPass(username: username) { result in
            spinner.stopAnimating()
            spinner.removeFromSuperview()
            
            switch result {
            case .success(let passData):
                do {
                    let pass = try PKPass(data: passData)
                    if let addVC = PKAddPassesViewController(passes: [pass]) {
                        addVC.delegate = context.coordinator
                        hostVC.present(addVC, animated: true)
                    } else {
                        self.showError(on: hostVC, message: "Could not create pass view")
                    }
                } catch {
                    self.showError(on: hostVC, message: "Invalid pass data: \(error.localizedDescription)")
                }
            case .failure(let error):
                self.showError(on: hostVC, message: error.localizedDescription)
            }
        }
        
        return hostVC
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }
    
    private func showError(on vc: UIViewController, message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -20)
        ])
    }
    
    class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let dismiss: DismissAction
        
        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }
        
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            dismiss()
        }
    }
}
