//
//  ARlogItems.swift
//
//  Created by Philipp Ackermann on 30.09.18. Contact: philipp@metason.net
//  Copyright © 2018 Philipp Ackermann. All rights reserved.
//  See https://github.com/metason/ARlog for more details
//

#if os(iOS)
import UIKit
#endif

// STATIC SETTING DEFAULTS
private let ARLOG_VERSION = 1 // current version of ARlog & its LogSession data structure

// ENUMS -------------------------------------------------------------------------

// Hint: single character symbols are shown in timeline of ARInspector, others are  internally used

public enum LogLevel: String {
    case info = "ℹ︎" // info
    case debug = "❗️" // debug
    case warning = "⚠️" // warning
    case error = "‼️" // error
    case severe = "🔥" // severe
}

public enum LogSymbol: String {
    case data = "📂" // codable data as json
    case capture = "📐" // AR capturing
    case map = "🌐" // AR world map / space map / point cloud
    case scene = "✚" // 3D element added to scene
    case touch = "◎" // touch interaction
    case plane = "⬛️" // AR detected plane
    case planeUpdate = "🔲" // Update of AR detected plane
    case image = "📷" // AR detected image
    case object = "⚫️" // AR detected object
    case face = "🙂" // AR detected face
    case anchor = "📌" // anchor in AR world
    case fps = "fps" // frames per second
    case cam = "cam" // AR camera
    case yshift = "yShift" // shift world coordinate reference in height (e.g. to plane)
}

// LOG ITEMS -------------------------------------------------------------------------

public struct LogItem : Codable {
    var time:Double = 0.0 // delta time to sessionStart in seconds
    var type:String
    var title:String
    var data:String = "" // depends on type: text or json string
    var ref:String = "" // UUID of object or filename of asset, such as:
                        // screen recording (.mp4), 3D (scenes/*.scn), or WorldMaps (maps/*.json)
    var status:String = "" // floats for cpu usage in %, memory usage in MB

    private enum CodingKeys: String, CodingKey {
        case time
        case type
        case title
        case data
        case ref
        case status
    }
    
    init(type:String, title:String) {
        #if os(iOS)
        self.time = getDeltaTime()
        self.status = getStatus()
        #endif
        self.type = type
        self.title = title
    }
    
    init(type:String, title:String, text:String) {
        #if os(iOS)
        self.time = getDeltaTime()
        self.status = getStatus()
        #endif
        self.type = type
        self.title = title
        self.data = text
    }
    
    init(type:String, title:String, assetPath:String) {
        #if os(iOS)
        self.time = getDeltaTime()
        self.status = getStatus()
        #endif
        self.type = type
        self.title = title
        self.ref = assetPath
    }
    
    init(type:String, title:String, data:String, withStatus:Bool = true) {
        #if os(iOS)
        self.time = getDeltaTime()
        if withStatus {
            self.status = getStatus()
        }
        #endif
        self.type = type
        self.title = title
        self.data = data
    }
    
    init(type:String, title:String, data:String, assetPath:String) {
        #if os(iOS)
        self.time = getDeltaTime()
        self.status = getStatus()
        #endif
        self.type = type
        self.title = title
        self.data = data
        self.ref = assetPath
    }
}

// Session Data -------------------------------------------------------------------------

public struct SessionLocation : Codable {
    var latitude: Double = 0.0  // geolocation
    var longitude: Double = 0.0 // geolocation
    var countryCode:String = ""
    var country:String = ""
    var state:String = ""
    var postalCode:String = ""
    var city:String = ""
    var address: String = ""
}

public struct SessionDevice : Codable {
    var name:String = ""
    var model:String = ""
    var OS:String = ""
    var OSversion:String = ""
    var CPUcores: Int = 0
    var memory:Float = 0.0 // in MB
    var totalStorage:Float = 0.0 // in MB
    var freeStorage:Float = 0.0 // in MB
    var screenWidth:Float = 0.0
    var screenHeight:Float = 0.0

    init() {
#if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        self.model = identifier
        self.name = UIDevice.current.name
        self.OS = UIDevice.current.systemName
        self.OSversion = UIDevice.current.systemVersion
        self.screenWidth = Float(UIScreen.main.bounds.width)
        self.screenHeight = Float(UIScreen.main.bounds.height)
        self.CPUcores = ProcessInfo.processInfo.processorCount
        self.memory = Float(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0)
        do {
            let systemAttributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory() as String)
            let space = (systemAttributes[FileAttributeKey.systemSize] as? NSNumber)?.int64Value
            self.totalStorage = Float(space!) / (1024.0 * 1024.0)
            var freeSpace:Int64 = 0
            if #available(iOS 11.0, *) {
                freeSpace = try! URL(fileURLWithPath: NSHomeDirectory() as String).resourceValues(forKeys: [URLResourceKey.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage! 
            } else {
                freeSpace = ((systemAttributes[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value)!
            }
            self.freeStorage = Float(freeSpace) / (1024.0 * 1024.0)
        } catch {
            
        }
#endif
    }
}

public struct LogSession : Codable {
    var sessionName:String = ""
    var logVersion = ARLOG_VERSION // version of LogSession data structure
    var appName:String = ""
    var appVersion:String = ""
    var appID:String = "" // Bundle identifier
    var kitVersion:String = "" // ARKit version, not yet detected (ToDo)
    var sessionStart:String = ""
    var location:SessionLocation = SessionLocation()
    var user:String = ""
    var organisation:String = ""
    var extra:String = ""
    var device:SessionDevice = SessionDevice()
    var cameraInterval:Double = 0.0 // will be taken from default settings in ARlog.swift
    var sceneInterval:Double = 0.0 // will be taken from default settings in ARlog.swift
    var videoFormat = "mp4" // mp4
    var sceneFormat = "scn" // scn, (dae Collada would be nice but export not supported on iOS)
    var logItems:Array<LogItem> = []

    init(name:String, startTime:String) {
        self.sessionName = name
        self.sessionStart = startTime
        #if os(iOS)
        self.appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        self.appID = Bundle.main.bundleIdentifier!
        #endif
    }
}

// DEVICE STATUS -------------------------------------------------------------------------

func getDeltaTime() -> Double {
#if os(iOS)
    let dt:TimeInterval = Date.init().timeIntervalSince(ARlog.sessionStart!)
    return dt
#else
    return -1.0
#endif
}

#if os(iOS)

// returns cpu mem (ToDo: gpu)
func getStatus() -> String {
    return String(cpuUsage()) + " " + String(memoryUsage())
}

func mach_task_self() -> task_t {
    return mach_task_self_
}

func memoryUsage() -> Float { // in MB
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
    let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
        return infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (machPtr: UnsafeMutablePointer<integer_t>) in
            return task_info(
                mach_task_self(),
                task_flavor_t(MACH_TASK_BASIC_INFO),
                machPtr,
                &count
            )
        }
    }
    guard kerr == KERN_SUCCESS else {
        return -1
    }
    return Float(info.resident_size) / (1024 * 1024)
}

private func cpuUsage() -> Float { // in %
    let basicInfoCount = MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
    var kern: kern_return_t
    var threadList = UnsafeMutablePointer<thread_act_t>.allocate(capacity: 1)
    var threadCount = mach_msg_type_number_t(basicInfoCount)
    var threadInfo = thread_basic_info.init()
    var threadInfoCount: mach_msg_type_number_t
    var threadBasicInfo: thread_basic_info
    var threadStatistic: UInt32 = 0
    kern = withUnsafeMutablePointer(to: &threadList) {
        #if swift(>=3.1)
        return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
            task_threads(mach_task_self_, $0, &threadCount)
        }
        #else
        return $0.withMemoryRebound(to: (thread_act_array_t?.self)!, capacity: 1) {
        task_threads(mach_task_self_, $0, &threadCount)
        }
        #endif
    }
    if kern != KERN_SUCCESS {
        return -1
    }
    if threadCount > 0 {
        threadStatistic += threadCount
    }
    var totalUsageOfCPU: Float = 0.0
    for i in 0..<threadCount {
        threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
        kern = withUnsafeMutablePointer(to: &threadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                thread_info(threadList[Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
            }
        }
        if kern != KERN_SUCCESS {
            return -1
        }
        threadBasicInfo = threadInfo as thread_basic_info
        if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
            totalUsageOfCPU = totalUsageOfCPU + Float(threadBasicInfo.cpu_usage) / Float(TH_USAGE_SCALE) * 100.0
        }
    }
    return totalUsageOfCPU
}
#endif

// AR DATA CAPTURING -------------------------------------------------------------------------
// Data structures to store ARWorldMap & ARAnchors device-independantly (e.g. for macOS without ARKit)
// Points are relative to the world coordinate origin of the session,
// which is the place the device was when the AR session recording started.

public struct SpaceAnchor : Codable {
    var name: String = "" // A descriptive name for the anchor.
    var id: String = "" // UUID: A unique identifier for the anchor.
    var transform: [Float] = [Float]() // A float4x4 matrix encoding anchor relative to the world coordinate
}

public struct DetectedPlane : Codable {
    var name: String = "" // A descriptive name for the anchor.
    var id: String = "" // UUID: A unique identifier for the anchor.
    var transform: [Float] = [Float]() // A float4x4 matrix encoding anchor relative to the world coordinate
    var type: String = "unknown" // values: unknown, floor, wall, ceiling, table, seat
    var alignment: String = "unknown" // values: unknown, horizontal, vertical
    var center:[Float] = [Float]() // float3: Center point of the map's space-mapping data
    var extent:[Float] = [Float]() // float3: The size of the map's point cloud
    var points: [Float] = [Float]() // array of float3: vertices of contour boundary
}

public struct SpaceMap : Codable {
    var center:[Float] = [Float]() // float3: Center point of the map's point cloud
    var extent:[Float] = [Float]() // float3: The size of the map's point cloud
    var anchors:[SpaceAnchor] = [SpaceAnchor]() // The set of anchors recorded in the world map/space map
    var points: [Float] = [Float]() // array of float3: The list of detected points
    var identifiers: [UInt64] = [UInt64] () // UUIDs corresponding to detected float3 feature points? Not used!
}
