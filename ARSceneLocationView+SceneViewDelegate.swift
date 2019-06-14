//
//  ARSceneLocationView+SceneViewDelegate.swift
//
//  Created by Andrew Hart on 02/07/2017.
//  Copyright © 2017 Project Dent. All rights reserved.
//
//  Modified by Sergey Blazhko on 08/03/18.
//  Copyright © 2018 Sergey Blazhko. All rights reserved.
//

import ARKit
import SceneKit

protocol ARSceneLocationViewDelegate: class {
    func session(_ session: ARSession, didFailWithError error: Error)
}

extension ARSceneLocationView: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        
        if !didFetchInitialLocation || session.currentFrame == nil { return }
        //Current frame and current location are required for this to be successful
        if let currentLocation = LocationManager.shared.currentLocation {
            didFetchInitialLocation = true
            addSceneLocationEstimate(location: currentLocation)
        }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        run()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sceneLocationViewDelegate?.session(session, didFailWithError: error)

        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self,
                                                   selector: #selector(self.restartSessionAfterError),
                                                   object: nil)
            self.perform(#selector(self.restartSessionAfterError), with: nil, afterDelay: 0.15)
        }
    }
    
    @objc
    private func restartSessionAfterError() {
        resetSession()
    }
}
