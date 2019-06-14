//
//  ARSceneLocationView+ObjectInteraction.swift
//
//  Created by Sergey Blazhko on 3/13/18.
//  Copyright © 2018 Sergey Blazhko. All rights reserved.
//

import UIKit
import SceneKit

protocol ARObjectSelectionDelegate: class {
    func postNodeSelected(_ postNode: PostLocationNode)
}

extension ARSceneLocationView {
    enum ARObjectInteractionRecognizerType: String {
        case objectSelection
    }
    //MARK: - Public
    func enableObjectSelection() {
        if let recognizer = addedRecognizerWithType(.objectSelection) {
            recognizer.isEnabled = true
            return
        }
        
        let tapRecognizer: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapRecognizer.numberOfTapsRequired = 1
        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.delegate = self
        tapRecognizer.name = ARObjectInteractionRecognizerType.objectSelection.rawValue
        addGestureRecognizer(tapRecognizer)
        
        isUserInteractionEnabled = true
    }
    
    func disableObjectSelection(removeRecognizer: Bool = false) {
        guard let selectionRecognizer = addedRecognizerWithType(.objectSelection) else { return }
        if removeRecognizer {
            removeGestureRecognizer(selectionRecognizer)
        } else {
            selectionRecognizer.isEnabled = false
        }
    }
    
    //MARK: - Private
    private func addedRecognizerWithType(_ type: ARObjectInteractionRecognizerType) -> UIGestureRecognizer? {
        guard let recognizers = gestureRecognizers else { return nil }
        
        return recognizers.lazy.flatMap({ (recognizer) -> UIGestureRecognizer? in
            return recognizer.name == type.rawValue ? recognizer : nil
        }).first
    }
    
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: self)
        let hitTestOptions: [SCNHitTestOption: Any] = [.boundingBoxOnly: false,
                                                       .categoryBitMask: ARObjectCategoryBitMask.post.rawValue]
        
        let hitTestResults = hitTest(location, options: hitTestOptions)
        
        guard let firstObject = hitTestResults.first?.node.parent as? PostLocationNode else { return }
        objectSelectionDelegate?.postNodeSelected(firstObject)
    }
}

extension ARSceneLocationView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let recognizerName = gestureRecognizer.name,
           let _ = ARObjectInteractionRecognizerType.init(rawValue: recognizerName) else { return true }
        return !addedPostNodes.isEmpty
    }
}
