//
//  ARSceneLocationView.swift
//
//  Created by Andrew Hart on 02/07/2017.
//  Copyright © 2017 Project Dent. All rights reserved.
//
//  Modified by Sergey Blazhko on 08/03/18.
//  Copyright © 2018 Sergey Blazhko. All rights reserved.
//

import Foundation
import ARKit
import CoreLocation

class ARSceneLocationView: ARSCNView {
    
    ///The limit to the scene, in terms of what data is considered reasonably accurate.
    ///Measured in meters.
    private static let sceneLimit = 5.0

    private var sceneLocationEstimates = [SceneLocationEstimate]()

    private var updateEstimatesTimer: Timer?
    var didFetchInitialLocation = false
    
    var currentScenePosition: SCNVector3? {
        guard let pointOfView: SCNNode = pointOfView else { return nil }
        return scene.rootNode.convertPosition(pointOfView.position, to: sceneNode)
    }
    
    private let objectsUpdatingQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".ARObjectsAdjustingQueue", qos: .userInitiated)
    
    ///The best estimation of location that has been taken
    ///This takes into account horizontal accuracy, and the time at which the estimation was taken
    ///favouring the most accuratesus, and then the most recent result.
    ///This doesn't indicate where the user currently is.
    private var bestLocationEstimate: SceneLocationEstimate? {
        let sortedLocationEstimates = sceneLocationEstimates.sorted(by: {
            if $0.location.horizontalAccuracy == $1.location.horizontalAccuracy {
                return $0.location.timestamp > $1.location.timestamp
            }
            return $0.location.horizontalAccuracy < $1.location.horizontalAccuracy
        })
        
        return sortedLocationEstimates.first
    }
    
    private var currentHeading: CLLocationDirection?

    private var currentLocation: CLLocation? {
        guard let bestEstimate = bestLocationEstimate,
            let position = currentScenePosition else { return nil }

        return bestEstimate.translatedLocation(to: position)
    }
    
    //Delegates
    weak var sceneLocationViewDelegate: ARSceneLocationViewDelegate?
    weak var objectSelectionDelegate: ARObjectSelectionDelegate? {
        didSet {
            if objectSelectionDelegate != nil {
                enableObjectSelection()
            } else {
                disableObjectSelection()
            }
        }
    }

    //AR objects
    private lazy var sceneNode: SCNNode = {
        let node = SCNNode()
        scene.rootNode.addChildNode(node)
        return node
    }()
    
    var addedPostNodes = [String : PostLocationNode] ()
    
    // MARK: - Initializing
    init(frame: CGRect, options: [String : Any]? = nil,
         objectSelectionDelegate: ARObjectSelectionDelegate? = nil,
         sceneLocationViewDelegate: ARSceneLocationViewDelegate? = nil) {
        self.sceneLocationViewDelegate = sceneLocationViewDelegate
        self.objectSelectionDelegate = objectSelectionDelegate
        
        super.init(frame: frame, options: options)
        
        initialSetup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        initialSetup()
    }
    
    private func initialSetup() {
        delegate = self
        
        autoenablesDefaultLighting = true
        automaticallyUpdatesLighting = true
        
        if objectSelectionDelegate != nil {
            enableObjectSelection()
        }
        
        //Needs to avoid session errors
        NotificationCenter.default.addObserver(forName: .UIApplicationDidEnterBackground,
                                               object: nil,
                                               queue: nil) {[weak self] (notification) in
            self?.pause()
        }
        
        NotificationCenter.default.addObserver(forName: .UIApplicationWillEnterForeground,
                                               object: nil,
                                               queue: nil) {[weak self] (notification) in
            self?.run()
        }

    }
    
    /**
     * Start sceneView session.
     */
     func run() {
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            print("Acces to the camera not provided")
            return
        }
        
        if !ARWorldTrackingConfiguration.isSupported {
            print("ARWorldTrackingConfiguration not supported by device")
            return
        }

		let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        
        session.run(configuration, options: [.resetTracking,
                                             .removeExistingAnchors])
        debugOptions = []

        updateEstimatesTimer?.invalidate()
        updateEstimatesTimer = Timer.scheduledTimer(timeInterval: 0.25,
                                                    target: self,
                                                    selector: #selector(updateLocationData),
                                                    userInfo: nil,
                                                    repeats: true)
    }
    
    func pause() {
        session.pause()
        updateEstimatesTimer?.invalidate()
        updateEstimatesTimer = nil
    }
    
    //Mark: - Reset
    func resetSession() {
        session = ARSession()
        run()
    }

    func resetPosts() {
        for post in addedPostNodes.values {
            post.removeFromParentNode()
        }
        addedPostNodes.removeAll()
    }
    
    //MARK: - Location - related
    @objc private func updateLocationData() {
        self.removeOldLocationEstimates()
        self.updatePositionAndScaleOfLocationNodes()
    }
    
    ///Adds a scene location estimate based on current time, camera position and location from location manager
    func addSceneLocationEstimate(location: CLLocation) {
        if let position = currentScenePosition {
            let sceneLocationEstimate = SceneLocationEstimate(location: location, position: position)
            self.sceneLocationEstimates.append(sceneLocationEstimate)
        }
    }
    
    private func removeOldLocationEstimates() {
        if let currentScenePosition = currentScenePosition {
            let currentPoint = CGPoint.pointWithVector(vector: currentScenePosition)
            sceneLocationEstimates = sceneLocationEstimates.filter({
                let point = CGPoint.pointWithVector(vector: $0.position)
                return currentPoint.radiusContainsPoint(radius: CGFloat(ARSceneLocationView.sceneLimit), point: point)
            })
        }
    }

    //MARK: - LocationNodes
    
    func addNode(_ node: PostLocationNode) {
        self.updatePositionAndScaleOfLocationNode(node)
        self.addedPostNodes[node.post.id] = node
        self.sceneNode.addChildNode(node)
    }

    func removeNode(_ node: PostLocationNode) {
        self.addedPostNodes.removeValue(forKey: node.post.id)
        node.removeFromParentNode()
    }
    
    func updatePositionAndScaleOfLocationNodes() {
            objectsUpdatingQueue.async {
            guard !self.addedPostNodes.isEmpty else { return }
            for node in self.addedPostNodes.values {
                if node.continuallyUpdatePositionOrScale {
                    self.updatePositionAndScaleOfLocationNode(node, animated: true)
                }
            }
        }
    }
    
    func updatePositionAndScaleOfLocationNode(_ node: LocationNode,
                                              animated: Bool = false,
                                              duration: TimeInterval = 0.3) {
        
            guard let currentPosition = currentScenePosition,
                let currentLocation = currentLocation else { return }
        
            if !animated {
                node.adjustToCurrentLocation(currentLocation,
                                             withScenePosition: currentPosition)
                return
            }
            
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            
            node.adjustToCurrentLocation(currentLocation,
                                         withScenePosition: currentPosition)
            SCNTransaction.commit()
        }
}

//MARK: - Add/Remove/Update Posts

extension ARSceneLocationView {
    
    func postReported(post: Post) {
        objectsUpdatingQueue.async {
            if let node = self.addedPostNodes[post.id] {
                self.removeNode(node)
            }
        }
    }
    
    func newPostCreated(_ post: Post) {
        objectsUpdatingQueue.async {
            self.addPostIfNoExist(post, isRecentlyAdded: true)
        }
    }
    
    func postsLoaded(_ posts: [Post]) {
        objectsUpdatingQueue.async {
            var newPostIds: Set<String> = Set()
            for post in posts {
                newPostIds.insert(post.id)
                self.addPostIfNoExist(post)
            }
            self.removeOldPosts(newPostIds: newPostIds)
        }
    }
    
    // update original post with added reply
    func replyCreatedFor(originalPostId: String, reply: Post) {
        objectsUpdatingQueue.async {
            if let postLocationNode = self.addedPostNodes[originalPostId] {
                postLocationNode.createdReply(reply)
            }
        }
    }
    
    // update original post without reported reply
    func replyReportedIn(originalPostId: String, reply: Post) {
        objectsUpdatingQueue.async {
            if let postLocationNode = self.addedPostNodes[originalPostId] {
                postLocationNode.reportedReply(reply)
            }
        }
    }
}

// MARK: - Private
private extension ARSceneLocationView {
    func addPostIfNoExist(_ post: Post, isRecentlyAdded: Bool = false) {
        if let addedPost = addedPostNodes[post.id] {
            addedPost.updateWith(post: post)
            return
        }
        
        let postNode: PostLocationNode
        if !isRecentlyAdded {
            postNode = PostLocationNode(post: post)
        } else {
            // add new postNode at current location & heading
            guard let location = currentLocation, let heading = currentHeading else { return }
            let shiftedLocation = location.coordinate.coordinateWithBearingShifted(bearing: heading, distanceMeters: 1)
            
            var post = post
            post.coordinates = shiftedLocation
            postNode = PostLocationNode(post: post)
        }
        
        addNode(postNode)
    }
    
    func removeOldPosts(newPostIds: Set<String>) {
        let addedpostIds = addedPostNodes.keys
        
        for key in addedpostIds {
            if !newPostIds.contains(key), let post = addedPostNodes[key] {
                removeNode(post)
            }
        }
    }
}

//MARK: - LocationManagerDelegate -
extension ARSceneLocationView  {
    func locationManagerDidUpdateLocation(_ location: CLLocation) {
        addSceneLocationEstimate(location: location)
    }
    
    func locationManagerDidUpdateHeading(_ heading: CLLocationDirection) {
        currentHeading = heading
    }
}
