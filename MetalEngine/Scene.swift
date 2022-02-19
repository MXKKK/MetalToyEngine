//
//  Scene.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/13.
//

import Foundation
import MetalKit

class Scene{
    let inputController = InputController()
    //let physicsController = PhysicsController()
    var renderType = forwardRendering
    var sceneSize: CGSize
    var cameras = [Camera()]
    var lights: [Light_Uniform] = []
    //var sun_light: Light_Uniform?
    var currentCameraIndex = 0
    var camera: Camera  {
      return cameras[currentCameraIndex]
    }
    var lightCount = 0
    var shadow_type = NoShadow
    var skybox: Skybox?
    
    init(sceneSize: CGSize){
        self.sceneSize = sceneSize
        setupScene()
        sceneSizeWillChange(to: sceneSize)
    }
    
    let rootNode = Node()
    var renderables: [Renderable] = []
    var emitters:[Emitter] = []
    var uniforms = Uniforms()
    var fragmentUniforms = FragmentUniforms()
    
    func setupScene(){
        
    }
    
    private func updatePlayer(deltaTime: Float){
        guard let node = inputController.player else {return}
        let holdPosition = node.position
        let holdRotation = node.rotation
        inputController.updatePlayer(deltaTime: deltaTime)
//        if physicsController.checkCollisions() && !updateCollidedPlayer() {
//          node.position = holdPosition
//          node.rotation = holdRotation
//        }
    }
    
    func updateCollidedPlayer() -> Bool {
      // override this
      return false
    }
    
    final func update(deltaTime: Float) {
      updatePlayer(deltaTime: deltaTime)
      
      uniforms.projectionMatrix = camera.projectionMatrix
      uniforms.viewMatrix = camera.viewMatrix
        uniforms.inv_viewMatrix = camera.viewMatrix.inverse
        uniforms.inv_viewNormalMatrix = uniforms.inv_viewMatrix.upperLeft
        uniforms.viewNormalMatrix = camera.viewMatrix.upperLeft
      fragmentUniforms.cameraPosition = camera.position
        fragmentUniforms.lightCount = uint(lightCount)
      
      updateScene(deltaTime: deltaTime)
      update(nodes: rootNode.children, deltaTime: deltaTime)
    }
    
    private func update(nodes: [Node], deltaTime: Float) {
      nodes.forEach { node in
        node.update(deltaTime: deltaTime)
        update(nodes: node.children, deltaTime: deltaTime)
      }
    }
    
    func updateScene(deltaTime: Float) {
      // override this to update your scene
    }
    
    func tessellation(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms, fragment: FragmentUniforms){
        //override this to tesselate
    }
    
    final func add(node: Node, parent: Node? = nil, render: Bool = true) {
      if let parent = parent {
        parent.add(childNode: node)
      } else {
        rootNode.add(childNode: node)
      }
      guard render == true,
        let renderable = node as? Renderable else {
          return
      }
      renderables.append(renderable)
    }
    
    final func remove(node: Node) {
      if let parent = node.parent {
        parent.remove(childNode: node)
      } else {
        for child in node.children {
          child.parent = nil
        }
        node.children = []
      }
      guard node is Renderable,
        let index = (renderables.firstIndex {
          $0 as? Node === node
        }) else { return }
      renderables.remove(at: index)
    }
    
    func sceneSizeWillChange(to size: CGSize) {
      for camera in cameras {
        camera.aspect = Float(size.width / size.height)
      }
      sceneSize = size
    }
    
}
