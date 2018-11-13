//
//  ARlog.swift
//
//  Created by Philipp Ackermann on 30.09.18. Contact: philipp@metason.net
//  Copyright © 2018 Philipp Ackermann. All rights reserved.
//  See https://github.com/metason/ARlog for more details
//

#if DEBUG

import Foundation
import SceneKit
import ARKit
import ReplayKit

// STATIC SETTING DEFAULTS
private let ARLOG_ENABLED = true // turn functionality of ARlog on/off
// Be aware of storage usage by ARlog especially by screen recording.
private let MAX_SAVED_SESSIONS = 4 // Amount of sessions on device. Olders will be deleted.

// CONSTANTS
public let atSessionStart:Double = 0.0
public let atSessionEnd:Double = Double.greatestFiniteMagnitude

// MAIN CLASS -------------------------------------------------------------------------

public class ARlog {
    // Settings: configurable during run-time, but typically before ARlog.start()
    static public var maxSavedSessions = MAX_SAVED_SESSIONS
    static public var autoLogScene:Bool = true
    static public var continouslyLogScene:Bool = false // if false only scenes with changes in nodes are captured
    static public var autoLogMap:Bool = true // autolog WorldMaps
    static public var autoLogPlanes:Bool = true
    //static public var autoLogImages:Bool = false // not yet implemented
    //static public var autoLogObjects:Bool = false // not yet implemented
    //static public var autoLogFaces:Bool = false // not yet implemented
    // Intervals for auto logging: no autologging when interval = 0.0
    static public var cameraInterval:Double = 0.5 // interval for storing camera/device poses
    static public var sceneInterval:Double = 0.25 // interval for storing 3D scenes when continouslyLogScene is true
    static public var mapInterval:Double = 1.0 // interval for storing AR world maps / space maps
    static let fpsInterval:Double = 1.0 // frames per second, therefore interval is 1.0

    // Internal objects
    static var isEnabled = ARLOG_ENABLED
    static var sessionStart:Date?
    static var sessionFolder:URL?
    static var isScreenRecording = false // is recording
    static var isRecordingWell = false // is recording without error
    static var assetWriter: AVAssetWriter!
    static var videoInput: AVAssetWriterInput!
    static var testCases:[ARTestCase] = []
    static var session:LogSession!
    static var dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }
    static let encoder = JSONEncoder()
    
    // observed objects
    static var sceneView:ARSCNView?
    static var stub = ARlogStub() // is used as delegate forwarder for static ARlog

    // time-dependent variables
    static var cameraResetTime:Date = Date.init()
    static var sceneResetTime:Date = Date.init()
    static var mapResetTime:Date = Date.init()
    static var previousPointsCount:Int = 0
    static var previousNodesCount:Int = 0
    static var fpsResetTime:Date = Date.init()
    static var frameCount = -1
    static var testResetTime:Date = Date.init()

    // public static functions
    
    static func start(_ observing:ARSCNView, sessionName:String = "ARSCNView") {
        if !isEnabled {
            print(LogLevel.warning.rawValue + " ARlog session recording is disabled!")
            return
        }
        ARlog.sessionStart = Date.init() // now
        ARlog.sessionFolder = ARlog.createSessionFolder()
        ARlog.session = LogSession(name: sessionName, startTime: (ARlog.sessionStart?.toString())!)
        ARlog.encoder.outputFormatting = .prettyPrinted
        ARlog.encoder.dateEncodingStrategy = .iso8601
        ARlog.session.cameraInterval = ARlog.cameraInterval
        if ARlog.autoLogScene {
            ARlog.session.sceneInterval = ARlog.cameraInterval
        } else {
            ARlog.session.sceneInterval = 0.0
        }
        
        // ToDo: fix
        //ARlog.session.kitVersion = arKitVersion
        
        ARlog.sceneView = observing
        ARlog.startScreenRecording()
    }
    
    // use finalizeFunction to set user, location, and extra
    static func stop(finalizeFunction: () -> Void = {}) {
        // run missing tests
        for test in testCases {
            if !test.executed {
                test.passed = test.condition()
                if test.passed {
                    ARlog.session.logItems.append(LogItem(type: LogSymbol.passed.rawValue, title: test.description))
                } else {
                    ARlog.session.logItems.append(LogItem(type: LogSymbol.failed.rawValue, title: test.description))
                }
                test.executed = true
            }
        }
        
        finalizeFunction()
        if !isEnabled {
            return
        }
        ARlog.session.logItems.append(LogItem(type: LogLevel.info.rawValue, title: "Screen recording stopped", data: (ARlog.sessionStart?.toString())!, assetPath: "screen.mp4"))
        ARlog.stopScreenRecording()
        ARlog.saveSession()
        // clean-up for a next session
        ARlog.sceneView = nil
        previousPointsCount = 0
        frameCount = -1
    }
    
    static func info(_ str:String) {
        ARlog.text(str, level:LogLevel.info, title: "Info")
    }
    
    static func debug(_ str:String) {
        ARlog.text(str, level:LogLevel.debug, title: "Debug")
    }
    
    static func warning(_ str:String) {
        ARlog.text(str, level:LogLevel.warning, title: "Warning")
    }
    
    static func error(_ str:String) {
        ARlog.text(str, level:LogLevel.error, title: "Error")
    }
    
    static func severe(_ str:String) {
        ARlog.text(str, level:LogLevel.severe, title: "Severe Bug")
    }
    
    static func text(_ str:String, level:LogLevel = .debug) {
        ARlog.text(str, level:level, title: "Message")
    }
    
    static func text(_ str:String, level:LogLevel = .debug, title:String = "Message") {
        print(level.rawValue + " " + title + ": " + str)
        if !isEnabled { return }
        ARlog.session.logItems.append(LogItem(type: level.rawValue, title: title, data: str))
    }
    
    static public func data(_ jsonStr:String, title:String = "Data") {
        if !isEnabled { return }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.data.rawValue, title: title, data: jsonStr))
    }
    
    static public func touch(_ at:CGPoint, long:Bool = false, title:String = "") {
        if !isEnabled { return }
        var str = title
        if str.count < 2 {
            if long {
                str = "Long Tap Interaction"
            } else {
                str = "Touch Interaction"
            }
        }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.touch.rawValue, title: str, data: String(format:"%i %i", Int(at.x), Int(at.y))))
    }
    
    // shift World Coordinate (WC) system in height (e.g., to detected plane
    static public func shiftWC(y:Float) {
        if !isEnabled { return }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.yshift.rawValue, title: "Shift WC in y", data: String(y), withStatus: false))
    }
    
    static public func fps(_ fps:Int) {
        if !isEnabled { return }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.fps.rawValue, title: "fps", data: String(fps)))
    }
    
    static public func cam(_ transform:SCNMatrix4) {
        if !isEnabled { return }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.cam.rawValue, title: "cam", data: transform.toString(), withStatus: false))
    }
    
    static public func capture(_ str:String, title:String = "AR Capturing") {
        if !isEnabled { return }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.capture.rawValue, title: title, data: str))
    }
    
    static public func scene(_ scene:SCNScene, title:String = "Scene") {
        if !isEnabled { return }
        let fileName = Date.init().toBaseName() + ".scn"
        let scenesURL = sessionFolder?.appendingPathComponent("scenes", isDirectory: true)
        let fileURL = scenesURL?.appendingPathComponent(String(fileName))
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: scenesURL!.path, isDirectory: &isDirectory)
        if !exists {
            do {
                try fileManager.createDirectory(at: scenesURL!, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                ARlog.text("Error: \(error.debugDescription)", level: LogLevel.error)
                return
            }
        }
        scene.write(to: fileURL!, options: nil, delegate: nil) { (totalProgress, error, stop) in
            if error != nil {
                print("Scene writing progress \(totalProgress). Error: \(String(describing: error))")
            }
        }
        let counter = countNodes(scene.rootNode)
        let str = String(format: "%i nodes", counter)
        ARlog.session.logItems.append(LogItem(type: LogSymbol.scene.rawValue, title: title, data: str, assetPath: fileName))
        ARlog.previousNodesCount = counter
        if autoLogScene && sceneInterval > 0.0 {
            let now = Date.init()
            sceneResetTime = now.addingTimeInterval(sceneInterval)
        }
    }
    
    @available(iOS 12.0, *)
    static public func mapOf(_ session:ARSession, title:String = "Map") {
        session.getCurrentWorldMap { (worldMap, error) in
            guard let worldMap = worldMap else {
                print("Error getting current world map.")
                return
            }
            ARlog.map(worldMap)
        }
    }
    
    @available(iOS 12.0, *)
    static public func map(_ map:ARWorldMap, title:String = "Map") {
        if !isEnabled { return }
        let fileName = Date.init().toBaseName() + ".json"
        let mapsURL = sessionFolder?.appendingPathComponent("maps", isDirectory: true)
        let fileURL = mapsURL?.appendingPathComponent(String(fileName))
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: mapsURL!.path, isDirectory: &isDirectory)
        if !exists {
            do {
                try fileManager.createDirectory(at: mapsURL!, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                ARlog.text("Error: \(error.debugDescription)", level: LogLevel.error)
                return
            }
        }
        var pointAmount = 0
        var anchorAmount = 0
        do {
            var spaceMap = SpaceMap()
            // transfer ARWorldMap to SpaceMap
            spaceMap.center = [map.center.x, map.center.y, map.center.z]
            spaceMap.extent = [map.extent.x, map.extent.y, map.extent.z]
            anchorAmount = map.anchors.count
            for i in 0..<map.anchors.count {
                var anchor = SpaceAnchor()
                if map.anchors[i].name != nil {
                    anchor.name = map.anchors[i].name!
                }
                anchor.id = map.anchors[i].identifier.uuidString
                let matrix = SCNMatrix4(map.anchors[i].transform)
                anchor.transform = matrix.toFloats()
                spaceMap.anchors.append(anchor)
            }
            let points = map.rawFeaturePoints.points
            pointAmount = points.count
            for i in 0..<points.count {
                spaceMap.points.append(points[i].x)
                spaceMap.points.append(points[i].y)
                spaceMap.points.append(points[i].z)
            }
            /* nothing in it?
            for i in 0..<map.rawFeaturePoints.identifiers.count {
                spaceMap.identifiers.append(map.rawFeaturePoints.identifiers[i])
            }
            */
            // save
            ARlog.encoder.outputFormatting = .prettyPrinted
            let data = try ARlog.encoder.encode(spaceMap)
            try data.write(to: fileURL!)
        } catch {
            ARlog.text("Error saving world map: \(error.localizedDescription)", level: LogLevel.severe)
        }
        let str = String(format: "%i points, %i anchors", pointAmount, anchorAmount)
        ARlog.session.logItems.append(LogItem(type: LogSymbol.map.rawValue, title: title, data: str, assetPath: fileName))
    }
    
    // colors as hexcode "#RRGGBBAA"
    static func dominantColors(primary:String, secondary:String = "", relRect:CGRect = CGRect(x:0.0, y:0.0, width:1.0, height:1.0)) {
        var observation = SpaceObservation()
        observation.type = ObservationType.dominantColors.rawValue
        observation.confidence = 1.0
        if secondary.count > 0 {
            observation.feature = primary + " " + secondary
        } else {
            observation.feature = primary
        }
        var str = "observation"
        observation.bbox.append(Float((relRect.origin.x)))
        observation.bbox.append(Float((relRect.origin.y)))
        observation.bbox.append(Float((relRect.size.width)))
        observation.bbox.append(Float((relRect.size.height)))
        ARlog.encoder.outputFormatting = .prettyPrinted
        let data = try? ARlog.encoder.encode(observation)
        if data != nil {
            str = String(data: data!, encoding: .utf8)!
        }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.image.rawValue, title: "Dominant Colors", data: str))
    }
    
    static func classifiedImage(label:String, confidence:Float, relRect:CGRect = CGRect(x:0.0, y:0.0, width:1.0, height:1.0)) {
        var observation = SpaceObservation()
        observation.type = ObservationType.classifiedImage.rawValue
        observation.feature = label
        observation.confidence = confidence
        var str = "observation"
        observation.bbox.append(Float((relRect.origin.x)))
        observation.bbox.append(Float((relRect.origin.y)))
        observation.bbox.append(Float((relRect.size.width)))
        observation.bbox.append(Float((relRect.size.height)))
        ARlog.encoder.outputFormatting = .prettyPrinted
        let data = try? ARlog.encoder.encode(observation)
        if data != nil {
            str = String(data: data!, encoding: .utf8)!
        }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.image.rawValue, title: "Image classified", data: str))
    }
    
    static func detectedImage(label:String, confidence:Float, relRect:CGRect = CGRect(x:0.0, y:0.0, width:1.0, height:1.0)) {
        var observation = SpaceObservation()
        observation.type = ObservationType.detectedImage.rawValue
        observation.feature = label
        observation.confidence = confidence
        var str = "observation"
        observation.bbox.append(Float((relRect.origin.x)))
        observation.bbox.append(Float((relRect.origin.y)))
        observation.bbox.append(Float((relRect.size.width)))
        observation.bbox.append(Float((relRect.size.height)))
        ARlog.encoder.outputFormatting = .prettyPrinted
        let data = try? ARlog.encoder.encode(observation)
        if data != nil {
            str = String(data: data!, encoding: .utf8)!
        }
        ARlog.session.logItems.append(LogItem(type: LogSymbol.image.rawValue, title: "Image detected", data: str))
    }
    
    // add test case with assertion to evaluate condition at time (in sec) after session start
    static func test(_ desc:String, assert: @escaping () -> Bool, at:Double = atSessionEnd) {
        let testCase = ARTestCase()
        testCase.description = desc
        testCase.condition = assert
        testCase.time = at
        testCases.append(testCase)
        testCases.sort(by: { $0.time < $1.time })
    }

    static func createSessionFolder() -> URL? {
        let fileManager = FileManager.default
        let documentDirectory = try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
        let arlogURL = documentDirectory?.appendingPathComponent("ARlogs", isDirectory: true)
        let foldername = sessionStart?.toFolderName()
        let sessionURL = arlogURL!.appendingPathComponent(foldername!, isDirectory: true)
        
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: arlogURL!.path, isDirectory: &isDirectory)
        if exists { // Delete old session folders when maxSavedSessions is reached
            do {
                let folderlist = try fileManager.contentsOfDirectory(at: arlogURL!, includingPropertiesForKeys: nil, options: [])
                if folderlist.count >= maxSavedSessions {
                    let sortedlist = folderlist.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    for i in 0...(sortedlist.count - maxSavedSessions) {
                        do {
                            try fileManager.removeItem(at: sortedlist[i])
                        } catch let error {
                            ARlog.text("Error: \(error.localizedDescription)", level: LogLevel.severe)
                        }
                    }
                }
            } catch let error {
                ARlog.text("Error: \(error.localizedDescription)", level: LogLevel.error)
                ARlog.isEnabled = false
                return nil
            }
        }
        // create new session directory
        do {
            try fileManager.createDirectory(at: sessionURL, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            ARlog.text("Error: \(error.debugDescription)", level: LogLevel.error)
            return nil
        }
        return sessionURL
    }
    
    static public func startScreenRecording() {
        guard !ARlog.isScreenRecording else {
            ARlog.text("Error: Screen recording already started!", level: LogLevel.severe)
            return
        }
        
        let videoURL = ARlog.sessionFolder!.appendingPathComponent("screen.mp4")
        ARlog.assetWriter = try! AVAssetWriter(outputURL: videoURL, fileType: AVFileType.mp4)
        
        // The size of the output video has to be a multiple of 16. A 2 pixels green line is going to be seen at the bottom and
        // on the right size of the video otherwise. Following two lines ensure this is respected.
        // Source: https://stackoverflow.com/questions/22883525
        let videoWidth = floor(UIScreen.main.bounds.size.width / 16) * 16
        let videoHeight = floor(UIScreen.main.bounds.size.height / 16) * 16
        //let videoWidth = UIScreen.main.bounds.size.width
        //let videoHeight = UIScreen.main.bounds.size.height
        
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight
        ]
        
        ARlog.videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
        ARlog.videoInput.expectsMediaDataInRealTime = true
        //ARlog.assetWriter.shouldOptimizeForNetworkUse = true
        ARlog.assetWriter.add(ARlog.videoInput)

        var recordingStarted = false
        RPScreenRecorder.shared().startCapture(handler: { sample, bufferType, error in
            ARlog.isRecordingWell = error == nil
            if error != nil {
                print(error!)
                return
            }
            
            if CMSampleBufferDataIsReady(sample) {
                if !recordingStarted {
                    ARlog.assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
                    recordingStarted = true
                }

                if ARlog.assetWriter.status == AVAssetWriter.Status.failed {
                    print("Error occured, status = \(ARlog.assetWriter.status.rawValue), \(ARlog.assetWriter.error!) \(String(describing: ARlog.assetWriter.error))")
                    return
                }
                
                if bufferType == .video {
                    if ARlog.videoInput.isReadyForMoreMediaData && isScreenRecording {
                        ARlog.videoInput.append(sample)
                    }
                }
            }
        }, completionHandler: { error in
            ARlog.isRecordingWell = error == nil
            if ARlog.isRecordingWell {
                ARlog.session.logItems.append(LogItem(type: LogLevel.info.rawValue, title: "Screen recording started", data: (Date.init().toString()), assetPath: "screen.mp4"))
                stub.primeDelegate = sceneView!.session.delegate
                sceneView!.session.delegate = stub // start listening to notifications
                if !ARlog.assetWriter.startWriting() {
                    print("Starting session failed")
                    isScreenRecording = false
                } else {
                    isScreenRecording = true
                }
            } else {
                ARlog.error("Screen recording failed! " + (error?.localizedDescription)!)
            }
        })
        
    }
    
    static public func stopScreenRecording() {
        guard ARlog.isScreenRecording else {
            return
        }
        ARlog.isScreenRecording = false
        RPScreenRecorder.shared().stopCapture { error in
            ARlog.assetWriter.finishWriting {
                ARlog.isRecordingWell = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Wait half a second to prevent crash due to object clean up while writing?
        }
    }
    
    static func saveSession() {
        let fileURL = sessionFolder?.appendingPathComponent("session.json")
        ARlog.encoder.outputFormatting = .prettyPrinted
        let data = try? ARlog.encoder.encode(session)
        if data != nil {
            try? data!.write(to: fileURL!)
        }
    }
    
    static func countNodes(_ node:SCNNode) -> Int {
        var i = 1 // node itself
        node.enumerateHierarchy({ _,_ in i = i + 1 })
        return i
    }
    
    // Stub functions
    
    static func createDetectedPlane(planeAnchor:ARPlaneAnchor) -> DetectedPlane {
        var plane = DetectedPlane()
        plane.name = "plane"
        if #available(iOS 12.0, *) {
            if planeAnchor.name != nil {
                plane.name = planeAnchor.name!
            }
        }
        plane.id = planeAnchor.identifier.uuidString
        let matrix = SCNMatrix4(planeAnchor.transform)
        plane.transform = matrix.toFloats()
        plane.center = [planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z]
        plane.extent = [planeAnchor.extent.x, planeAnchor.extent.y, planeAnchor.extent.z]
        if #available(iOS 12.0, *) {
            if ARPlaneAnchor.isClassificationSupported { // only on iPhone XS, iPhone XS Max, iPhone XR
                switch planeAnchor.classification {
                case .floor:
                    plane.type = "floor"
                    ARlog.shiftWC(y: planeAnchor.center.y)
                    break
                case .none(_):
                    plane.type = "unknown"
                case .wall:
                    plane.type = "wall"
                case .ceiling:
                    plane.type = "ceiling"
                case .table:
                    plane.type = "table"
                case .seat:
                    plane.type = "seat"
                }
            }
        } else {
            plane.type = "unknown"
        }
        switch planeAnchor.alignment {
            case .horizontal:
                plane.alignment = "horizontal"
            case .vertical:
                plane.alignment = "vertical"
            default:
                plane.alignment = "unknown"
        }
        let points = planeAnchor.geometry.boundaryVertices
        for i in 0..<points.count {
            plane.points.append(points[i].x)
            plane.points.append(points[i].y)
            plane.points.append(points[i].z)
        }
        return plane
    }
    
    static public func didAdd(anchor: ARAnchor) {
        // autolog for planes
        if ARlog.autoLogPlanes {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let plane = createDetectedPlane(planeAnchor: planeAnchor)
                var str = "plane"
                ARlog.encoder.outputFormatting = []
                let data = try? ARlog.encoder.encode(plane)
                if data != nil {
                    //str = (data?.base64EncodedString())! // if we want to hide?
                    str = String(data: data!, encoding: .utf8)!
                }
                ARlog.session.logItems.append(LogItem(type: LogSymbol.plane.rawValue, title: "Plane detected", data: str))
                return
            }
        }
        
        // Todo: check for images
        
        // Todo: check for objects
        
        // Todo: check for faces

    }
    
    static public func didUpdate(frame: ARFrame) {
        let now = Date.init()
        // autolog fps
        if frameCount == -1 { // initialize first
            fpsResetTime = now.addingTimeInterval(fpsInterval)
            frameCount = 0
        } else {
            frameCount = frameCount + 1
            if now.timeIntervalSince(fpsResetTime) >= 0.0 {
                // ToDo: calc fps to exact 1.0 second
                ARlog.fps(frameCount)
                fpsResetTime = now.addingTimeInterval(fpsInterval)
                frameCount = 0
            }
        }
        if sceneView != nil {
            // autolog camera pos
            if now.timeIntervalSince(cameraResetTime) >= 0.0 {
                ARlog.cam((sceneView!.pointOfView?.worldTransform)!)
                cameraResetTime = now.addingTimeInterval(cameraInterval)
            }
            // autolog scene
            if sceneView != nil {
                if now.timeIntervalSince(sceneResetTime) >= 0.0 {
                    let count = countNodes(sceneView!.scene.rootNode)
                    if ARlog.previousNodesCount != count || continouslyLogScene {
                        ARlog.scene(sceneView!.scene)
                        ARlog.previousNodesCount = count
                    }
                    if autoLogScene && sceneInterval > 0.0 {
                        sceneResetTime = now.addingTimeInterval(sceneInterval)
                    }
                }
            }
            // autolog map
            if #available(iOS 12.0, *) {
                if  frame.rawFeaturePoints != nil {
                    if now.timeIntervalSince(mapResetTime) >= 0.0 {
                        if ARlog.previousPointsCount != frame.rawFeaturePoints?.points.count {
                            ARlog.mapOf(sceneView!.session)
                            ARlog.previousPointsCount = (frame.rawFeaturePoints?.points.count)!
                        }
                        mapResetTime = now.addingTimeInterval(mapInterval)
                    }
                }
            }
        }
        // check tests
        if now.timeIntervalSince(testResetTime) >= 0.0 {
            for test in testCases {
                if now.timeIntervalSince(sessionStart!) >= test.time {
                    if !test.executed {
                        test.passed = test.condition()
                        if test.passed {
                            ARlog.session.logItems.append(LogItem(type: LogSymbol.passed.rawValue, title: test.description))
                        } else {
                            ARlog.session.logItems.append(LogItem(type: LogSymbol.failed.rawValue, title: test.description))
                        }
                        test.executed = true
                    }
                } else {
                    testResetTime = (sessionStart?.addingTimeInterval(test.time))!
                    break
                }
            }
            ARlog.cam((sceneView!.pointOfView?.worldTransform)!)
            testResetTime = now.addingTimeInterval(cameraInterval)
        }
    }
    
    static public func didUpdate(anchor: ARAnchor) {
        // check for planes (all plane updates, we can't apply a time interval)
        if ARlog.autoLogPlanes {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let plane = createDetectedPlane(planeAnchor: planeAnchor)
                var str = "plane"
                ARlog.encoder.outputFormatting = []
                let data = try? ARlog.encoder.encode(plane)
                if data != nil {
                    str = String(data: data!, encoding: .utf8)!
                }
                ARlog.session.logItems.append(LogItem(type: LogSymbol.planeUpdate.rawValue, title: "Plane update", data: str))
                return
            }
        }
        
        // Todo: check for images
        
        // Todo: check for objects
        
        // Todo: check for faces
        
    }
    
}

class ARlogStub : NSObject, ARSessionDelegate {
    var primeDelegate: ARSessionDelegate?

    // Delegate functions
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if primeDelegate != nil {
            primeDelegate?.session?(session, didUpdate: frame)
        }
        ARlog.didUpdate(frame: frame)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        if primeDelegate != nil {
            primeDelegate?.session?(session, didAdd: anchors)
        }
        for i in 0..<anchors.count {
            ARlog.didAdd(anchor: anchors[i])
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        if primeDelegate != nil {
            primeDelegate?.session?(session, didUpdate: anchors)
        }
        for i in 0..<anchors.count {
            ARlog.didUpdate(anchor: anchors[i])
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if primeDelegate != nil {
            primeDelegate?.session?(session, cameraDidChangeTrackingState: camera)
        }
        var text = "unknown"
        switch camera.trackingState {
        case .notAvailable:
            text = "AR detection not available!"
        case .normal:
            return
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                text = "Excessive motion"
            case .insufficientFeatures:
                text = "Insufficient features"
            case .initializing:
                text = "Initializing tracking"
            case .relocalizing:
                text = "Relocation of AR session"
            }
        }
        ARlog.capture(text, title: "Tracking State")
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        if primeDelegate != nil {
            primeDelegate?.session?(session, didFailWithError: error)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        if primeDelegate != nil {
            primeDelegate?.sessionWasInterrupted?(session)
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        if primeDelegate != nil {
            primeDelegate?.sessionInterruptionEnded?(session)
        }
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        if primeDelegate != nil {
            return primeDelegate?.sessionShouldAttemptRelocalization?(session) ?? false
        }
        return false
    }

    func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        if primeDelegate != nil {
            primeDelegate?.session?(session, didOutputAudioSampleBuffer: audioSampleBuffer)
        }
    }
    
}

class ARTestCase {
    var description: String = ""
    var time:Double = atSessionEnd
    var condition:() -> Bool = { return false }
    var executed:Bool = false
    var passed:Bool = false
}

// EXTENSIONS -------------------------------------------------------------------------

extension Date {
    func toString() -> String {
        return ARlog.dateFormatter.string(from: self as Date)
    }
    
    func toBaseName() -> String {
        let sessionname = self.toString()
        let shortname = sessionname.suffix(12)
        let filename = shortname.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ".", with: "")
        return filename
    }
    
    func toFolderName() -> String {
        let sessionname = self.toString()
        let indexEndOfName = sessionname.index(sessionname.endIndex, offsetBy: -4)
        let shortname = sessionname[..<indexEndOfName]
        let foldername = shortname.replacingOccurrences(of: ":", with: "")
        return foldername
    }
}

extension SCNMatrix4 {
    func toString() -> String {
        return String(format: "%f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f", m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44)
    }
    
    func toFloats() -> [Float] {
        return [m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44]
    }
}

#endif
