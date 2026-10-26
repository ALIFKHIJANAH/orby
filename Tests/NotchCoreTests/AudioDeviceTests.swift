import Foundation
import Testing

@testable import NotchCore

@Suite struct AudioDeviceTests {
    private func device(_ transport: AudioDeviceInfo.Transport, name: String = "Device", output: Bool = true,
                        uid: String = "uid") -> AudioDeviceInfo {
        AudioDeviceInfo(uid: uid, name: name, transport: transport, hasOutput: output)
    }

    @Test func classifiesByTransport() {
        #expect(device(.bluetooth).isHeadphone(appearedAfterLaunch: true))
        #expect(device(.bluetoothLE).isHeadphone(appearedAfterLaunch: true))
        #expect(device(.usb).isHeadphone(appearedAfterLaunch: true))
        #expect(!device(.other).isHeadphone(appearedAfterLaunch: true))
        #expect(!device(.bluetooth, output: false).isHeadphone(appearedAfterLaunch: true))
    }

    @Test func builtInOnlyCountsWhenPluggedInLater() {
        #expect(device(.builtIn, name: "External Headphones").isHeadphone(appearedAfterLaunch: true))
        #expect(!device(.builtIn, name: "MacBook Pro Speakers").isHeadphone(appearedAfterLaunch: false))
    }

    @Test func readsAddressFromUID() {
        #expect(device(.bluetooth, uid: "08-e4-df-d2-8d-2d:output").bluetoothAddress == "08:E4:DF:D2:8D:2D")
        #expect(device(.usb, uid: "AppleUSBAudioEngine:Foo:1").bluetoothAddress == nil)
    }

    private let report = Data("""
        {"SPBluetoothDataType": [{
          "controller_properties": {"controller_address": "BC:D0:74:32:1A:A4"},
          "device_connected": [
            {"Alif’s AirPods Pro": {"device_address": "AA:BB:CC:DD:EE:FF", "device_batteryLevelLeft": "85%",
              "device_batteryLevelRight": "90%", "device_batteryLevelCase": "40%"}},
            {"KiiP TH60": {"device_address": "03:4D:E4:DF:AA:69", "device_batteryLevelMain": "60%"}},
            {"NOVA v4": {"device_address": "D1:0A:38:30:00:53"}}
          ],
          "device_not_connected": [
            {"Old Buds": {"device_address": "11:22:33:44:55:66", "device_batteryLevelMain": "10%"}}
          ]
        }]}
        """.utf8)

    @Test func airPodsBatteryByAddress() {
        let b = BluetoothReport.battery(json: report, address: "aa-bb-cc-dd-ee-ff", name: "AirPods")
        #expect(b == HeadphoneBattery(left: 85, right: 90, caseLevel: 40))
        #expect(b?.summary == 85)
    }

    @Test func headsetBatteryByName() {
        let b = BluetoothReport.battery(json: report, address: nil, name: "KiiP TH60")
        #expect(b?.main == 60)
        #expect(b?.summary == 60)
    }

    @Test func noBatteryOrNotConnected() {
        #expect(BluetoothReport.battery(json: report, address: "D1:0A:38:30:00:53", name: "NOVA v4") == nil)
        #expect(BluetoothReport.battery(json: report, address: "11:22:33:44:55:66", name: "Old Buds") == nil)
        #expect(BluetoothReport.battery(json: Data("nope".utf8), address: nil, name: "x") == nil)
    }

    @Test func headsetBatteryFromPowerSources() {
        let out = """
            Now drawing from 'Battery Power'
             -InternalBattery-0 (id=22872163)\t49%; discharging; 1:50 remaining present: true
             -NOVA v4 (id=1080890507)\t32%; 
             -KiiP TH60 (id=1222644877)\t70%; discharging present: true
            """
        #expect(PowerSourceReport.battery(pmset: out, name: "KiiP TH60") == HeadphoneBattery(main: 70))
        #expect(PowerSourceReport.battery(pmset: out, name: "KiiP") == nil)
        #expect(PowerSourceReport.battery(pmset: out, name: "AirPods") == nil)
    }
}
