//
//  Renderer.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

import Foundation
import MetalKit
import MetalPerformanceShaders

class Renderer: NSObject{
    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    static var colorPixelFormat: MTLPixelFormat!
    static var library: MTLLibrary!
    static var fps: Int!
    
    var uniforms = Uniforms()
    var renderType :RenderType
    var fragmentUniforms = FragmentUniforms()
    let depthStencilState: MTLDepthStencilState
    var scene: Scene?
    var shadowTexture: MTLTexture?
    var albedoTexture: MTLTexture?
    var normalTexture: MTLTexture?
    var positionTexture: MTLTexture?
    var depthTexture: MTLTexture?
    var materialPackTexture: MTLTexture?
    var enableMSAA = true

    
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor?
    var gBufferRenderPassDescriptor: MTLRenderPassDescriptor?
    
    var fogEnabled = false
    
    //for composition in deffered rendering
    var compositionPipelineState: MTLRenderPipelineState!

    var quadVerticesBuffer: MTLBuffer!
    var quadTexCoordsBuffer: MTLBuffer!

    let quadVertices: [Float] = [
      -1.0,  1.0,
       1.0, -1.0,
      -1.0, -1.0,
      -1.0,  1.0,
       1.0,  1.0,
       1.0, -1.0
    ]

    let quadTexCoords: [Float] = [
      0.0, 0.0,
      1.0, 1.0,
      0.0, 1.0,
      0.0, 0.0,
      1.0, 0.0,
      1.0, 1.0
    ]

    
    init(metalView: MTKView, renderType: RenderType =  forwardRendering) {
      guard
        let device = MTLCreateSystemDefaultDevice(),
        let commandQueue = device.makeCommandQueue() else {
          fatalError("GPU not available")
      }
      Renderer.device = device
      Renderer.commandQueue = commandQueue
      Renderer.library = device.makeDefaultLibrary()
      Renderer.colorPixelFormat = metalView.colorPixelFormat
      Renderer.fps = metalView.preferredFramesPerSecond
        self.renderType = renderType
     
      
      metalView.device = device
      metalView.depthStencilPixelFormat = .depth32Float
      
      depthStencilState = Renderer.buildDepthStencilState()!
      
      super.init()
      metalView.clearColor = MTLClearColor(red: 0.7, green: 0.9,
                                           blue: 1, alpha: 1)

      metalView.delegate = self
      mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
        
    

      //fragmentUniforms.lightCount = lighting.count
        
        //for deffered rendering
        quadVerticesBuffer =
            Renderer.device.makeBuffer(bytes: quadVertices,
              length: MemoryLayout<Float>.size * quadVertices.count,
              options: [])
        quadVerticesBuffer.label = "Quad vertices"
        quadTexCoordsBuffer =
            Renderer.device.makeBuffer(bytes: quadTexCoords,
              length: MemoryLayout<Float>.size * quadTexCoords.count,
              options: [])
        quadTexCoordsBuffer.label = "Quad texCoords"
        
        buildCompositionPipelineState()


    }
    
    static func buildDepthStencilState() -> MTLDepthStencilState? {
      let descriptor = MTLDepthStencilDescriptor()
      descriptor.depthCompareFunction = .less
      descriptor.isDepthWriteEnabled = true
      return
        Renderer.device.makeDepthStencilState(descriptor: descriptor)
    }
    
    static func heightToSlope(source: MTLTexture) -> MTLTexture{
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat, width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        guard let destination =
                Renderer.device.makeTexture(descriptor: descriptor),
              let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
        else { fatalError()}
        
        let shader = MPSImageSobel(device: Renderer.device)
    
        shader.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
        commandBuffer.commit()
        return destination
    }
    
    static func heightToNormal(source: MTLTexture) -> MTLTexture{
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        guard let destination =
                Renderer.device.makeTexture(descriptor: descriptor),
              let commandBuffer = Renderer.commandQueue.makeCommandBuffer(),
              let kernelFunction = library?.makeFunction(name: "heightToNormal")
        else { fatalError()}
        let computePipelineState =
            try! Renderer.device.makeComputePipelineState(function: kernelFunction)
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(source, index: 0)
        computeEncoder.setTexture(destination, index: 1)
        let width = computePipelineState.threadExecutionWidth
        let height = computePipelineState.maxTotalThreadsPerThreadgroup / width
        let threadsPerGroup = MTLSizeMake(width, height, 1)
        let threadsPerGrid = MTLSizeMake(Int(source.width), Int(source.height), 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        return destination
        
        
    }
    
    //set render according to scene
    func setRenderProperties(metalView: MTKView, sc: Scene){
        
        if sc.shadow_type != NoShadow{
            shadowRenderPassDescriptor = MTLRenderPassDescriptor()
            buildShadowTexture(size: CGSize(width: 4096.0, height: 4096.0) )
        }
        renderType = sc.renderType
        if renderType == deferredRendering{
            gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
            buildGBufferRenderPassDescriptor(size: metalView.drawableSize)
        }
    }
    
    func buildGbufferTextures(size: CGSize){
        albedoTexture = buildTexture(pixelFormat: .bgra8Unorm,
                                  size: size, label: "Albedo texture")
          normalTexture = buildTexture(pixelFormat: .rgba16Float,
                                  size: size, label: "Normal texture")
          positionTexture = buildTexture(pixelFormat: .rgba16Float,
                                  size: size, label: "Position texture")
        materialPackTexture = buildTexture(pixelFormat: .rgba16Float,
                                  size: size, label: "metallic + roughness + Ao texture")
          depthTexture = buildTexture(pixelFormat: .depth32Float,
                                  size: size, label: "Depth texture")
    }
    
    func buildGBufferRenderPassDescriptor(size: CGSize){
        gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
        buildGbufferTextures(size: size)
        let textures: [MTLTexture] = [albedoTexture!,
                                      normalTexture!,
                                      positionTexture!,
                                      materialPackTexture!]
        for (position, texture) in textures.enumerated(){
            gBufferRenderPassDescriptor?.setUpColorAttachment(position: position, texture: texture)
        }
        gBufferRenderPassDescriptor?.setUpDepthAttachment(texture: depthTexture!)
        
    }
    
    func renderCompositionPass(
        renderEncoder: MTLRenderCommandEncoder, skybox:Skybox?) {
      renderEncoder.pushDebugGroup("Composition pass")
      renderEncoder.label = "Composition encoder"
      renderEncoder.setRenderPipelineState(compositionPipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
      // Send the quad information to the vertex shader.
      renderEncoder.setVertexBuffer(quadVerticesBuffer,
                                    offset: 0, index: 0)
      renderEncoder.setVertexBuffer(quadTexCoordsBuffer,
                                    offset: 0, index: 1)
      // Send the G-buffer textures and lights array to the fragment shader.
      renderEncoder.setFragmentTexture(albedoTexture, index: 0)
      renderEncoder.setFragmentTexture(normalTexture, index: 1)
      renderEncoder.setFragmentTexture(positionTexture, index: 2)
        renderEncoder.setFragmentTexture(materialPackTexture, index: 3)
        renderEncoder.setFragmentTexture(depthTexture, index: 4)
        renderEncoder.setFragmentBytes(&fogEnabled,
                                       length: MemoryLayout<Bool>.size,
                                       index: Int(BufferIndexFog.rawValue))

        renderEncoder.setFragmentBytes(&scene!.lights,
                                       length: MemoryLayout<Light_Uniform>.stride * scene!.lightCount,
                                       index: Int(BufferIndexLights.rawValue))
        renderEncoder.setFragmentBytes(&scene!.fragmentUniforms,
        length: MemoryLayout<FragmentUniforms>.stride,
        index: Int(BufferIndexFragmentUniforms.rawValue))
        
        renderEncoder.setFragmentBytes(&fogEnabled,
                                       length: MemoryLayout<Bool>.size,
                                       index: Int(BufferIndexFog.rawValue))

      // Draw the quad
      renderEncoder.drawPrimitives(type: .triangle,
                                   vertexStart: 0,
                                   vertexCount: quadVertices.count)
        
        //render sky box
        if let skb = skybox{
            skb.render(renderEncoder: renderEncoder,
                                 uniforms: scene!.uniforms,
                                 renderType: renderType)
        }
        
        
      renderEncoder.endEncoding()
      renderEncoder.popDebugGroup()
    }
    
    func buildCompositionPipelineState(vertexFunctionName: String = "compositionVert",
                                       fragmentFunctionName: String = "compositionFrag") {
      let descriptor = MTLRenderPipelineDescriptor()
      if(enableMSAA)
      {
        descriptor.sampleCount = 4
      }
      descriptor.colorAttachments[0].pixelFormat =
          Renderer.colorPixelFormat
      descriptor.depthAttachmentPixelFormat = .depth32Float
      descriptor.label = "Composition state"
      descriptor.vertexFunction = Renderer.library.makeFunction(
        name: vertexFunctionName)
      descriptor.fragmentFunction = Renderer.library.makeFunction(
        name: fragmentFunctionName)
      do {
        compositionPipelineState =
          try Renderer.device.makeRenderPipelineState(
              descriptor: descriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
    }


    
    
}
    
    extension Renderer: MTKViewDelegate {
      func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.sceneSizeWillChange(to: size)
        buildShadowTexture(size: CGSize(width: 4096.0, height: 4096.0))
        //if (renderType == deferredRendering){
        buildGBufferRenderPassDescriptor(size: size)
        //}
        


      }
      
      func draw(in view: MTKView) {
        guard
          let scene = scene,
          //let descriptor = view.currentRenderPassDescriptor,
          let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
          else {
            return
        }
        for emitter in scene.emitters{
            emitter.emit()
        }
        
        view.sampleCount = 1
        // update all the models' poses
        let deltaTime = 1 / Float(Renderer.fps)
        scene.update(deltaTime: deltaTime)
        var uniform = scene.uniforms
        
        scene.tessellation(computeEncoder: commandBuffer.makeComputeCommandEncoder()!, uniforms: uniform, fragment: scene.fragmentUniforms)
        
        if scene.shadow_type != NoShadow{
            
        //shadow pass
        guard let shadowEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowRenderPassDescriptor!)else{
            return
        }
        shadowEncoder.label = "Shadow encoder"
        shadowEncoder.setCullMode(.none)
        shadowEncoder.setDepthStencilState(depthStencilState)
        shadowEncoder.setDepthBias(0.01, slopeScale: 1.0, clamp: 0.01)
       
            uniform.projectionMatrix = float4x4(orthoLeft: -30, right: 30, bottom: -30, top: 30, near: -30, far: 30)
            let sl = scene.lights[0]
        let pos: float3 = [sl.position.x, sl.position.y, sl.position.z]
        
        let center: float3 = [0, 0, 0]
        let lookAt = float4x4(eye: pos, center: center, up: [0, 1, 0])
        uniform.viewMatrix = lookAt
            uniform.shadowMatrix = uniform.projectionMatrix * uniform.viewMatrix
        for renderable in scene.renderables{
            shadowEncoder.pushDebugGroup(renderable.name)
            renderable.render_shadow(renderEncoder: shadowEncoder, uniforms: uniform)
            shadowEncoder.popDebugGroup()
        }
        
        shadowEncoder.endEncoding()
            
        }
        
        
        
        if(renderType == deferredRendering){
            //gbuffer pass
            guard let renderEncoder =
                    commandBuffer.makeRenderCommandEncoder(descriptor: gBufferRenderPassDescriptor!)else{
                return
            }
            renderEncoder.setDepthStencilState(depthStencilState)

            //set shadow_map
            if scene.shadow_type != NoShadow
            {
                renderEncoder.setFragmentTexture(shadowTexture,
                                                 index: Int(ShadowMap.rawValue))
            }
            
            
            uniform.viewMatrix = scene.uniforms.viewMatrix
            uniform.projectionMatrix = scene.uniforms.projectionMatrix
            //var lights = lighting.lights
            renderEncoder.setFragmentBytes(&scene.lights,
                                           length: MemoryLayout<Light_Uniform>.stride * scene.lightCount,
                                           index: Int(BufferIndexLights.rawValue))

            // render all the models in the array
            for renderable in scene.renderables {
              renderEncoder.pushDebugGroup(renderable.name)
              renderable.render(renderEncoder: renderEncoder,
                                uniforms: uniform,
                                fragmentUniforms: scene.fragmentUniforms)
              renderEncoder.popDebugGroup()
            }
            
            renderEncoder.endEncoding()
            guard let drawable = view.currentDrawable else {
              return
            }
            
            //composition pass
            if(enableMSAA)
            {
                view.sampleCount = 4
            }
            
            guard let descriptor = view.currentRenderPassDescriptor else {
                return
            }
           
            guard let compositionEncoder =
                    commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)else{
                return
            }
            //update skybox
            if let skb = scene.skybox{
                skb.update(renderEncoder: compositionEncoder)
            }
            renderCompositionPass(renderEncoder: compositionEncoder, skybox: scene.skybox)
            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            
        }
        else
        {
            if(enableMSAA)
            {
                view.sampleCount = 4
            }
            guard let descriptor = view.currentRenderPassDescriptor else {
                return
            }
            guard let renderEncoder =
                    commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)else{
                return
            }
            renderEncoder.setDepthStencilState(depthStencilState)

            //set shadow_map
            if scene.shadow_type != NoShadow
            {
                renderEncoder.setFragmentTexture(shadowTexture,
                                                 index: Int(ShadowMap.rawValue))
            }
            
            renderEncoder.setFragmentBytes(&fogEnabled,
                                           length: MemoryLayout<Bool>.size,
                                           index: Int(BufferIndexFog.rawValue))

            
            
            uniform.viewMatrix = scene.uniforms.viewMatrix
            uniform.projectionMatrix = scene.uniforms.projectionMatrix
            //var lights = lighting.lights
            renderEncoder.setFragmentBytes(&scene.lights,
                                           length: MemoryLayout<Light_Uniform>.stride * scene.lightCount,
                                           index: Int(BufferIndexLights.rawValue))

            //update skybox
            if let skb = scene.skybox{
                skb.update(renderEncoder: renderEncoder)
            }
            // render all the models in the array
            for renderable in scene.renderables {
              renderEncoder.pushDebugGroup(renderable.name)
                view.sampleCount = 4
              renderable.render(renderEncoder: renderEncoder,
                                uniforms: uniform,
                                fragmentUniforms: scene.fragmentUniforms)
              renderEncoder.popDebugGroup()
            }
            
            //render skybox
            scene.skybox?.render(renderEncoder: renderEncoder,
                                 uniforms: scene.uniforms,
                                 renderType: renderType)
            
            renderEncoder.endEncoding()
            guard let drawable = view.currentDrawable else {
              return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        

        
      }
    }

private extension MTLRenderPassDescriptor{
    func setUpColorAttachment(position: Int, texture: MTLTexture) {
      let attachment: MTLRenderPassColorAttachmentDescriptor =
        colorAttachments[position]
      attachment.texture = texture
      attachment.loadAction = .clear
      attachment.storeAction = .store
      attachment.clearColor = MTLClearColorMake(0.73, 0.92, 1, 1)
    }
    
    func setUpDepthAttachment(texture: MTLTexture){
        depthAttachment.texture = texture
        depthAttachment.loadAction = .clear
        depthAttachment.storeAction = .store
        depthAttachment.clearDepth  = 1
    }

}

