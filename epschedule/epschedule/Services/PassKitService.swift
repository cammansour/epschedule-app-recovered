
import Foundation
import PassKit
import Security
import CryptoKit
import Compression
import Combine

final class PassKitService {
    static let shared = PassKitService()
    
    private let passTypeIdentifier = "pass.eps.epschedule"
    
    private let teamIdentifier: String = {
        if let teamId = Bundle.main.object(forInfoDictionaryKey: "APPLE_TEAM_IDENTIFIER") as? String,
           !teamId.isEmpty {
            return teamId
        }
        return ""
    }()
    
    private init() {
        print("🟢 [DEBUG] PassKitService.shared initialized")
    }
    
    func createStudentIDPass(studentInfo: StudentInfo) throws -> PKPass {
        
        print("🔄 Creating pass for student: \(studentInfo.name)")
        
        var passDictionary: [String: Any] = [
            "formatVersion": 1,
            "passTypeIdentifier": passTypeIdentifier,
            "serialNumber": studentInfo.studentID,
            "teamIdentifier": teamIdentifier,
            "organizationName": "Eastside Preparatory School",
            "description": "Student ID Card",
            "logoText": "EPS",
            "foregroundColor": "rgb(0, 0, 0)",
            "backgroundColor": "rgb(255, 255, 255)",
            "generic": [
                "primaryFields": [
                    [
                        "key": "name",
                        "label": "Name",
                        "value": studentInfo.name
                    ]
                ],
                "secondaryFields": [
                    [
                        "key": "id",
                        "label": "Student ID",
                        "value": studentInfo.studentID
                    ]
                ],
                "barcode": [
                    "message": studentInfo.barcode,
                    "format": "PKBarcodeFormatCode128",
                    "messageEncoding": "iso-8859-1"
                ]
            ]
        ]
        
        let calendar = Calendar.current
        if let expirationDate = calendar.date(byAdding: .year, value: 1, to: Date()) {
            passDictionary["expirationDate"] = ISO8601DateFormatter().string(from: expirationDate)
        }
        
        let passData = try JSONSerialization.data(withJSONObject: passDictionary, options: [])
        print("✅ Created pass.json (\(passData.count) bytes)")
        
        let signedPassData = try signPass(passData: passData)
        print("✅ Signed pass package (\(signedPassData.count) bytes)")
        
        guard let pass = try? PKPass(data: signedPassData) else {
            throw PassKitError.passCreationFailed
        }
        
        
        print("✅ Successfully created PKPass")
        return pass
    }
    
    func signPass(passData: Data) throws -> Data {
        
        let certNames = ["Certificates_ios", "Certificates", "pass", "certificate", "epschedule"]
        var certURL: URL?
        var certData: Data?
        
        print("🔍 Searching for certificate...")
        for baseName in certNames {
            for ext in ["p12", "cer"] {
                if let url = Bundle.main.url(forResource: baseName, withExtension: ext) {
                    certURL = url
                    certData = try? Data(contentsOf: url)
                    if certData != nil {
                        print("✅ Found certificate: \(baseName).\(ext) at \(url.path)")
                        break
                    }
                }
            }
            if certData != nil { break }
        }
        
        guard let data = certData else {
            print("❌ Certificate not found. Searched for: \(certNames.joined(separator: ", "))")
            print("   Bundle path: \(Bundle.main.bundlePath)")
            throw PassKitError.certificateNotFound
        }
        
        let certPassword = ""
        
        var items: CFArray?
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: certPassword
        ]
        
        print("🔐 Importing certificate...")
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        if status != errSecSuccess {
            print("❌ Certificate import failed with status: \(status)")
        }
        guard status == errSecSuccess,
              let itemsArray = items as? [[String: Any]],
              let identityDict = itemsArray.first,
              let identity = identityDict[kSecImportItemIdentity as String] as! SecIdentity? else {
            if certURL?.pathExtension == "cer" {
                throw PassKitError.certificateNeedsConversion
            }
            throw PassKitError.certificateImportFailed
        }
        
        print("✅ Certificate imported successfully")
        
        var privateKey: SecKey?
        let keyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard keyStatus == errSecSuccess, let key = privateKey else {
            print("❌ Failed to get private key: \(keyStatus)")
            throw PassKitError.privateKeyNotFound
        }
        
        print("✅ Got private key, signing pass...")
        
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            passData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                print("❌ Signing error: \(error)")
            }
            throw PassKitError.signingFailed
        }
        
        print("✅ Pass signed successfully")
        
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        var certificateDER = Data()
        if let cert = certRef {
            certificateDER = SecCertificateCopyData(cert) as Data
        }
        
        let pkcs7Signature = createPKCS7Signature(rawSignature: signature, certificate: certificateDER, manifestHash: passData.sha1HashBytes)
        print("📝 Created PKCS#7 signature (\(pkcs7Signature.count) bytes)")
        
        return try createPassPackage(passData: passData, signature: pkcs7Signature, certificate: certificateDER)
    }
    
    private func createManifest(passData: Data, signature: Data) -> [String: String] {
        var manifest: [String: String] = [:]
        
        manifest["pass.json"] = passData.sha1Hash
        
        manifest["signature"] = signature.sha1Hash
        
        return manifest
    }
    

    private func createPKCS7Signature(rawSignature: Data, certificate: Data, manifestHash: [UInt8]) -> Data {
        
        var pkcs7 = Data()
        
        let signedDataOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
        
        let sha256OID: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
        
        let dataOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]
        
        let rsaOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        
        var signedData = Data()
        
        signedData.append(contentsOf: [0x02, 0x01, 0x01])
        
        var digestAlgSet = Data()
        var digestAlgSeq = Data()
        digestAlgSeq.append(contentsOf: sha256OID)
        digestAlgSeq.append(contentsOf: [0x05, 0x00]) // NULL
        digestAlgSet.append(contentsOf: wrapSequence(digestAlgSeq))
        signedData.append(contentsOf: wrapSet(digestAlgSet))
        
        var encapContent = Data()
        encapContent.append(contentsOf: dataOID)
        signedData.append(contentsOf: wrapSequence(encapContent))
        
        var certsData = Data()
        certsData.append(certificate)
        signedData.append(contentsOf: wrapContextTag(0, data: certsData))
        
        var signerInfo = Data()
        signerInfo.append(contentsOf: [0x02, 0x01, 0x01])
        
        let issuerSerial = extractIssuerAndSerial(from: certificate)
        signerInfo.append(contentsOf: wrapSequence(issuerSerial))
        
        var digestAlg = Data()
        digestAlg.append(contentsOf: sha256OID)
        digestAlg.append(contentsOf: [0x05, 0x00])
        signerInfo.append(contentsOf: wrapSequence(digestAlg))
        
        var sigAlg = Data()
        sigAlg.append(contentsOf: rsaOID)
        sigAlg.append(contentsOf: [0x05, 0x00])
        signerInfo.append(contentsOf: wrapSequence(sigAlg))
        
        signerInfo.append(contentsOf: wrapOctetString(rawSignature))
        
        var signerInfoSet = Data()
        signerInfoSet.append(contentsOf: wrapSequence(signerInfo))
        signedData.append(contentsOf: wrapSet(signerInfoSet))
        
        var content = Data()
        content.append(contentsOf: wrapSequence(signedData))
        
        var outer = Data()
        outer.append(contentsOf: signedDataOID)
        outer.append(contentsOf: wrapContextTag(0, data: content))
        
        pkcs7.append(contentsOf: wrapSequence(outer))
        
        return pkcs7
    }
    
    private func wrapSequence(_ data: Data) -> Data {
        return wrapTag(0x30, data: data)
    }
    
    private func wrapSet(_ data: Data) -> Data {
        return wrapTag(0x31, data: data)
    }
    
    private func wrapOctetString(_ data: Data) -> Data {
        return wrapTag(0x04, data: data)
    }
    
    private func wrapContextTag(_ tag: UInt8, data: Data) -> Data {
        return wrapTag(0xA0 | tag, data: data)
    }
    
    private func wrapTag(_ tag: UInt8, data: Data) -> Data {
        var result = Data()
        result.append(tag)
        
        let length = data.count
        if length < 128 {
            result.append(UInt8(length))
        } else if length < 256 {
            result.append(0x81)
            result.append(UInt8(length))
        } else if length < 65536 {
            result.append(0x82)
            result.append(UInt8((length >> 8) & 0xFF))
            result.append(UInt8(length & 0xFF))
        } else {
            result.append(0x83)
            result.append(UInt8((length >> 16) & 0xFF))
            result.append(UInt8((length >> 8) & 0xFF))
            result.append(UInt8(length & 0xFF))
        }
        
        result.append(data)
        return result
    }
    
    private func extractIssuerAndSerial(from certificate: Data) -> Data {
        var result = Data()
        result.append(contentsOf: [0x30, 0x00]) // Empty sequence
        result.append(contentsOf: [0x02, 0x01, 0x01]) // INTEGER 1
        return result
    }
    
    private func createPassPackage(passData: Data, signature: Data, certificate: Data) throws -> Data {
        var files: [(name: String, data: Data)] = [
            ("pass.json", passData)
        ]
        
        let iconNames = ["icon", "icon@2x", "icon@3x"]
        for iconName in iconNames {
            if let iconURL = Bundle.main.url(forResource: iconName, withExtension: "png"),
               let iconData = try? Data(contentsOf: iconURL) {
                files.append(("\(iconName).png", iconData))
                print("✅ Added \(iconName).png to pass (\(iconData.count) bytes)")
            } else {
                print("⚠️ Icon not found in bundle: \(iconName).png")
            }
        }
        
        var manifestDict: [String: String] = [:]
        for file in files {
            manifestDict[file.name] = file.data.sha1Hash
        }
        
        let manifestData = try JSONSerialization.data(withJSONObject: manifestDict, options: [.sortedKeys])
        files.append(("manifest.json", manifestData))
        files.append(("signature", signature))
        
        print("📦 Creating pass with \(files.count) files")
        
        let zipData = try createZipArchive(files: files)
        return zipData
    }
    private func createZipArchive(files: [(name: String, data: Data)]) throws -> Data {
        var zipData = Data()
        var centralDirectory: Data = Data()
        var offset: UInt32 = 0
        
        let localFileHeaderSignature: UInt32 = 0x04034b50
        let centralDirSignature: UInt32 = 0x02014b50
        let endOfCentralDirSignature: UInt32 = 0x06054b50
        
        for file in files {
            let fileName = file.name
            let fileData = file.data
            let fileNameData = fileName.data(using: .utf8) ?? Data()
            let fileNameLength = UInt16(fileNameData.count)
            let uncompressedSize = UInt32(fileData.count)
            let compressedSize = uncompressedSize // Store uncompressed for simplicity
            let crc32 = fileData.crc32
            
            var localHeader = Data()
            localHeader.append(contentsOf: withUnsafeBytes(of: localFileHeaderSignature.littleEndian) { Data($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Data($0) }) // Version needed
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // General purpose bit flag
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Compression method (0 = stored)
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Last mod time
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Last mod date
            localHeader.append(contentsOf: withUnsafeBytes(of: crc32.littleEndian) { Data($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Data($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Data($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: fileNameLength.littleEndian) { Data($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Extra field length
            localHeader.append(fileNameData)
            
            zipData.append(localHeader)
            zipData.append(fileData)
            
            var centralHeader = Data()
            centralHeader.append(contentsOf: withUnsafeBytes(of: centralDirSignature.littleEndian) { Data($0) })
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Data($0) }) // Version made by
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Data($0) }) // Version needed
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // General purpose bit flag
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Compression method
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Last mod time
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Last mod date
            centralHeader.append(contentsOf: withUnsafeBytes(of: crc32.littleEndian) { Data($0) })
            centralHeader.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Data($0) })
            centralHeader.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Data($0) })
            centralHeader.append(contentsOf: withUnsafeBytes(of: fileNameLength.littleEndian) { Data($0) })
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Extra field length
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // File comment length
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Disk number start
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Internal file attributes
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) }) // External file attributes
            centralHeader.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Data($0) })
            centralHeader.append(fileNameData)
            
            centralDirectory.append(centralHeader)
            
            offset = UInt32(zipData.count)
        }
        
        let centralDirOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)
        
        var endOfCentralDir = Data()
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: endOfCentralDirSignature.littleEndian) { Data($0) })
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Number of this disk
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Number of disk with start of central directory
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Data($0) }) // Total number of entries on this disk
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Data($0) }) // Total number of entries
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Data($0) }) // Size of central directory
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Data($0) }) // Offset of central directory
        endOfCentralDir.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // ZIP file comment length
        
        zipData.append(endOfCentralDir)
        
        return zipData
    }

    }

enum PassKitError: LocalizedError {
    case certificateNotFound
    case certificateNeedsConversion
    case certificateImportFailed
    case privateKeyNotFound
    case signingFailed
    case passCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .certificateNotFound:
            return "Pass certificate not found. Please add Certificates.p12 (or pass.cer) to the app bundle."
        case .certificateNeedsConversion:
            return "pass.cer is a certificate file, but we need a .p12 file (certificate + private key) for signing. Please convert your certificate to .p12 format."
        case .certificateImportFailed:
            return "Failed to import certificate."
        case .privateKeyNotFound:
            return "Private key not found in certificate."
        case .signingFailed:
            return "Failed to sign pass."
        case .passCreationFailed:
            return "Failed to create pass from signed data."
        }
    }
}

extension Data {
    private static let crc32Table: [UInt32] = [
        0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
        0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
        0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
        0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
        0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
        0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
        0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
        0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
        0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
        0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
        0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
        0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
        0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
        0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
        0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
        0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
        0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
        0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
        0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
        0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
        0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
        0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
        0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
        0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
        0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
        0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
        0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
        0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
        0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
        0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
        0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
        0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
    ]

    @inline(__always)
    private static func crc32Lookup(_ index: Int) -> UInt32 { crc32Table[index] }
    
    var sha1Hash: String {
        let digest = Insecure.SHA1.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    var sha1HashBytes: [UInt8] {
        let digest = Insecure.SHA1.hash(data: self)
        return Array(digest)
    }
    
    var crc32: UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in self {
            crc = (crc >> 8) ^ Self.crc32Lookup(Int((crc ^ UInt32(byte)) & 0xFF))
        }
        return crc ^ 0xFFFFFFFF
    }
}

