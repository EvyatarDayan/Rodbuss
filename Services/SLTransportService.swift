//
//  SLTransportService.swift
//  Rödbuss
//
//  Uses SL Transport API (Trafiklab) – no API key required.
//  https://www.trafiklab.se/api/our-apis/sl/transport
//

import Foundation

// MARK: - Response models (match API JSON)

struct SLTransportAuthority: Codable {
    let id: Int
    let name: String
}

struct SLContractor: Codable {
    let id: Int
    let name: String
}

struct SLValidRange: Codable, Hashable {
    let from: String?
    let to: String?
}

struct SLLineInfo: Codable {
    let id: Int
    let gid: Int?
    let name: String?
    let designation: String
    let transport_mode: String
    let group_of_lines: String?
    let transport_authority: SLTransportAuthority?
    let contractor: SLContractor?
    let valid: SLValidRange?
}

struct SLSite: Codable, Identifiable, Hashable {
    let id: Int
    let gid: Int?
    let name: String
    let abbreviation: String?
    let lat: Double?
    let lon: Double?
    let stop_areas: [Int]?
    /// Transport modes served at this site (e.g. ["BUS", "TRAM"]). Nil if API omits it.
    let transport_modes: [String]?
    let valid: SLValidRange?

    /// True if this site serves bus (when transport_modes is present and contains BUS).
    var hasBus: Bool {
        guard let modes = transport_modes, !modes.isEmpty else { return true }
        return modes.contains { $0.uppercased() == "BUS" }
    }
}

struct SLStopAreaRef: Codable {
    let id: Int
    let name: String
    let sname: String?
    let type: String?
}

struct SLStopPointRef: Codable {
    let id: Int
    let name: String
    let designation: String?
}

struct SLJourneyRef: Codable {
    let id: Int?
    let state: String?
    let prediction_state: String?
    let passenger_level: String?
}

struct SLDepartureLine: Codable {
    let id: Int?
    let designation: String?
    let transport_mode: String?
    let group_of_lines: String?
}

struct SLDeparture: Codable, Identifiable {
    let direction: String?
    let direction_code: Int?
    let via: String?
    let destination: String?
    let state: String?
    let scheduled: String?
    let expected: String?
    let display: String?
    let journey: SLJourneyRef?
    let stop_area: SLStopAreaRef?
    let stop_point: SLStopPointRef?
    let line: SLDepartureLine?
    let deviations: String?

    var id: String { "\(line?.id ?? 0)-\(scheduled ?? "")-\(destination ?? "")" }

    enum CodingKeys: String, CodingKey {
        case direction, direction_code, via, destination, state, scheduled, expected, display
        case journey, stop_area, stop_point, line
        case deviations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = try c.decodeIfPresent(String.self, forKey: .direction)
        direction_code = try c.decodeIfPresent(Int.self, forKey: .direction_code)
        via = try c.decodeIfPresent(String.self, forKey: .via)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        scheduled = try c.decodeIfPresent(String.self, forKey: .scheduled)
        expected = try c.decodeIfPresent(String.self, forKey: .expected)
        display = try c.decodeIfPresent(String.self, forKey: .display)
        journey = try c.decodeIfPresent(SLJourneyRef.self, forKey: .journey)
        stop_area = try c.decodeIfPresent(SLStopAreaRef.self, forKey: .stop_area)
        stop_point = try c.decodeIfPresent(SLStopPointRef.self, forKey: .stop_point)
        line = try c.decodeIfPresent(SLDepartureLine.self, forKey: .line)
        deviations = SLDeparture.decodeDeviations(c, key: .deviations)
    }

    private static func decodeDeviations(_ c: KeyedDecodingContainer<SLDeparture.CodingKeys>, key: CodingKeys) -> String? {
        try? c.decodeIfPresent(String.self, forKey: key)
    }

    private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let d = SLDeparture.isoFormatterWithFraction.date(from: s) { return d }
        if let d = SLDeparture.isoFormatter.date(from: s) { return d }
        let customFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "HH:mm:ss",
            "HH:mm"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in customFormats {
            formatter.dateFormat = format
            if let d = formatter.date(from: s) {
                if format == "HH:mm" || format == "HH:mm:ss" {
                    let cal = Calendar.current
                    let comps = cal.dateComponents([.hour, .minute, .second], from: d)
                    return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: comps.second ?? 0, of: Date())
                }
                return d
            }
        }
        return nil
    }

    var scheduledDate: Date? { SLDeparture.parseDate(scheduled) }
    var expectedDate: Date? { SLDeparture.parseDate(expected) }
}

struct SLDeparturesResponse: Codable {
    let departures: [SLDeparture]
    let stop_deviations: [SLStopDeviation]?
}

struct SLStopDeviation: Codable {
    let importance: Int?
    let consequence: String?
    let message: String?
}

// MARK: - Service

private struct SLApiErrorEnvelope: Codable {
    let message: String?
}

enum SLTransportServiceError: LocalizedError {
    case httpStatus(Int, message: String?)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(code, message):
            let clean = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if code >= 500 || clean?.lowercased().contains("internal server error") == true {
                return "SL service is temporarily unavailable. Please try again shortly."
            }
            if let clean, !clean.isEmpty {
                return "SL API error \(code): \(clean)"
            }
            return "SL API error \(code)"
        }
    }
}

final class SLTransportService {
    static let shared = SLTransportService()

    private let baseURL = "https://transport.integration.sl.se/v1"
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    private init() {}

    /// Fetch all sites (with stop area IDs). Filter by name on the client if needed.
    func fetchSites(expand: Bool = true) async throws -> [SLSite] {
        guard await ApiSleepManager.isApiAllowed() else { throw ApiSleepError.sleeping }
        var components = URLComponents(string: "\(baseURL)/sites")!
        components.queryItems = [URLQueryItem(name: "expand", value: expand ? "true" : "false")]
        let url = components.url!
        let data = try await performRequest(url: url)
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([SLSite].self, from: data) {
            return list
        }
        // Defensive fallback in case API switches to an envelope: { "sites": [...] }.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawSites = obj["sites"],
           let wrappedData = try? JSONSerialization.data(withJSONObject: rawSites),
           let list = try? decoder.decode([SLSite].self, from: wrappedData) {
            return list
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unable to decode sites response"))
    }

    /// Fetch next departures from a site (by site ID from /sites).
    func fetchDepartures(siteId: Int) async throws -> SLDeparturesResponse {
        guard await ApiSleepManager.isApiAllowed() else { throw ApiSleepError.sleeping }
        let url = URL(string: "\(baseURL)/sites/\(siteId)/departures")!
        let data = try await performRequest(url: url)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(SLDeparturesResponse.self, from: data)
        } catch {
            // Defensive fallback in case API wraps payload as { "departures": [...] }.
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawDepartures = obj["departures"],
               let depData = try? JSONSerialization.data(withJSONObject: rawDepartures),
               let deps = try? decoder.decode([SLDeparture].self, from: depData) {
                var stopDeviations: [SLStopDeviation]?
                if let rawDeviations = obj["stop_deviations"],
                   let deviationsData = try? JSONSerialization.data(withJSONObject: rawDeviations),
                   let decodedDeviations = try? decoder.decode([SLStopDeviation].self, from: deviationsData) {
                    stopDeviations = decodedDeviations
                }
                return SLDeparturesResponse(departures: deps, stop_deviations: stopDeviations)
            }
            let fallback = decodeDeparturesRelaxed(data: data)
            if !fallback.departures.isEmpty {
                return fallback
            }
            throw error
        }
    }

    private func performRequest(url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(SLApiErrorEnvelope.self, from: data))?.message
            throw SLTransportServiceError.httpStatus(http.statusCode, message: message)
        }
        // Some upstream errors come back as HTTP 200 with {"message":"..."} payload.
        if let envelope = try? JSONDecoder().decode(SLApiErrorEnvelope.self, from: data),
           let message = envelope.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            throw SLTransportServiceError.httpStatus(500, message: message)
        }
        return data
    }

    /// Decode response tolerating malformed items; skip any departure that fails to decode.
    private func decodeDeparturesRelaxed(data: Data) -> SLDeparturesResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["departures"] as? [[String: Any]] else {
            return SLDeparturesResponse(departures: [], stop_deviations: nil)
        }
        let decoder = JSONDecoder()
        var departures: [SLDeparture] = []
        for item in arr {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let dep = try? decoder.decode(SLDeparture.self, from: itemData) else { continue }
            departures.append(dep)
        }
        var stopDeviations: [SLStopDeviation]?
        if let devArr = json["stop_deviations"] as? [[String: Any]] {
            stopDeviations = devArr.compactMap { dict in
                guard let d = try? JSONSerialization.data(withJSONObject: dict),
                      let s = try? decoder.decode(SLStopDeviation.self, from: d) else { return nil }
                return s
            }
            if stopDeviations?.isEmpty == true { stopDeviations = nil }
        }
        return SLDeparturesResponse(departures: departures, stop_deviations: stopDeviations)
    }
}
