//
//  TestScene.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/14.
//

import Foundation
import MetalKit

class TestScene: Scene{
    
    
    let rt = deferredRendering
    let car = Model(name: "racing-car.obj", shadowTypes: PCF, renderType: deferredRendering, fragmentFunctionName: "fragment_mainPBR",enableRSM: false)
//    let orthoCamera = OrthographicCamera()
    let light = Light(name: "sun-light")
    let ground = Model(name: "ground.obj", shadowTypes: PCF, renderType: deferredRendering,enableRSM: false)
    let skeleton = Model(name: "skeletonWave.usda", shadowTypes: PCF, renderType: deferredRendering,enableRSM: false)
//    let light2 = Light(name: "point-light")
//    let terrain = Terrains(name: "hill",size: [8, 8], height: 1)
    //let snowEmitter = Renderer.snow(position: [0, 10, 0], xRange: 10.0, zRange: 10.0)
//    let Lantern = Model(name: "Lantern.obj", shadowTypes: NoShadow, renderType: forwardRendering)
    let sponza = Model(name: "Table.obj", shadowTypes: PCF, renderType: deferredRendering, enableRSM: false)
    let lantern = Model(name: "Lantern.obj", shadowTypes: PCF, renderType: deferredRendering, enableRSM: false)
    

    override func setupScene() {
        
        renderType = rt
        shadow_type = PCF
        
        skybox = Skybox(textureName: "sky")
        light.light.position = [1.0, 1.0, -2.0]
//        light.light.position = [0, -1, 0]
        light.light.type = Sunlight
        light.light.color = [0.5, 0.5, 0.5]
        light.light.specularColor = [0.2, 0.2, 0.2]
        //light.light.intensity = 0.6
        light.isVisible = false
        
        add(node: light)
        //add(node: snowEmitter)
//        add(node: Lantern)
        //emitters.append(snowEmitter)
        self.lights.append(light.light)
        self.lightCount += 1
        
        
//        light2.light.position = [0,1,0]
//        light2.light.type = Pointlight
//        light2.light.color = [0.0, 1.0, 0.0]
//        light2.light.specularColor = [0. 0, 1.0, 0.0]
//        light2.light.attenuation = [1.0, 3.0, 2.0]
//        light2.isVisible = false
//
//        self.lights.append(light2.light)
//        self.lightCount += 1
      camera.position = [0, 3, -4]
      //add(node: car, parent: camera)
//        add(node: car)
//        add(node: light2)
//        car.position = [0.35, 0, 0.1]
//        car.rotation = [0, .pi / 2, 0]
        
//        add(node: terrain)
//        terrain.position = [0,0,0]
        
        inputController.keyboardDelegate = self
        skeleton.rotation = [Float(-.pi / 2.0), 0, 0]
        skeleton.position = [6, -5, 6]
        //skeleton.rotation = [.pi, -.pi, .pi]
        skeleton.scale = [500.0,500.0, 500.0]
        //skeleton.runAnimation(name: "wave")
        ground.position = [0, -5, 0]
        //ground.scale = [2.0, 1.0, 2.0]
        ground.tiling = 1
        add(node: ground)
//        Lantern.position = [0.35, 0, 0.1]
//        Lantern.scale = [10.0, 10.0, 10.0]
        car.position = [10.0, -5.0, 10.0]
        car.scale = [3.0, 3.0, 3.0]
        sponza.position = [0.35, -5.0, 0.1]
        sponza.scale = [5.0, 5.0, 5.0]
        lantern.position = [0.0, 1.0, 0.0]
        lantern.scale = [3.0, 3.0, 3.0]
        add(node: car)
        add(node: skeleton)
        skeleton.runAnimation(name: "wave")
        add(node: sponza)
        add(node: lantern, parent: sponza, render: true)
//        add(node: Lantern)
        //car.scale = [100.0, 100.0, 10]
      
      inputController.translationSpeed = 10.0
      inputController.player = camera
      
//      orthoCamera.position = [0, 2, 0]
//      orthoCamera.rotation.x = .pi / 2
//      cameras.append(orthoCamera)
      
     
    }
    
    override func updateCollidedPlayer() -> Bool {
      return false
    }
    
    override func tessellation(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms, fragment: FragmentUniforms) {
//        terrain.tessellation(computeEncoder: computeEncoder, uniforms: uniforms, fragmentUniforms: fragment)
//        snowEmitter.updateParticles(computeEncoder: computeEncoder, uniforms: uniforms, fragmentUniforms: fragment)
        computeEncoder.endEncoding()
    }
    override func sceneSizeWillChange(to size: CGSize) {
      super.sceneSizeWillChange(to: size)
      
      
    }
}
extension TestScene: KeyboardDelegate {
  func keyPressed(key: KeyboardControl, state: InputState) -> Bool {
    switch key {
    case .key0:
      currentCameraIndex = 0
    //case .w:
      //currentCameraIndex = 1
    default:
      break
    }
    return true
  }
}
