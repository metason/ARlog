//
//  ARlogUpload.swift
//
//  Created by Gabriel Ankeshian on 22.02.19. Contact: gabriel.ankeshian@gmail.com
//

#if DEBUG

import Foundation               // includes URLSession
import SystemConfiguration

public class ARlogUpload {

    // Settings
    let doUpload = true       // if this is true ARlog will try to upload
    let onlyWifi = false       // if this is true it will only upload when wifi is available
    let largeOnlyWifi = false  // if this is true large files will only be uploaded when wifi is connected
    let serverURL = "https://service.metason.net/arlog" // URL of the server endpoint "http://<ip>:<port>"
    
    // Internal objects
    var projectID = ""         // projectID of the AR project, where it is saved on the server
    
    init(projectID: String) {
        self.projectID = projectID
    }
    
    // upload functionality
    func upload(_ sessionFilesUrl: String,_ sessionName: String){
        var dynUpload = doUpload
        
        if (isWifi() == true && onlyWifi == true){
            dynUpload = true
        }
        if (isWifi() == false && onlyWifi == true){
            dynUpload = false
        }
        if (largeOnlyWifi == true && isWifi() == true){
            dynUpload = true
        }
        if (largeOnlyWifi == true && isWifi() == false){
            dynUpload = false
        }
        
        if (isConnection() == false){
            dynUpload = false
            print("there is no connection to any network")
        }
        
        if (doUpload == true && dynUpload == true){
            let uploadUrl = URL(string: serverURL + "/log/" + projectID + "/" + sessionName)
            singleFileUploader(sessionFilesUrl, uploadUrl!)
        } else if (doUpload == false){
            print("Uploads are disabled.")
        } else if (dynUpload == false){
            print("no upload possible. something conflicts with your flags, is your wifi on?")
        } else{
            print("something is going wrong")
        }
    }

    // uploads all the files belonging to a session
    func singleFileUploader(_ sessionFilesUrl: String,_ uploadUrl: URL){
        let sessionJsonFile = URL(string: sessionFilesUrl + "session.json")
        let videoFile = URL(string: sessionFilesUrl + "screen.mp4")
        let mapsFolder = URL(string: sessionFilesUrl + "maps/")
        let scenesFolder = URL(string: sessionFilesUrl + "scenes/")
        
        // upload the session files in the session directory
        fileUpload(sessionJsonFile!, uploadUrl, "session", "application/json", "session.json")
        if (!(isLargeFile(videoFile!))){
            fileUpload(videoFile!, uploadUrl, "session", "video/mp4", "screen.mp4")
        } else {
            print("video file too large for upload")
        }
        
        // loop through the folders of the session directory to upload each file
        // https://stackoverflow.com/a/47761434
        let fm = FileManager()
        do {
            if dirExists(scenesFolder!.path){
            let fileURLs = try fm.contentsOfDirectory(at: scenesFolder!, includingPropertiesForKeys: nil)

            for fileUrl in fileURLs{
                fileUpload(fileUrl, uploadUrl, "scenes", "scene", fileUrl.lastPathComponent)
                }
            } else {print("scenes folder does not exists")}

            if dirExists(mapsFolder!.path){
                let fileURLs = try fm.contentsOfDirectory(at: mapsFolder!, includingPropertiesForKeys: nil)
                for fileUrl in fileURLs{
                    fileUpload(fileUrl, uploadUrl, "maps", "application/json", fileUrl.lastPathComponent)
                }
            } else {
                print("maps folder does not exists")
            }

        } catch {
            print("Error while enumerating files: \(error.localizedDescription)")
        }
    }
    
    func fileUpload(_ uploadFile: URL, _ uploadUrl: URL, _ subfolder: String, _ contentType: String,_ filename: String) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: uploadUrl.path, isDirectory: &isDirectory)
        if !exists || isDirectory.boolValue {
            return
        }
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "POST"
        request.setValue(subfolder, forHTTPHeaderField: "X-Session-Subfolder")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        let config = URLSessionConfiguration.background(withIdentifier: UUID().uuidString)
        let session = URLSession(configuration: config)
//        print(request)
        
        let task = session.uploadTask(with: request, fromFile: uploadFile)
        task.resume()
    }

    func isLargeFile(_ fileUrl: URL) -> Bool{
        // if a file is larger than 100mb this function will return true
        let fileSize = fileUrl.fileSize;
        if (fileSize >= 104857600){
            return true
        } else {
            return false
        }
    }
    
    func dirExists(_ fullPath: String) -> Bool {
        // https://stackoverflow.com/a/24696209
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        if fileManager.fileExists(atPath: fullPath, isDirectory:&isDir) {
            if isDir.boolValue {
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }
    
    func isWifi() -> Bool {
        return Reachability.isConnectedToWifi()
    }

    func isCellular() -> Bool{
        return (Reachability.isConnectedToNetwork() && !(Reachability.isConnectedToWifi()))
    }

    func isConnection() -> Bool{
        return (Reachability.isConnectedToWifi() || Reachability.isConnectedToNetwork())
    }
}


extension URL {
    // https://stackoverflow.com/a/48566887
    var attributes: [FileAttributeKey : Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch let error as NSError {
            print("FileAttribute error: \(error)")
        }
        return nil
    }
    
    var fileSize: UInt64 {
        return attributes?[.size] as? UInt64 ?? UInt64(0)
    }
    
    var fileSizeString: String {
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    var creationDate: Date? {
        return attributes?[.creationDate] as? Date
    }
}


public class Reachability {
    // https://stackoverflow.com/a/39782859

    class func isConnectedToNetwork() -> Bool {

        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)

        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }

        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }

        /* Only Working for WIFI
         let isReachable = flags == .reachable
         let needsConnection = flags == .connectionRequired

         return isReachable && !needsConnection
         */

        // Working for Cellular and WIFI
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)

        return ret
    }
    
    class func isConnectedToWifi() -> Bool{
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        /* Only Working for WIFI */
        let isReachable = flags == .reachable
        let needsConnection = flags == .connectionRequired
        let ret = (isReachable && !needsConnection)
        
        return ret;
    }
}
#endif
