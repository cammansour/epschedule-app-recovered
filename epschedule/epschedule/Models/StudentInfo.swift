
import Foundation
import PassKit

struct StudentInfo: Codable, Identifiable {
    var id: String { studentID }
    var name: String
    var studentID: String
    var barcode: String
    
    static let `default` = StudentInfo(
        name: "Cameron Mansour",
        studentID: "20275270",
        barcode: "20275270"
    )
}

extension StudentInfo {
    func createPass() -> PKPass? {
        return nil
    }
}

