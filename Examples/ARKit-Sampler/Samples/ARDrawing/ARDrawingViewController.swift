//
//  ARDrawingViewController.swift
//  ARKit-Sampler
//
//  Created by Shuichi Tsutsumi on 2017/09/20.
//  Copyright © 2017 Shuichi Tsutsumi. All rights reserved.
//

import UIKit
import ARKit
import ColorSlider

class ARDrawingViewController: UIViewController, ARSCNViewDelegate {
    
    private var drawingNodes = [DynamicGeometryNode]()

    private var isTouching = false {
        didSet {
            pen.isHidden = !isTouching
        }
    }
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var statusLabel: UILabel!
    @IBOutlet var pen: UILabel!
    @IBOutlet var resetBtn: UIButton!

    @IBOutlet var colorSlider: ColorSlider!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup the color picker
        colorSlider.orientation = .horizontal
        colorSlider.previewEnabled = true
        
        sceneView.delegate = self
        sceneView.debugOptions = [SCNDebugOptions.showFeaturePoints]
        sceneView.scene = SCNScene()

        statusLabel.text = "Wait..."
        pen.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sceneView.session.run()
        ARlog.continouslyLogScene = true
        ARlog.start(sceneView, sessionName: "ARDrawing")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
        let myData = ["className": "ARDrawingViewController",
                      "function": "viewWillDisappear",
                      "status": statusLabel.text,
                      "pen": pen.text,
                      "drawingNodesAmount": String(self.drawingNodes.count)]
        ARlog.encoder.outputFormatting = .prettyPrinted
        let data = try? ARlog.encoder.encode(myData)
        if data != nil {
            let jsonStr = String(data: data!, encoding: .utf8)!
            ARlog.data(jsonStr)
        }
        ARlog.stop()
        ARlog.continouslyLogScene = false

    }
    
    // MARK: - Private
    
    private func reset() {
        for node in drawingNodes {
            node.removeFromParentNode()
        }
        drawingNodes.removeAll()
    }
    
    private func isReadyForDrawing(trackingState: ARCamera.TrackingState) -> Bool {
        switch trackingState {
        case .normal:
            return true
        default:
            return false
        }
    }
    
    private func worldPositionForScreenCenter() -> SCNVector3 {
        let screenBounds = UIScreen.main.bounds
        let center = CGPoint(x: screenBounds.midX, y: screenBounds.midY)
        let centerVec3 = SCNVector3Make(Float(center.x), Float(center.y), 0.99)
        return sceneView.unprojectPoint(centerVec3)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isTouching else {return}
        guard let currentDrawing = drawingNodes.last else {return}
        
        DispatchQueue.main.async(execute: {
            let vertice = self.worldPositionForScreenCenter()
            currentDrawing.addVertice(vertice)
        })
    }

    // MARK: - ARSessionObserver

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("\(self.classForCoder)/\(#function), error: " + error.localizedDescription)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        print("trackingState: \(camera.trackingState)")
        
        let state = camera.trackingState
        let isReady = isReadyForDrawing(trackingState: state)
        statusLabel.text = isReady ? "Touch the screen to draw." : "Wait. " + state.description
    }
    
    // MARK: - Touch Handlers
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let frame = sceneView.session.currentFrame else {return}
        guard isReadyForDrawing(trackingState: frame.camera.trackingState) else {return}
        
        let drawingNode = DynamicGeometryNode(color: colorSlider.color, lineWidth: 0.004)
        sceneView.scene.rootNode.addChildNode(drawingNode)
        drawingNodes.append(drawingNode)

        statusLabel.text = "Move your device!"

        isTouching = true
        guard let touch = touches.first else {return}
        let pos = touch.location(in: sceneView)
        ARlog.touch(pos)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        statusLabel.text = "Touch the screen to draw."
    }
    
    // MARK: - Actions

    @IBAction func resetBtnTapped(_ sender: UIButton) {
        reset()
    }
}

