---
name: sg-transit-routing
description: Plan Singapore MRT/bus journeys with no API keys.
---

# Singapore transit routing (no API keys)

## Working stack

| Need | Endpoint | Auth |
|---|---|---|
| SG geocoding (authoritative) | `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=X&returnGeom=Y&getAddrDetails=Y&pageNum=1` | none |
| Transit routing + real schedules | `https://api.transitous.org/api/v1/plan?fromPlace=lat,lon&toPlace=lat,lon&time=<ISO8601>&numItineraries=8` | none |
| Transit stop/place lookup | `https://api.transitous.org/api/v1/geocode?text=X` | none |
| Driving distance | `https://router.project-osrm.org/route/v1/driving/...` | none |
| **Walking** distance/time | `https://routing.openstreetmap.de/routed-foot/route/v1/foot/...` | none |

Coordinates always go `lon,lat` in OSRM URLs.

## Gotchas that cost time

1. **OSRM demo server has no foot profile.** `router.project-osrm.org/route/v1/foot/...` silently returns the *car* profile (~14 km/h). Use `routing.openstreetmap.de/routed-foot` for real walking (~4.5 km/h). Cross-check: if a "foot" duration implies >6 km/h, you got the car profile.
2. **OneMap routing needs a token** (`/api/public/routingsvc/route` -> 401). Geocoding does not. Don't waste turns on routing there.
3. **OneMap search fuzzy-matches and 429s.** `"TAMPINES MRT STATION"` returns *Tampines East*. Retry with backoff and prefer the result whose `SEARCHVAL` contains the exact station code, e.g. `(DT31)`. Cross-validate against Nominatim.
4. **Transitous walk legs are ~2x real time** (models ~2.2 km/h). Its itineraries over-transfer to dodge long final walks - the "best" route it returns may have 4 transfers when a clean 2-vehicle route exists. Trust its **rail and bus leg times** (from LTA GTFS); recompute walks from OSRM foot distance at 4.5 km/h.
5. **First-train tables are non-monotonic.** SBS Transit's first/last-train page has multiple first trains entering service at different points, so times jump backwards. Only the termini-origin column yields running times - use *Mon-Sat, Towards <terminus>*.
6. **Transitous `arriveBy=true`** answers "latest departure to arrive by X". A plain `time=` sweep only searches forward from that instant - sweeping from 08:40 will never surface an 09:05 arrival.
7. **data.gov.sg traffic cameras are not usable for congestion.** `transport/traffic-images` now returns **5 cameras** island-wide (was ~90). None cover the Tampines-Newton corridor. Do not design camera-plus-vision jam reading.
8. **Taxi GPS is the only keyless live road signal.** `transport/taxi-availability` gives ~3,000 points refreshing every **30 s**, but **no taxi IDs** - cross-snapshot matching is nearest-neighbour and lossy, and at 30 s a 60 km/h car moves ~500 m, near inter-taxi spacing. Report only an aggregate stationary fraction, never per-vehicle speed.
9. **curl against data.gov.sg breaks on this Windows host** - schannel TLS renegotiation swallows the body (`http=200 bytes=0`, no file written). Use Python urllib for those endpoints.
10. **`datamall2.mytransport.sg` 404s unauthenticated.** `BusArrivalv2` `Load` (SEA/LSD/SDA) + `Monitored=false` IS the bus-skip signal; `TrafficSpeedBandSvc` IS the road-jam signal. One free AccountKey unlocks both - say so instead of approximating them.

## MRT ride times (DTL, verified 2026-09)

DTL runs ~2.0 min/stop. Cumulative from Bukit Panjang: Newton (DT11) 21 min, Tampines West (DT31) 58 min, Tampines (DT32) 60 min.

- Tampines West (DT31) -> Newton (DT11) = **38 min**
- Tampines (DT32) -> Newton (DT11) = **40 min**

Verified against SBSTransit first-train data: DT1 Bukit Panjang 5:30 -> DT11 Newton 5:51 reproduces the 21-min figure exactly.

## Method

1. Geocode both endpoints on OneMap; confirm the returned `SEARCHVAL` is the actual destination.
2. Ask Transitous for the trip. Read the **leg modes and leg times**.
3. Recompute every WALK leg from OSRM foot distance / 4.5 km/h.
4. Rebuild the itinerary by hand using verified rail/bus times; prefer fewest-vehicle routes when peak frequency is <=3 min.
5. Report the router's latest-safe-departure, then state why the hand-built route beats it.