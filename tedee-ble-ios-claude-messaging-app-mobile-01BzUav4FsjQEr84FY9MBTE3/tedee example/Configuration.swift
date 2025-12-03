//
//  Configuration.swift
//  tedee example
//
//  Created by Mateusz Samosij on 28/02/2024.
//

import Foundation

enum Configuration {
    static let SerialNumber = ""
    static let Certificate = ""
    static let Expiration = ""
    static let DevicePublicKey = ""
    static let MobilePublicKey = ""
}

extension Configuration {
    static var expirationDate: Date = {
        guard let expirationDate = Date.date(from: Expiration,
                                             format: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'", isUTC: true) else {
            fatalError("Invalid expiration date format")
        }
        
        return expirationDate
    }()
}

extension Date {
    static var dF = DateFormatter()
    
    static func date(from string: String, format: String = "yyyy-MM-dd'T'HH:mm:ss", isUTC: Bool = false, locale: Locale? = nil) -> Date? {
        dF.dateFormat = format
        dF.locale = locale ?? Locale(identifier: "en_US_POSIX")
        dF.timeZone = isUTC ? TimeZone(abbreviation: "UTC") : Calendar.current.timeZone
        return dF.date(from: string)
    }
}
