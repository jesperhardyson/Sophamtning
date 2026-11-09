import CloudKit
import Foundation
import SophamtningKit

/// Hushållets poster i CloudKit och översättningen till och från paketets värdetyper. Paketet känner inte till CloudKit,
/// så allt som rör `CKRecord` ligger här.
///
/// Postnamnen är deterministiska: två deltagare som delar samma adress eller bockar samma hämtning skriver samma post,
/// och vid `serverRecordChanged` behålls serverns version (första trycket vinner).
enum HouseholdRecords {
    static let containerIdentifier = "iCloud.se.hardyson.sophamtning"
    static let zoneName = "Hushall"
    static let addressType = "HushallAdress"
    static let markType = "Utstallt"
    static let participantType = "HushallDeltagare"
    /// Rubriken som systemets delningsark visar för inbjudan.
    static let shareTitle = "Hushåll"

    /// Zonen i ägarens privata databas.
    static var privateZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private enum Field {
        static let address = "address"
        static let addedBy = "addedBy"
        static let source = "source"
        static let id = "id"
        static let date = "date"
        static let by = "by"
        static let at = "at"
        static let name = "name"
    }

    /// Början av postnamnet för en deltagares namn. Resten är deltagarens användar-id.
    private static let participantPrefix = "deltagare-"

    // MARK: Postnamn

    static func recordName(for key: AddressKey) -> String {
        key.fileName
    }

    static func recordName(for placedOut: PlacedOut) -> String {
        placedOut.key.fileName + "-" + placedOut.date.iso
    }

    static func recordName(forParticipant id: String) -> String {
        participantPrefix + id
    }

    // MARK: Namn

    /// Mitt namn i hushållet. Finns posten redan ändras bara namnet, så att serverns systemfält följer med.
    static func participantRecord(id: String, name: String, existing: CKRecord?, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = existing ?? CKRecord(recordType: participantType, recordID: CKRecord.ID(recordName: recordName(forParticipant: id), zoneID: zoneID))
        record[Field.name] = name as NSString
        return record
    }

    /// Deltagarens id och namn ur en post, eller `nil` för andra poster och tomma namn.
    static func participantName(from record: CKRecord) -> (id: String, name: String)? {
        let recordName = record.recordID.recordName
        guard record.recordType == participantType, recordName.hasPrefix(participantPrefix),
              let name = (record[Field.name] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        return (String(recordName.dropFirst(participantPrefix.count)), name)
    }

    /// Mitt förnamn från Apple-kontot, när iOS lämnar ut det.
    static func suggestedName(in share: CKShare) -> String? {
        guard let components = share.currentUserParticipant?.userIdentity.nameComponents else { return nil }
        if let given = components.givenName, !given.isEmpty { return given }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        let name = formatter.string(from: components)
        return name.isEmpty ? nil : name
    }

    // MARK: Adresser

    /// En ny post för en delad adress. `address` är hela `SavedAddress` som JSON, med `url` oförändrad.
    static func addressRecord(_ address: HouseholdAddress, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName(for: address.address.key), zoneID: zoneID)
        let record = CKRecord(recordType: addressType, recordID: recordID)
        let json = try JSONEncoder().encode(address.address)
        record[Field.address] = String(decoding: json, as: UTF8.self) as NSString
        record[Field.addedBy] = address.addedBy as NSString
        return record
    }

    /// Adressen i en post, eller `nil` om posten inte är en hel adress.
    static func address(from record: CKRecord) -> HouseholdAddress? {
        guard record.recordType == addressType,
              let json = record[Field.address] as? String,
              let address = try? JSONDecoder().decode(SavedAddress.self, from: Data(json.utf8)) else { return nil }
        return HouseholdAddress(address: address, addedBy: record[Field.addedBy] as? String ?? "")
    }

    // MARK: Bockar

    /// En ny post för en bock. `id` är adressens id ordagrant, och `date` hämtdatumet (`yyyy-MM-dd`).
    static func markRecord(_ mark: HouseholdMark, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName(for: mark.placedOut), zoneID: zoneID)
        let record = CKRecord(recordType: markType, recordID: recordID)
        record[Field.source] = mark.placedOut.key.source as NSString
        record[Field.id] = mark.placedOut.key.id as NSString
        record[Field.date] = mark.placedOut.date.iso as NSString
        record[Field.by] = mark.by as NSString
        record[Field.at] = mark.at as NSDate
        return record
    }

    /// Bocken i en post. `isPending` sätts av synken, som vet om posten väntar på att skickas.
    static func mark(from record: CKRecord, isPending: Bool) -> HouseholdMark? {
        guard record.recordType == markType,
              let source = record[Field.source] as? String,
              let id = record[Field.id] as? String,
              let dateText = record[Field.date] as? String,
              let date = DayDate(dateText) else { return nil }
        let placedOut = PlacedOut(key: AddressKey(source: source, id: id), date: date)
        let at = record[Field.at] as? Date ?? record.creationDate ?? Date(timeIntervalSince1970: 0)
        return HouseholdMark(placedOut: placedOut, by: record[Field.by] as? String ?? "", at: at, isPending: isPending)
    }

    /// En kopia utan systemfälten, för att skriva en post igen som ny när den har försvunnit på servern.
    static func freshCopy(of record: CKRecord) -> CKRecord {
        let copy = CKRecord(recordType: record.recordType, recordID: record.recordID)
        for key in record.allKeys() {
            copy[key] = record[key]
        }
        return copy
    }

    // MARK: Deltagare

    /// Deltagarna som har gått med, ägaren först. Mitt id är `myId` även när CloudKit kallar mig `CKCurrentUserDefaultName`.
    static func participants(of share: CKShare, myId: String?) -> [HouseholdParticipant] {
        let accepted = share.participants.filter { $0.role == .owner || $0.acceptanceStatus == .accepted }
        let result = accepted.compactMap { participant -> HouseholdParticipant? in
            guard let id = participantId(participant, in: share, myId: myId) else { return nil }
            return HouseholdParticipant(id: id, name: name(of: participant), isOwner: participant.role == .owner)
        }
        return result.sorted { lhs, rhs in
            if lhs.isOwner != rhs.isOwner { return lhs.isOwner }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Ägarens namn, för texten om att ägarens iCloud är fullt.
    static func ownerName(of share: CKShare?) -> String {
        guard let owner = share?.participants.first(where: { $0.role == .owner }) else { return "Ägaren" }
        return name(of: owner)
    }

    /// Användar-id:t för en deltagare, samma som `CKContainer.userRecordID()` ger på deltagarens alla enheter.
    static func participantId(_ participant: CKShare.Participant, in share: CKShare, myId: String?) -> String? {
        if participant == share.currentUserParticipant, let myId { return myId }
        guard let recordName = participant.userIdentity.userRecordID?.recordName else { return nil }
        if recordName == CKCurrentUserDefaultName { return myId }
        return recordName
    }

    /// Namnet från Apple-kontot i kort form, till exempel "Kim". Utan namn visas adressen eller numret, annars "Någon".
    static func name(of participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .short
            let name = formatter.string(from: components)
            if !name.isEmpty { return name }
        }
        let lookup = participant.userIdentity.lookupInfo
        return lookup?.emailAddress ?? lookup?.phoneNumber ?? "Någon"
    }

    // MARK: Fel

    /// Hushållets läge för ett fel från CloudKit, eller `nil` när felet är tillfälligt och motorn försöker igen själv.
    /// `zoneNotFound` och `userDeletedZone` hanteras av synken, eftersom de betyder olika saker för ägare och medlem.
    static func status(for error: CKError, ownerName: @autoclosure () -> String) -> HouseholdStatus? {
        switch error.code {
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .operationCancelled:
            nil
        case .notAuthenticated:
            .notSignedIn
        case .quotaExceeded:
            .quotaExceeded(ownerName: ownerName())
        case .partialFailure:
            // Det allvarligaste felet för en post avgör, så att svaret inte beror på ordningen i ordboken.
            (error.partialErrorsByItemID?.values.compactMap { $0 as? CKError }.max { severity($0.code) < severity($1.code) })
                .map { status(for: $0, ownerName: ownerName()) } ?? .failed
        default:
            .failed
        }
    }

    /// Hur allvarligt ett fel i en `partialFailure` är: `notAuthenticated` före `quotaExceeded`, före en borttagen zon,
    /// före övriga fel.
    static func severity(_ code: CKError.Code) -> Int {
        switch code {
        case .notAuthenticated: 3
        case .quotaExceeded: 2
        case .zoneNotFound, .userDeletedZone: 1
        default: 0
        }
    }

    // MARK: Lagring

    /// En post med alla fält och systemfält, för den lokala kopian.
    static func archive(_ record: CKRecord) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data) -> CKRecord? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [CKRecord.self, CKShare.self], from: data) as? CKRecord
    }
}
