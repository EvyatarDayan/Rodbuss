# Live bus position on map – API options

Your app currently uses **Trafiklab** (and Samtrafiken) **GTFS-RT VehiclePositions** feeds to show the bus on the map. Below are the realistic options for a **free and accurate** live bus API.

---

## 1. Google – **not an option for your use case**

- **Google Transit / GTFS-Realtime** is a **spec** and a **partnership program** for **transit agencies** to send data *to* Google (so buses show in Google Maps).
- There is **no public Google API** that lets an app *read* live bus positions. You cannot call a Google endpoint from Rödbuss to get SL bus locations.
- So: **Google does not provide a free API you can use here.**

---

## 2. Trafiklab (current) – **best option, make it reliable**

- **Trafiklab** is the official platform for Swedish transit data, including **SL**.
- **GTFS Regional** includes **VehiclePositions** (real-time bus positions) for SL and others.
- **Free**: Yes, with a free API key from [developer.trafiklab.se](https://developer.trafiklab.se).
- **Accurate**: Yes; this is the same data source used for official apps.

**Why you might see “issues”:**

- Wrong or outdated endpoint URL (Trafiklab has changed paths over time).
- API key: query param `key=...` (and possibly header for some endpoints).
- Gzip: some endpoints return gzip; your code already handles that.
- Protobuf layout can differ (field numbers); your custom parser might need to match the current feed.

**Recommendation:** Keep using Trafiklab, but use the **single, documented** GTFS Regional realtime URL from their current docs/OpenAPI spec and ensure the key is sent as they specify. Prefer **one stable endpoint** instead of many fallbacks.

---

## 3. Samtrafiken Open Data

- **opendata.samtrafiken.se** – official GTFS-RT for several operators (`sl`, `ul`, `dt`, etc.).
- **Free**: Yes, with registration/key.
- **Accurate**: Same type of data as Trafiklab (GTFS-RT).

Your code already tries `opendata.samtrafiken.se/gtfs-rt/{operator}/VehiclePositions.pb?key=...`. If Trafiklab is flaky, using **only** Samtrafiken (with a key from them) can be a cleaner fallback. You still need a key.

---

## 4. Transitland – **not a replacement for vehicle positions**

- Transitland has a **REST API** (stops, routes, trips, etc.) but **no dedicated “vehicle positions” endpoint** in the same way as a raw GTFS-RT feed.
- They aggregate feeds in the background; for **live bus on map** you need direct VehiclePositions. So Transitland is **not** a practical replacement for your current Trafiklab/Samtrafiken GTFS-RT.

---

## 5. Other (Resrobot, OTP, etc.)

- **Resrobot (Trafiklab)** – trip planning, not live vehicle positions.
- **OpenTripPlanner** – you would host it and plug in the **same** GTFS-RT feed (Trafiklab/Samtrafiken); it does not replace the need for a working feed.

---

## Summary

| Option              | Free? | Accurate? | Use for live bus on map?     |
|---------------------|------|-----------|------------------------------|
| Google              | N/A  | N/A       | **No** – no consumer API     |
| **Trafiklab**       | Yes  | Yes       | **Yes** – main source        |
| Samtrafiken         | Yes  | Yes       | **Yes** – alternative/backup |
| Transitland         | Yes  | N/A       | **No** – no vehicle pos API  |

**Practical path:**  
Use **Trafiklab** (and optionally Samtrafiken as fallback) and **harden the integration**: one documented endpoint, correct API key usage, and robust parsing/error handling. There isn’t a different free, accurate API that replaces Trafiklab for Stockholm bus positions.
