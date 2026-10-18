// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
import Foundation

// Logic tests (Core.swift) against mock_ha.py. Run with Tests/run.sh.
var failures = 0
func check(_ ok: Bool, _ name: String) {
    print((ok ? "OK   " : "FAIL ") + name)
    if !ok { failures += 1 }
}
func throwsError(_ block: () async throws -> Void) async -> Bool {
    do { try await block(); return false } catch { return true }
}

let address = "http://127.0.0.1:\(ProcessInfo.processInfo.environment["MOCK_PORT"] ?? "8123")"

func run() async {
    let client = try! HAClient(address: address, token: "test-token")
    let entities = try! await client.states()
    check(entities.count == 10, "reads the 10 entities")

    let map = AutoMap.map(entities)
    check(map["status"] == "sensor.philips_airfryer_status", "auto: status")
    check(map["remaining"] == "sensor.philips_airfryer_time_remaining", "auto: time remaining")
    check(map["temp"] == "number.philips_airfryer_temperature", "auto: temperature (not the thermostat)")
    check(map["time"] == "number.philips_airfryer_cook_time", "auto: duration (not keep warm)")
    check(map["start"] == "button.philips_airfryer_start", "auto: start (not the garage)")
    check(map["pause"] != nil && map["stop"] != nil, "auto: pause and stop")

    let bad = try! HAClient(address: address, token: "sbagliato")
    check(await throwsError { _ = try await bad.states() }, "wrong token rejected")
    check(await throwsError { _ = try HAClient(address: "http://u:p@host", token: "x") }, "URL with credentials rejected")
    check(await throwsError { _ = try HAClient(address: "ftp://host", token: "x") }, "non-http scheme rejected")

    let temp = entities.first { $0.id == map["temp"] }!
    let time = entities.first { $0.id == map["time"] }!
    check((try? validated(200, entity: temp)) == 200, "200 °C is valid")
    check((try? validated(250, entity: temp)) == nil, "250 °C is out of range")
    check((try? validated(183, entity: temp)) == nil, "183 °C does not respect step 5")
    check((try? durationValue(minutes: 15, unit: "s")) == 900, "15 min = 900 s")
    check((try? durationValue(minutes: 15, unit: "h")) == nil, "unknown unit rejected")
    check((try? validated(30 * 60, entity: time)) == 1800, "30 min within limits")

    try! await client.call("number", "set_value", ["entity_id": temp.id, "value": 190.0])
    try! await client.call("button", "press", ["entity_id": map["stop"]!])
    let (data, _) = try! await URLSession.shared.data(from: URL(string: address + "/_log")!)
    let log = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    check(log.count == 2 && log[0]["service"] as? String == "number/set_value" && log[1]["service"] as? String == "button/press",
          "service calls reach the server")

    // Italian entity names as Home Assistant shows them for a real air fryer (ids derived from the device name).
    let it = """
    [
    {"entity_id":"button.airfryer_5000_series_l_cloud_avvia_cottura","state":"unknown","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Avvia cottura"}},
    {"entity_id":"button.airfryer_5000_series_l_cloud_pausa","state":"unknown","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Pausa"}},
    {"entity_id":"button.airfryer_5000_series_l_cloud_stop","state":"unknown","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Stop"}},
    {"entity_id":"button.airfryer_5000_series_l_cloud_mantieni_caldo","state":"unknown","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Mantieni caldo"}},
    {"entity_id":"number.airfryer_5000_series_l_cloud_imposta_temperatura","state":"0","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Imposta temperatura","unit_of_measurement":"°C","min":40,"max":200,"step":5}},
    {"entity_id":"number.airfryer_5000_series_l_cloud_imposta_tempo_di_cottura","state":"0","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Imposta tempo di cottura","unit_of_measurement":"min","min":1,"max":60,"step":1}},
    {"entity_id":"number.airfryer_5000_series_l_cloud_durata_mantieni_caldo","state":"60","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Durata mantieni caldo","unit_of_measurement":"min","min":1,"max":180,"step":1}},
    {"entity_id":"number.airfryer_5000_series_l_cloud_temperatura_mantieni_caldo","state":"65","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Temperatura mantieni caldo","unit_of_measurement":"°C","min":40,"max":80,"step":5}},
    {"entity_id":"sensor.airfryer_5000_series_l_cloud_stato_cottura","state":"standby","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Stato cottura"}},
    {"entity_id":"sensor.airfryer_5000_series_l_cloud_temperatura_impostata","state":"0.0","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Temperatura impostata","unit_of_measurement":"°C"}},
    {"entity_id":"sensor.airfryer_5000_series_l_cloud_tempo_di_cottura_totale","state":"0","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Tempo di cottura totale","unit_of_measurement":"min"}},
    {"entity_id":"sensor.airfryer_5000_series_l_cloud_tempo_rimanente","state":"0.00","attributes":{"friendly_name":"Airfryer 5000 Series L (Cloud) Tempo rimanente","unit_of_measurement":"s"}}
    ]
    """
    let itMap = AutoMap.map(try! JSONDecoder().decode([Entity].self, from: Data(it.utf8)))
    check(itMap["start"]?.hasSuffix("avvia_cottura") == true, "it: start cooking")
    check(itMap["pause"]?.hasSuffix("pausa") == true && itMap["stop"]?.hasSuffix("stop") == true, "it: pause and stop")
    check(itMap["temp"]?.hasSuffix("imposta_temperatura") == true, "it: set temperature")
    check(itMap["time"]?.hasSuffix("imposta_tempo_di_cottura") == true, "it: set cooking time")
    check(itMap["status"]?.hasSuffix("stato_cottura") == true, "it: cooking status")
    check(itMap["remaining"]?.hasSuffix("tempo_rimanente") == true, "it: time remaining")

    // Real entities exported from a Home Assistant with an HD9255 (air fryer only, no personal data).
    let real = try! JSONDecoder().decode([Entity].self, from: try! Data(contentsOf: URL(fileURLWithPath: "Tests/fixture_hd9255.json")))
    let rm = AutoMap.map(real)
    check(rm.count == 8, "real: all 8 roles matched (\(rm.count))")
    check(rm["status"] == "sensor.airfryer_5000_series_l_cloud_stato_cottura", "real: status = cooking status, not firmware")
    check(rm["time"] == "number.airfryer_5000_series_l_cloud_imposta_tempo_di_cottura", "real: duration")
    check(rm["temp"] == "number.airfryer_5000_series_l_cloud_imposta_temperatura", "real: temperature")
    check(rm["power"] == "switch.airfryer_5000_series_l_cloud_alimentazione", "real: power, not preheating")

    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    let (_, resp) = try! await session.data(from: URL(string: address + "/redirect")!)
    check((resp as? HTTPURLResponse)?.statusCode == 302, "redirects are not followed")
}

await run()
print(failures == 0 ? "All tests passed" : "\(failures) tests failed")
exit(failures == 0 ? 0 : 1)
