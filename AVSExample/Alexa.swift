//
//  ViewController.swift
//  AVSExample
//

import Cocoa
import AVFoundation
import GCDWebServers

class Alexa: NSObject, AVAudioPlayerDelegate, SimpleWebServerDelegate {
    
    @IBOutlet weak var recordButton: NSButton!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var configureButton: NSButton!
    
    @IBOutlet var menuBar: NSMenu!
    @IBOutlet weak var menuRecord: NSMenuItem!
    @IBOutlet weak var menuConfigure: NSMenuItem!
    @IBOutlet weak var menuStatus: NSMenuItem!
    
    private var webServerURL: NSURL?
    private var currentAccessToken: String?
    private var tokenExpirationTime: NSDate?
    
    private var isRecording = false
    
    private var simplePCMRecorder: SimplePCMRecorder
    
    private let tempFilename = "\(NSTemporaryDirectory())avsexample.wav"
    
    private var player: AVAudioPlayer?
    private var userDefaults = NSUserDefaults.standardUserDefaults()
    
    required init?(coder: NSCoder) {
        self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
        
       
    }
    
    override init() {
        
        
        
        self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
        let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
        statusItem.menu = menuBar
        
        
        self.menuStatus.enabled = false
        self.recordButton.enabled = false
        self.menuRecord.enabled = false
        
        self.statusLabel.stringValue = "Starting"
        self.menuStatus.title = "Starting"
        
        self.configureButton.enabled = true
        
        self.recordButton.continuous = true
        self.recordButton.setPeriodicDelay(0.075, interval: 0.075)
        
        
        
        // Have the recorder create a first recording that will get tossed so it starts faster later
        try! self.simplePCMRecorder.setupForRecording(tempFilename, sampleRate:16000, channels:1, bitsPerChannel:16, errorHandler: nil)
        try! self.simplePCMRecorder.startRecording()
        try! self.simplePCMRecorder.stopRecording()
        self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
        super.init()
        NSAppleEventManager.sharedAppleEventManager().setEventHandler(self, andSelector: "handleURLEvent", forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        SimpleWebServer.instance.delegate = self
        SimpleWebServer.instance.startWebServer()
    }
    
    @IBAction func recordingAction(sender: AnyObject?) {
        
        if menuRecord.state == NSOffState {
            if !self.isRecording {
                self.isRecording = true
                
                self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
                try! self.simplePCMRecorder.setupForRecording(tempFilename, sampleRate:16000, channels:1, bitsPerChannel:16, errorHandler: { (error:NSError) -> Void in
                    print(error)
                    try! self.simplePCMRecorder.stopRecording()
                })
                
                try! self.simplePCMRecorder.startRecording()
                
                self.statusLabel.stringValue = "Recording"
                self.menuStatus.title = "Recording"
                
            }
        } else {
            if self.isRecording {
                self.isRecording = false
                menuRecord.state = NSOffState
                
                self.menuRecord.enabled = false
                
                try! self.simplePCMRecorder.stopRecording()
                
                self.statusLabel.stringValue = "Uploading recording"
                self.menuStatus.title = "Uploading recording"
                
                self.upload()
            }
        }
    }
    @IBAction func recordAction(recordButton: NSButton) {
        
        if recordButton.state == NSOffState {
            if !self.isRecording {
                self.isRecording = true
                
                self.simplePCMRecorder = SimplePCMRecorder(numberBuffers: 1)
                try! self.simplePCMRecorder.setupForRecording(tempFilename, sampleRate:16000, channels:1, bitsPerChannel:16, errorHandler: { (error:NSError) -> Void in
                    print(error)
                    try! self.simplePCMRecorder.stopRecording()
                })
                
                try! self.simplePCMRecorder.startRecording()
                
                self.statusLabel.stringValue = "Recording"
                self.menuStatus.title = "Recording"
            }
        } else {
            if self.isRecording {
                self.isRecording = false
                recordButton.state = NSOffState
                
                self.recordButton.enabled = false
                
                try! self.simplePCMRecorder.stopRecording()
                
                self.statusLabel.stringValue = "Uploading recording"
                self.menuStatus.title = "Uploading recording"
                
                self.upload()
            }
        }
        
    }
    
    @IBAction func configureAction(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(self.webServerURL!)
    }
    
    
    private func upload() {
        let uploader = AVSUploader()
        
        uploader.authToken = self.currentAccessToken
        
        uploader.jsonData = self.createMeatadata()
        
        uploader.audioData = NSData(contentsOfFile: tempFilename)!
        
        uploader.errorHandler = { (error:NSError) in
            if Config.Debug.Errors {
                print("Upload error: \(error)")
            }
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.statusLabel.stringValue = "Upload error: \(error.localizedDescription)"
                self.menuStatus.title = "Upload error. See log."
                NSLog(error.localizedDescription)
                self.recordButton.enabled = true
                self.menuRecord.enabled = true
            })
        }
        
        uploader.progressHandler = { (progress:Double) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if progress < 100.0 {
                    self.statusLabel.stringValue = String(format: "Upload progress: %d", progress)
                    self.menuStatus.title = String(format: "Upload progress: %d", progress)
                } else {
                    self.statusLabel.stringValue = "Waiting for response"
                    self.menuStatus.title = "Waiting for response"
                }
            })
        }
        
        uploader.successHandler = { (data:NSData, parts:[PartData]) -> Void in
            
            for part in parts {
                if part.headers["Content-Type"] == "application/json" {
                    if Config.Debug.General {
                        print(NSString(data: part.data, encoding: NSUTF8StringEncoding))
                    }
                } else if part.headers["Content-Type"] == "audio/mpeg" {
                    do {
                        self.player = try AVAudioPlayer(data: part.data)
                        self.player?.delegate = self
                        self.player?.play()
                        
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.statusLabel.stringValue = "Playing response"
                            self.menuStatus.title = "Playing response"
                        })
                    } catch let error {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.statusLabel.stringValue = "Playing error: \(error)"
                            self.menuStatus.title = "Playback error. See log."
                            NSLog(String(error))
                            self.recordButton.enabled = true
                            self.menuRecord.enabled = true
                        })
                    }
                }
            }
            
        }
        
        try! uploader.start()
    }
    
    private func createMeatadata() -> String? {
        var rootElement = [String:AnyObject]()
        
        let deviceContextPayload = ["streamId":"", "offsetInMilliseconds":"0", "playerActivity":"IDLE"]
        let deviceContext = ["name":"playbackState", "namespace":"AudioPlayer", "payload":deviceContextPayload]
        rootElement["messageHeader"] = ["deviceContext":[deviceContext]]
        
        let deviceProfile = ["profile":"doppler-scone", "locale":"en-us", "format":"audio/L16; rate=16000; channels=1"]
        rootElement["messageBody"] = deviceProfile
        
        let data = try! NSJSONSerialization.dataWithJSONObject(rootElement, options: NSJSONWritingOptions(rawValue: 0))
        
        return NSString(data: data, encoding: NSUTF8StringEncoding) as String?
    }
    
    //
    // SimpleWebServerDelegate Impl
    //
    
    func startupComplete(webServerURL: NSURL) {
        userDefaults.synchronize()
        // Always force localhost as the host
        self.webServerURL = NSURL(scheme: webServerURL.scheme, host: "localhost:\(webServerURL.port!)", path: webServerURL.path!)
        if let accessToken = self.userDefaults.stringForKey("access_token") {
            self.currentAccessToken = accessToken
            self.tokenExpirationTime = userDefaults.objectForKey("tokenExpiresIn") as? NSDate
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.statusLabel.stringValue = "Ready"
                self.menuStatus.title = "Ready"
                self.recordButton.enabled = true
                self.menuRecord.enabled = true
            })
            
        } else {
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.statusLabel.stringValue = "Configuration needed"
                self.menuStatus.title = "Configuration needed"
                self.configureButton.enabled = true
            })
        }
    }
    
    func configurationComplete(tokenExpirationTime: NSDate, currentAccessToken: String) {
        self.currentAccessToken = currentAccessToken
        self.tokenExpirationTime = tokenExpirationTime
        
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.statusLabel.stringValue = "Ready"
            self.menuStatus.title = "Ready"
            self.recordButton.enabled = true
            self.menuRecord.enabled = true
        })
    }
    
    //
    // AVAudioPlayerDelegate Impl
    //
    
    func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.statusLabel.stringValue = "Ready"
            self.menuStatus.title = "Ready"
            self.recordButton.enabled = true
            self.menuRecord.enabled = true
        })
    }
    
    func audioPlayerDecodeErrorDidOccur(player: AVAudioPlayer, error: NSError?) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.statusLabel.stringValue = "Player error: \(error)"
            self.menuStatus.title = "Player error. See log."
            NSLog(String(error))
            self.recordButton.enabled = true
            self.menuRecord.enabled = true
        })
    }
    
    //
    // Handle app URL
    //
    
    func handleURLEvent() {
        if self.currentAccessToken != nil && self.tokenExpirationTime != nil {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.statusLabel.stringValue = "Ready"
                self.menuStatus.title = "Ready"
                self.recordButton.enabled = true
                self.menuRecord.enabled = true
            })
        } else {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.statusLabel.stringValue = "Configuration error"
                self.menuStatus.title = "Configuration error"
                self.recordButton.enabled = false
                self.menuRecord.enabled = false
            })
        }
    }
}

