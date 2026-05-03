//
//  BusPositionService.swift
//  Rödbuss
//
//  Fetches real-time bus positions from Trafiklab GTFS-RT VehiclePositions feed (SL).
//  Requires Trafiklab API key in Settings. Feed is protobuf; we parse a minimal subset.
//

import CoreLocation
import Foundation

/// One vehicle position from the GTFS-RT feed (route_id optional; lat/lon in WGS84).
struct VehiclePositionItem {
    var routeId: String?
    /// GTFS-RT TripDescriptor trip_id. Useful to lock to one specific upcoming departure.
    var tripId: String?
    /// GTFS-RT TripDescriptor direction_id (0 or 1). Used to filter by route direction.
    var tripDirectionId: Int?
    var latitude: Double
    var longitude: Double
}

enum BusPositionError: Error, LocalizedError {
    case httpStatus(Int, url: URL)
    case noDataFromFeed
    case network(Error)
    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, _): return "HTTP \(code)"
        case .noDataFromFeed: return "No vehicles in feed"
        case .network(let e): return e.localizedDescription
        }
    }
}

final class BusPositionService {
    static let shared = BusPositionService()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    /// Builds list of (URL, useKeyInHeader). Tries Trafiklab first (key in query), then Samtrafiken.
    private func vehiclePositionsRequests(apiKey: String) -> [(url: URL, keyInHeader: Bool)] {
        var list: [(URL, Bool)] = []
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return list }
        let q = [URLQueryItem(name: "key", value: key)]

        // 1. Trafiklab GTFS Regional (key as query param – documented format)
        for path in [
            "https://api.trafiklab.se/gtfs-regional/v2/VehiclePositions.pb",
            "https://api.trafiklab.se/gtfs-regional/v1/VehiclePositions.pb",
            "https://api.trafiklab.se/gtfs-regional/VehiclePositions.pb",
            "https://api.trafiklab.se/gtfs-regional/v2/sl/VehiclePositions.pb",
            "https://api.trafiklab.se/gtfs-sweden/v2/VehiclePositions.pb",
            "https://api.trafiklab.se/gtfs-sweden/v1/VehiclePositions.pb",
        ] {
            if var c = URLComponents(string: path) { c.queryItems = q; if let u = c.url { list.append((u, false)) } }
        }

        // 2. Trafiklab realtime-api (key in query or header)
        for path in [
            "https://realtime-api.trafiklab.se/v1/gtfs-regional/sl/VehiclePositions.pb",
            "https://realtime-api.trafiklab.se/v1/gtfs-regional/VehiclePositions.pb",
            "https://realtime-api.trafiklab.se/gtfs-regional/sl/VehiclePositions.pb",
        ] {
            if var c = URLComponents(string: path) { c.queryItems = q; if let u = c.url { list.append((u, false)) } }
            if let u = URL(string: path) { list.append((u, true)) }
        }

        // 3. Samtrafiken Open Data (may need separate key from opendata.samtrafiken.se)
        for operatorCode in ["sl", "dt", "ul", "otraf", "skane"] {
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let path = "https://opendata.samtrafiken.se/gtfs-rt/\(operatorCode)/VehiclePositions.pb?key=\(encodedKey)"
            if let u = URL(string: path) { list.append((u, false)) }
        }

        return list
    }

    private init() {}

    /// If data is gzip-compressed (magic 0x1f 0x8b), decompress and return; otherwise return data as-is.
    private static func decompressGzipIfNeeded(_ data: Data) -> Data {
        guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else { return data }
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen: size_t = 0
        let result = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return gzip_decompress(base.assumingMemoryBound(to: UInt8.self), data.count, &outPtr, &outLen)
        }
        guard result == 0, let ptr = outPtr, outLen > 0 else { return data }
        defer { free(ptr) }
        return Data(bytes: ptr, count: outLen)
    }

    /// Fetches vehicle positions; tries multiple URLs and key-in-query or key-in-header. Decompresses gzip if needed.
    /// - Parameters:
    ///   - directionFilter: If set, only return vehicles with this GTFS-RT direction_id (0 or 1), so the same line in the opposite direction is excluded.
    ///   - tripIdFilter: If set, prefer vehicles whose trip_id matches this value. If no match exists, we fall back to line/direction result.
    func fetchVehiclePositions(apiKey: String, lineFilter: String?, directionFilter: Int? = nil, tripIdFilter: String? = nil) async throws -> [VehiclePositionItem] {
        guard await ApiSleepManager.isApiAllowed() else { throw ApiSleepError.sleeping }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let requests = vehiclePositionsRequests(apiKey: apiKey)
        var lastError: Error?
        for (url, keyInHeader) in requests {
            // Try without gzip first so we parse raw protobuf; if server still sends gzip we decompress
            for useIdentityEncoding in [true, false] {
                do {
                    var req = URLRequest(url: url)
                    if useIdentityEncoding { req.setValue("identity", forHTTPHeaderField: "Accept-Encoding") }
                    if keyInHeader {
                        req.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
                        req.setValue(key, forHTTPHeaderField: "x-api-key")
                        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    // Don't set custom User-Agent – use default so request matches browser behaviour
                    let (data, response) = try await session.data(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    #if DEBUG
                    let safeUrl = url.absoluteString.replacingOccurrences(of: key, with: "***")
                    print("[BusPosition] \(url.host ?? "") \(status) \(safeUrl.prefix(80))...")
                    #endif
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        lastError = BusPositionError.httpStatus(http.statusCode, url: url)
                        continue
                    }
                    let dataToParse = Self.decompressGzipIfNeeded(data)
                    let all = GTFSRealtimeParser.parseVehiclePositions(dataToParse)
                    #if DEBUG
                    if all.isEmpty {
                        print("[BusPosition] \(url.host ?? ""): 0 vehicles (size: \(data.count), first: \(data.prefix(4).map { $0 }), identity=\(useIdentityEncoding))")
                    } else {
                        print("[BusPosition] \(url.host ?? ""): \(all.count) vehicles")
                    }
                    #endif
                    guard !all.isEmpty else { continue }
                    guard let line = lineFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !line.isEmpty else {
                        return all
                    }
                    var matched = all.filter { item in
                        guard let rid = item.routeId?.lowercased() else { return true }
                        return rid == line || rid.hasPrefix(line) || line.hasPrefix(rid) || rid.contains(line)
                    }
                    if let dir = directionFilter, !matched.isEmpty {
                        let byDirection = matched.filter { item in
                            guard let did = item.tripDirectionId else { return true }
                            return did == dir
                        }
                        if !byDirection.isEmpty { matched = byDirection }
                    }
                    if let trip = tripIdFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !trip.isEmpty, !matched.isEmpty {
                        let byTrip = matched.filter { item in
                            guard let tid = item.tripId?.trimmingCharacters(in: .whitespacesAndNewlines), !tid.isEmpty else { return false }
                            return tid == trip || tid.contains(trip) || trip.contains(tid)
                        }
                        if !byTrip.isEmpty { matched = byTrip }
                    }
                    if matched.isEmpty, let first = all.first { return [first] }
                    return matched
                } catch {
                    lastError = BusPositionError.network(error)
                    #if DEBUG
                    print("[BusPosition] \(url.host ?? "") identity=\(useIdentityEncoding): \(error.localizedDescription)")
                    #endif
                }
            }
        }
        if let lastError = lastError { throw lastError }
        throw BusPositionError.noDataFromFeed
    }
}

// MARK: - Minimal GTFS-Realtime protobuf parser (FeedMessage > FeedEntity > VehiclePosition > Position, TripDescriptor)
// Standard GTFS-RT: FeedMessage.entity=2, FeedEntity.vehicle=4. TripUpdate=3 is not VehiclePosition.

private enum GTFSRealtimeParser {
    /// FeedMessage: header=1, entity=2. Only parse field 2 (entity); field 1 is header.
    private static let entityFieldNumber = 2
    /// FeedEntity: TripUpdate=3, VehiclePosition=4. Only parse field 4.
    private static let vehicleFieldNumber = 4

    static func parseVehiclePositions(_ data: Data) -> [VehiclePositionItem] {
        var result: [VehiclePositionItem] = []
        var offset = 0
        while offset < data.count {
            guard let (fieldNum, wireType, len) = readTagAndLength(data, offset: &offset) else { break }
            if wireType == 2, fieldNum == entityFieldNumber {
                let entityEnd = offset + len
                var innerOffset = offset
                while innerOffset < entityEnd {
                    guard let (f, w, l) = readTagAndLength(data, offset: &innerOffset) else { break }
                    if w == 2, f == vehicleFieldNumber {
                        if let item = parseVehiclePosition(data, start: innerOffset, end: innerOffset + l) {
                            result.append(item)
                        }
                        innerOffset += l
                    } else {
                        skipValue(data, offset: &innerOffset, wireType: w, length: l)
                    }
                }
                offset = entityEnd
            } else {
                skipValue(data, offset: &offset, wireType: wireType, length: len)
            }
        }
        // Fallback: if standard parse returned nothing, try alternative layout (e.g. entity=1 or vehicle=3)
        if result.isEmpty && data.count > 100 {
            result = parseVehiclePositionsRelaxed(data)
        }
        return result
    }

    /// Tries alternative field numbers in case the feed uses a different proto version.
    private static func parseVehiclePositionsRelaxed(_ data: Data) -> [VehiclePositionItem] {
        var result: [VehiclePositionItem] = []
        var offset = 0
        while offset < data.count {
            guard let (fieldNum, wireType, len) = readTagAndLength(data, offset: &offset) else { break }
            if wireType == 2, (fieldNum == 1 || fieldNum == 2) {
                let entityEnd = offset + len
                var innerOffset = offset
                while innerOffset < entityEnd {
                    guard let (f, w, l) = readTagAndLength(data, offset: &innerOffset) else { break }
                    if w == 2, (f == 3 || f == 4) {
                        if let item = parseVehiclePosition(data, start: innerOffset, end: innerOffset + l) {
                            result.append(item)
                        }
                        innerOffset += l
                    } else {
                        skipValue(data, offset: &innerOffset, wireType: w, length: l)
                    }
                }
                offset = entityEnd
            } else {
                skipValue(data, offset: &offset, wireType: wireType, length: len)
            }
        }
        return result
    }

    private static func parseVehiclePosition(_ data: Data, start: Int, end: Int) -> VehiclePositionItem? {
        var lat: Double?
        var lon: Double?
        var routeId: String?
        var tripId: String?
        var directionId: Int?
        var offset = start
        while offset < end {
            guard let (fieldNum, wireType, len) = readTagAndLength(data, offset: &offset) else { break }
            guard wireType == 2 else { skipValue(data, offset: &offset, wireType: wireType, length: len); continue }
            let subStart = offset
            let subEnd = offset + len
            var pos = subStart
            var subLat: Double?, subLon: Double?, subRouteId: String?, subDirectionId: Int?
            var subTripId: String?
            while pos < subEnd {
                guard let (f, w, l) = readTagAndLength(data, offset: &pos) else { break }
                if w == 1, l == 8 {
                    guard let d = readDouble(data, offset: &pos) else { break }
                    if f == 1 { subLat = d } else if f == 2 { subLon = d }
                } else if w == 5, l == 4 {
                    // GTFS-RT Position uses float (wire 5), not double
                    guard let d = readFloat(data, offset: &pos) else { break }
                    if f == 1 { subLat = Double(d) } else if f == 2 { subLon = Double(d) }
                } else if w == 0 {
                    // Varint (e.g. TripDescriptor direction_id = field 3)
                    guard let v = readVarint(data, offset: &pos) else { break }
                    if f == 3 { subDirectionId = v }
                } else if w == 2 {
                    if l > 0, l < 1000 {
                        let text = readString(data, offset: &pos, length: l)
                        if fieldNum == 1, f == 1 {
                            // TripDescriptor.trip_id
                            subTripId = text
                        } else if fieldNum == 1, (f == 2 || f == 5) {
                            // TripDescriptor.route_id (some feeds vary)
                            subRouteId = text
                        } else if f == 2 || f == 5 {
                            subRouteId = text
                        }
                    } else {
                        skipValue(data, offset: &pos, wireType: w, length: l)
                    }
                } else {
                    skipValue(data, offset: &pos, wireType: w, length: l)
                }
            }
            if subLat != nil || subLon != nil { lat = subLat ?? lat; lon = subLon ?? lon }
            if subRouteId != nil { routeId = subRouteId }
            if subTripId != nil { tripId = subTripId }
            if subDirectionId != nil { directionId = subDirectionId }
            offset = subEnd
        }
        guard let lat = lat, let lon = lon, lat >= -90, lat <= 90, lon >= -180, lon <= 180 else { return nil }
        return VehiclePositionItem(routeId: routeId, tripId: tripId, tripDirectionId: directionId, latitude: lat, longitude: lon)
    }

    private static func readTagAndLength(_ data: Data, offset: inout Int) -> (fieldNum: Int, wireType: Int, length: Int)? {
        guard let tag = readVarint(data, offset: &offset) else { return nil }
        let wireType = tag & 0x07
        let fieldNum = tag >> 3
        var length = 0
        if wireType == 2 {
            guard let len = readVarint(data, offset: &offset) else { return nil }
            length = len
        } else if wireType == 1 {
            length = 8
        } else if wireType == 5 {
            length = 4
        } else if wireType == 0 {
            length = 10
        }
        return (fieldNum, wireType, length)
    }

    private static func skipValue(_ data: Data, offset: inout Int, wireType: Int, length: Int) {
        if wireType == 2 {
            offset += length
        } else if wireType == 1 {
            offset += 8
        } else if wireType == 5 {
            offset += 4
        } else if wireType == 0 {
            while offset < data.count, (data[offset] & 0x80) != 0 { offset += 1 }
            if offset < data.count { offset += 1 }
        }
    }

    private static func readVarint(_ data: Data, offset: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while offset < data.count {
            let b = Int(data[offset])
            offset += 1
            result |= (b & 0x7f) << shift
            if (b & 0x80) == 0 { return result }
            shift += 7
            if shift > 35 { return nil }
        }
        return nil
    }

    private static func readDouble(_ data: Data, offset: inout Int) -> Double? {
        guard offset + 8 <= data.count else { return nil }
        let v = data.subdata(in: offset..<(offset + 8))
        offset += 8
        return v.withUnsafeBytes { $0.load(as: Double.self) }
    }

    private static func readFloat(_ data: Data, offset: inout Int) -> Float? {
        guard offset + 4 <= data.count else { return nil }
        let v = data.subdata(in: offset..<(offset + 4))
        offset += 4
        return v.withUnsafeBytes { $0.load(as: Float.self) }
    }

    private static func readString(_ data: Data, offset: inout Int, length: Int) -> String? {
        guard length >= 0, offset + length <= data.count else { return nil }
        let sub = data.subdata(in: offset..<(offset + length))
        offset += length
        return String(data: sub, encoding: .utf8)
    }
}
