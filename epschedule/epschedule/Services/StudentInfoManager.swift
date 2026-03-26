
import Foundation
import Combine

class StudentInfoManager: ObservableObject {
    @Published var studentInfo: StudentInfo = .default
    
    private let userDefaults = UserDefaults.standard
    private let studentInfoKey = "studentInfo"
    
    init() {
        loadStudentInfo()
    }
    
    func saveStudentInfo() {
        if let encoded = try? JSONEncoder().encode(studentInfo) {
            userDefaults.set(encoded, forKey: studentInfoKey)
        }
    }
    
    func loadStudentInfo() {
        if let data = userDefaults.data(forKey: studentInfoKey),
           let decoded = try? JSONDecoder().decode(StudentInfo.self, from: data) {
            studentInfo = decoded
        }
    }
    
    func updateStudentInfo(name: String, studentID: String) {
        studentInfo.name = name
        studentInfo.studentID = studentID
        studentInfo.barcode = studentID // Use student ID as barcode
        saveStudentInfo()
    }
}

