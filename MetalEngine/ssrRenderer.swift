//
//  ssrRenderer.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/12/1.
//


import Foundation
import MetalKit
import MetalPerformanceShaders

class ssrRenderer: NSObject{
    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    static var colorPixelFormat: MTLPixelFormat!
    static var library: MTLLibrary!
    static var fps: Int!
    
    var uniforms = Uniforms()
    var renderType :RenderType = deferredRendering
    var fragmentUniforms = FragmentUniforms()
    let depthStencilState: MTLDepthStencilState
    var scene: Scene?
    var shadowTexture: MTLTexture?
    var albedoTexture: MTLTexture?
    var normalTexture: MTLTexture?
    var positionTexture: MTLTexture?
    var depthTexture: MTLTexture?
    var materialPackTexture: MTLTexture?
    var lightTexutre: MTLTexture?
    var directLightTexture: MTLTexture?
    var diffuseTexture: MTLTexture?
    var postProcessTexture1: MTLTexture?
    var postProcessTexture2: MTLTexture?
    var HizTexture: MTLTexture?
    
    //RSM textures
    var RSMposition: MTLTexture?
    var RSMnormal: MTLTexture?
    var RSMflux: MTLTexture?
    
    var enableMSAA = false
    var fogEnabled = false
    var enableRSM = false
    var m_ssrParam = ssrParam()

    
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor?
    var gBufferRenderPassDescriptor: MTLRenderPassDescriptor?
    var screenRTRenderPassDescriptor: MTLRenderPassDescriptor?
    var compositionRenderPassDescriptor: MTLRenderPassDescriptor?
    var fxaaRenderPassDescriptor: MTLRenderPassDescriptor?
    var coneTracingPassDescriptor: MTLRenderPassDescriptor?
    var depthBlitPassDescriptor: MTLRenderPassDescriptor?

    
    //for screen space ray tracing
    var screenRTPipelineState: MTLRenderPipelineState!
    //for composition in deffered rendering
    var compositionPipelineState: MTLRenderPipelineState!
    var coneTracingPipelineState: MTLRenderPipelineState!
    var minPoolingPipelineState: MTLComputePipelineState!
    var endPostPSO: MTLRenderPipelineState!
    var fxaaPSO: MTLRenderPipelineState!
    var depthBlitPSO: MTLRenderPipelineState!

    var quadVerticesBuffer: MTLBuffer!
    var quadTexCoordsBuffer: MTLBuffer!
    var samplesBuffer: MTLBuffer!

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
    
    let samples_num = 400
    var samples: [Float]
    

    
    init(metalView: MTKView) {
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
        
     
      
      metalView.device = device
      metalView.depthStencilPixelFormat = .depth32Float
      
      depthStencilState = Renderer.buildDepthStencilState()!
        
        m_ssrParam.depthBufferSize.x = 0.0
        m_ssrParam.depthBufferSize.y = 0.0
        m_ssrParam.zThickness = 0.3
        m_ssrParam.nearPlaneZ = 0.001
        m_ssrParam.farPlaneZ = 100.0
        m_ssrParam.stride = 1.0
        m_ssrParam.maxSteps = 400
        m_ssrParam.maxDistance = 400
        m_ssrParam.strideZCutoff = 200
        m_ssrParam.fadeStart = 0.1
        m_ssrParam.fadeEnd = 1.0
        
        samples = [Float](repeating: 0, count: 3 * samples_num)
        let PI = 3.1415926535897932384626433832795;
        var r_max = 0.3
        srand48(Int(time(nil)))
        for i in 0 ..< samples_num{
            var x1 = drand48()
            var x2 = drand48()
            samples[3 * i] = Float(r_max * x1 * sin(2.0 * PI * x2))
            samples[3 * i + 1] = Float(r_max * x1 * cos(2.0 * PI * x2))
            samples[3 * i + 2] = Float(x1 * x1);
            
        }
        
      super.init()
        metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0,
                                             blue: 0.0, alpha: 1)

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
        
        samplesBuffer = Renderer.device.makeBuffer(bytes: samples,
                                                   length: MemoryLayout<Float>.size * samples.count,
                                                   options: [])
        samplesBuffer.label = "Samples for RSM"
        
        buildComputePipelineState()
        buildCompositionPipelineState()
        buildScreenRTPipelineState()
        buildConeTracinglineState()
        buildDepthBlitPSO()
        buildFXAAPSO()
        buildEndPostPSO()


    }
    
    static func buildDepthStencilState() -> MTLDepthStencilState? {
      let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less;
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
            if(enableRSM)
            {
                buildRSMTextures(size: CGSize(width: 4096.0, height: 4096.0))
                shadowRenderPassDescriptor?.setUpColorAttachment(position: 0, texture: RSMposition!)
                shadowRenderPassDescriptor?.setUpColorAttachment(position: 1, texture: RSMnormal!)
                shadowRenderPassDescriptor?.setUpColorAttachment(position: 2, texture: RSMflux!)
                
            }
            
        }
            gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
            buildGBufferRenderPassDescriptor(size: metalView.drawableSize)
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
        lightTexutre = buildTexture(pixelFormat: .rgba16Float, size: size, label: "Light texture")
        
        diffuseTexture = buildTexture(pixelFormat: .rgba16Float, size: size, label: "diffuseTexture", mipmapped: true)
        
        directLightTexture = buildTexture(pixelFormat: .rgba16Float, size: size, label: "directLightTexture")
        
        
        HizTexture = buildTexture(pixelFormat: .r32Float, size: CGSize(width: 2048, height: 2048), label: "Hierarchical Z-Buffer", mipmapped: true, enable_write: true)
        
        
    }
    
    func buildRSMTextures(size: CGSize){
        RSMposition = buildTexture(pixelFormat: .rgba16Float, size: size, label: "RSM Position")
        RSMnormal = buildTexture(pixelFormat: .rgba16Float, size: size, label: "RSM Normal")
        RSMflux = buildTexture(pixelFormat: .rgba16Float, size: size, label: "RSM Flux")
    }
    
    func buildPostProcessTextures(size: CGSize){
        postProcessTexture1 = buildTexture(pixelFormat: .bgra8Unorm, size: size, label: "postprocess tex1")
        postProcessTexture2 = buildTexture(pixelFormat: .bgra8Unorm, size: size, label: "postprocess tex2")
    }
    
    func buildGBufferRenderPassDescriptor(size: CGSize){
        gBufferRenderPassDescriptor = MTLRenderPassDescriptor()
        buildGbufferTextures(size: size)
        buildPostProcessTextures(size: size)
        let textures: [MTLTexture] = [albedoTexture!,
                                      normalTexture!,
                                      positionTexture!,
                                      materialPackTexture!]
        for (position, texture) in textures.enumerated(){
            gBufferRenderPassDescriptor?.setUpColorAttachment(position: position, texture: texture)
        }
        gBufferRenderPassDescriptor?.setUpDepthAttachment(texture: depthTexture!)
        
    }
    func buildConeTracingPassDescriptor(size: CGSize, zig: Bool){
        coneTracingPassDescriptor = MTLRenderPassDescriptor()
        if(zig)
        {
            coneTracingPassDescriptor?.setUpColorAttachment(position: 0, texture: postProcessTexture1!)
        }
        else
        {
            coneTracingPassDescriptor?.setUpColorAttachment(position: 0, texture: postProcessTexture2!)
        }
    }
    func buildDepthBlitDescriptor(size: CGSize)
    {
        depthBlitPassDescriptor = MTLRenderPassDescriptor()
        depthBlitPassDescriptor?.setUpColorAttachment(position: 0, texture: HizTexture!)
    }
    func buildFXAAPassDescriptor(size: CGSize, zig: Bool){
        fxaaRenderPassDescriptor = MTLRenderPassDescriptor()
        if(zig)
        {
            fxaaRenderPassDescriptor?.setUpColorAttachment(position: 0, texture: postProcessTexture1!)
        }
        else
        {
            fxaaRenderPassDescriptor?.setUpColorAttachment(position: 0, texture: postProcessTexture2!)
        }
        
    }
    func buildScreenRTRenderPassDescriptor(size: CGSize){
        screenRTRenderPassDescriptor = MTLRenderPassDescriptor()
        screenRTRenderPassDescriptor?.setUpColorAttachment(position: 0, texture: lightTexutre!)
    }
    
    func buildCompositionRenderPassDescriptor(){
        compositionRenderPassDescriptor = MTLRenderPassDescriptor()
    
        
        let textures: [MTLTexture] = [directLightTexture!,
                                      diffuseTexture!]
        for (position, texture) in textures.enumerated(){
            compositionRenderPassDescriptor?.setUpColorAttachment(position: position, texture: texture)
        }
    }
    
    func screenSpaceRayTracing(renderEncoder: MTLRenderCommandEncoder)
    {
        renderEncoder.pushDebugGroup("screen Space Ray Tracing")
        renderEncoder.label = "screen Space Ray Tracing"
        renderEncoder.setRenderPipelineState(screenRTPipelineState)
        renderEncoder.setVertexBuffer(quadVerticesBuffer,
                                      offset: 0, index: 0)
        renderEncoder.setVertexBuffer(quadTexCoordsBuffer,
                                      offset: 0, index: 1)
        // Send the G-buffer textures and lights array to the fragment shader.
        renderEncoder.setFragmentTexture(albedoTexture, index: 0)
        renderEncoder.setFragmentTexture(normalTexture, index: 1)
        renderEncoder.setFragmentTexture(positionTexture, index: 2)
          renderEncoder.setFragmentTexture(materialPackTexture, index: 3)
          renderEncoder.setFragmentTexture(HizTexture, index: 4)
        renderEncoder.setFragmentBytes(&scene!.uniforms, length: MemoryLayout<Uniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
        renderEncoder.setFragmentBytes(&m_ssrParam, length: MemoryLayout<ssrParam>.stride, index: 0)
        
        // Draw the quad
        renderEncoder.drawPrimitives(type: .triangle,
                                     vertexStart: 0,
                                     vertexCount: quadVertices.count)
        renderEncoder.endEncoding()
        renderEncoder.popDebugGroup()
        
    }
    
    func generateMipMaps(commandBuffer: MTLCommandBuffer, texture: MTLTexture)
    {
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        blitEncoder?.generateMipmaps(for: texture)
        blitEncoder?.endEncoding()
    }
    
    func minPoolingDepth(computeEncoder: MTLComputeCommandEncoder)
    {
        computeEncoder.setComputePipelineState(minPoolingPipelineState)
        for level in 1...HizTexture!.mipmapLevelCount - 1
        {
            let source = HizTexture!.makeTextureView(pixelFormat: HizTexture!.pixelFormat, textureType: HizTexture!.textureType, levels: level - 1..<level, slices: 0..<1)!
            let dst = HizTexture!.makeTextureView(pixelFormat: HizTexture!.pixelFormat, textureType: HizTexture!.textureType, levels: level..<level + 1, slices: 0..<1)!
            computeEncoder.setTexture(source, index: 0)
            computeEncoder.setTexture(dst, index: 1)
            let width = minPoolingPipelineState.threadExecutionWidth
            let height = minPoolingPipelineState.maxTotalThreadsPerThreadgroup / width
            let threadsPerGroup = MTLSizeMake(width, height, 1)
            let threadsPerGrid = MTLSizeMake(Int(dst.width) , Int(dst.height), 1)
            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        }
       
       
        computeEncoder.endEncoding()
    }
    
    func coneTracing(renderEncoder: MTLRenderCommandEncoder)
    {
        renderEncoder.pushDebugGroup("cone tracing")
        renderEncoder.label = "cone tracing"
        renderEncoder.setRenderPipelineState(coneTracingPipelineState)
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
          renderEncoder.setFragmentTexture(lightTexutre, index: 5)
        renderEncoder.setFragmentTexture(diffuseTexture, index: 6)
        renderEncoder.setFragmentTexture(directLightTexture, index: 7)
        renderEncoder.setFragmentBytes(&m_ssrParam, length: MemoryLayout<ssrParam>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle,
                                     vertexStart: 0,
                                     vertexCount: quadVertices.count)
        renderEncoder.endEncoding()
        renderEncoder.popDebugGroup()
          
        
    }
    
    func fxaaPass(renderEncoder: MTLRenderCommandEncoder)
    {
        renderEncoder.pushDebugGroup("fxaa")
        renderEncoder.label = "FXAA pass"
        renderEncoder.setRenderPipelineState(fxaaPSO)
        renderEncoder.setVertexBuffer(quadVerticesBuffer,
                                      offset: 0, index: 0)
        renderEncoder.setVertexBuffer(quadTexCoordsBuffer,
                                      offset: 0, index: 1)
        // Send the G-buffer textures and lights array to the fragment shader.
        renderEncoder.setFragmentTexture(postProcessTexture1, index: 0)
        renderEncoder.drawPrimitives(type: .triangle,
                                     vertexStart: 0,
                                     vertexCount: quadVertices.count)
        renderEncoder.endEncoding()
        renderEncoder.popDebugGroup()
    }
    func endPostProcessing(renderEncoder: MTLRenderCommandEncoder)
    {
        renderEncoder.pushDebugGroup("end Post")
        renderEncoder.label = "end PostProcessing"
        renderEncoder.setRenderPipelineState(endPostPSO)
        renderEncoder.setVertexBuffer(quadVerticesBuffer,
                                      offset: 0, index: 0)
        renderEncoder.setVertexBuffer(quadTexCoordsBuffer,
                                      offset: 0, index: 1)
        // Send the G-buffer textures and lights array to the fragment shader.
        renderEncoder.setFragmentTexture(postProcessTexture2, index: 0)
        renderEncoder.drawPrimitives(type: .triangle,
                                     vertexStart: 0,
                                     vertexCount: quadVertices.count)
        
        renderEncoder.endEncoding()
        renderEncoder.popDebugGroup()
    }
    
    func depthBlit(renderEncoder: MTLRenderCommandEncoder)
    {
        renderEncoder.pushDebugGroup("depth blit")
        renderEncoder.label = "depth blit"
        renderEncoder.setRenderPipelineState(depthBlitPSO)
        renderEncoder.setVertexBuffer(quadVerticesBuffer,
                                      offset: 0, index: 0)
        renderEncoder.setVertexBuffer(quadTexCoordsBuffer,
                                      offset: 0, index: 1)
        // Send the G-buffer textures and lights array to the fragment shader.
        renderEncoder.setFragmentTexture(depthTexture, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangle,
                                     vertexStart: 0,
                                     vertexCount: quadVertices.count)
        renderEncoder.endEncoding()
        renderEncoder.popDebugGroup()
    }
    func renderCompositionPass(
        renderEncoder: MTLRenderCommandEncoder, skybox:Skybox?) {
      renderEncoder.pushDebugGroup("Composition pass")
      renderEncoder.label = "Composition encoder"
      renderEncoder.setRenderPipelineState(compositionPipelineState)
//        renderEncoder.setDepthStencilState(depthStencilState)
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
        renderEncoder.setFragmentTexture(lightTexutre, index: 5)
        
        if(enableRSM)
        {
            renderEncoder.setFragmentBuffer(samplesBuffer, offset: 0, index: Int(BufferIndexSamples.rawValue))
            renderEncoder.setFragmentTexture(RSMposition, index: 6)
            renderEncoder.setFragmentTexture(RSMnormal, index: 7)
            renderEncoder.setFragmentTexture(RSMflux, index: 8)
        }
        
        var skbool = false
        
        //update skybox
        if let skb = skybox{
            skb.update(renderEncoder: renderEncoder)
            skbool = true
           
        }
        renderEncoder.setFragmentBytes(&skbool, length: MemoryLayout<Bool>.size, index: Int(BufferIndexHasSkybox.rawValue))
       

        renderEncoder.setFragmentBytes(&scene!.lights,
                                       length: MemoryLayout<Light_Uniform>.stride * scene!.lightCount,
                                       index: Int(BufferIndexLights.rawValue))
        renderEncoder.setFragmentBytes(&scene!.fragmentUniforms,
        length: MemoryLayout<FragmentUniforms>.stride,
        index: Int(BufferIndexFragmentUniforms.rawValue))
        
        renderEncoder.setFragmentBytes(&scene!.uniforms,
        length: MemoryLayout<Uniforms>.stride,
        index: Int(BufferIndexUniforms.rawValue))
        
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
    
    func buildDepthBlitPSO(vertexFunctionName: String = "compositionVert",
                                       fragmentFunctionName: String = "depthBlitFrag")
    {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = .r32Float
        descriptor.label = "depth blit"
        descriptor.vertexFunction = Renderer.library.makeFunction(
          name: vertexFunctionName)
        descriptor.fragmentFunction = Renderer.library.makeFunction(
          name: fragmentFunctionName)
        do {
          depthBlitPSO =
            try Renderer.device.makeRenderPipelineState(
                descriptor: descriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
        
    }
    func buildCompositionPipelineState(vertexFunctionName: String = "compositionVert",
                                       fragmentFunctionName: String = "compositionFrag") {
      let descriptor = MTLRenderPipelineDescriptor()
        
        let functionConstants = MTLFunctionConstantValues()
        functionConstants.setConstantValue(&enableRSM, type: .bool, index: 0)
//      if(enableMSAA)
//      {
//        descriptor.sampleCount = 4
//      }
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.colorAttachments[1].pixelFormat = .rgba16Float
//      descriptor.depthAttachmentPixelFormat = .depth32Float
      descriptor.label = "Composition state"
        do{
            descriptor.vertexFunction = Renderer.library.makeFunction(
              name: vertexFunctionName)
            descriptor.fragmentFunction = try Renderer.library.makeFunction(
              name: fragmentFunctionName, constantValues: functionConstants)
        }
        catch {
          fatalError("No Metal function exists")
        }
      do {
        compositionPipelineState =
          try Renderer.device.makeRenderPipelineState(
              descriptor: descriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
    }
    
    func buildScreenRTPipelineState(vertexFunctionName: String = "compositionVert",
                                   fragmentFunctionName: String = "SSRT_fragment")
    {
        let descriptor = MTLRenderPipelineDescriptor()
//        if(enableMSAA)
//        {
//          descriptor.sampleCount = 4
//        }
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.label = "Screen Space Ray tracing"
        descriptor.vertexFunction = Renderer.library.makeFunction(
          name: vertexFunctionName)
        descriptor.fragmentFunction = Renderer.library.makeFunction(
          name: fragmentFunctionName)
        do {
          screenRTPipelineState =
            try Renderer.device.makeRenderPipelineState(
                descriptor: descriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
    }
    
    func buildEndPostPSO(vertexFunctionName: String = "compositionVert",
                                   fragmentFunctionName: String = "endPostFrag")
    {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = Renderer.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.label = "End PostProcessing"
        descriptor.vertexFunction = Renderer.library.makeFunction(
          name: vertexFunctionName)
        descriptor.fragmentFunction = Renderer.library.makeFunction(
          name: fragmentFunctionName)
        do {
          endPostPSO =
            try Renderer.device.makeRenderPipelineState(
                descriptor: descriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
    }
    
    func buildFXAAPSO(vertexFunctionName: String = "compositionVert",
                      fragmentFunctionName: String = "FXAAFrag")
    {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.label = "FXAA"
        descriptor.vertexFunction = Renderer.library.makeFunction(
          name: vertexFunctionName)
        descriptor.fragmentFunction = Renderer.library.makeFunction(
          name: fragmentFunctionName)
        do {
          fxaaPSO =
            try Renderer.device.makeRenderPipelineState(
                descriptor: descriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
        
        
    }
    
    func buildConeTracinglineState(vertexFunctionName: String = "compositionVert",
                                       fragmentFunctionName: String = "ConeTracingFrag") {
      let descriptor = MTLRenderPipelineDescriptor()
      if(enableMSAA)
      {
        descriptor.sampleCount = 4
      }
      descriptor.colorAttachments[0].pixelFormat =
        .bgra8Unorm
      descriptor.label = "Cone Tracing state"
      descriptor.vertexFunction = Renderer.library.makeFunction(
        name: vertexFunctionName)
      descriptor.fragmentFunction = Renderer.library.makeFunction(
        name: fragmentFunctionName)
      do {
        coneTracingPipelineState =
          try Renderer.device.makeRenderPipelineState(
              descriptor: descriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
    }
    
    func buildComputePipelineState(){
        guard let kernelFunction =
                Renderer.library?.makeFunction(name: "minPooling")else{
            fatalError("Tessellation shader function not found")
        }
        do {
          minPoolingPipelineState =
            try  Renderer.device.makeComputePipelineState(function: kernelFunction)
        } catch let error {
          fatalError(error.localizedDescription)
        }
           
        
    }
    

}
    
    extension ssrRenderer: MTKViewDelegate {
      func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.sceneSizeWillChange(to: size)
        buildShadowTexture(size: CGSize(width: 4096.0, height: 4096.0))
        //if (renderType == deferredRendering){
        buildGBufferRenderPassDescriptor(size: size)
        buildScreenRTRenderPassDescriptor(size: size)
        buildConeTracingPassDescriptor(size: size, zig: true)
        buildFXAAPassDescriptor(size: size, zig: false)
        buildDepthBlitDescriptor(size: size)
        m_ssrParam.depthBufferSize.x = Float(size.width)
        m_ssrParam.depthBufferSize.y = Float(size.height)
        let tmp = max(m_ssrParam.depthBufferSize.x, m_ssrParam.depthBufferSize.y)
        m_ssrParam.numMips = ceil(log2(tmp))
        buildCompositionRenderPassDescriptor();
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
        uniform.viewMatrix = float4x4(translation: [0, 0, 7]) * lookAt
            uniform.shadowMatrix = uniform.projectionMatrix * uniform.viewMatrix
            scene.uniforms.shadowMatrix = uniform.shadowMatrix
        for renderable in scene.renderables{
            shadowEncoder.pushDebugGroup(renderable.name)
            renderable.render_shadow(renderEncoder: shadowEncoder, uniforms: uniform)
            shadowEncoder.popDebugGroup()
        }
        
        shadowEncoder.endEncoding()
            
        }
        
        
        
       
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
         
            
            //generate Hi-Z
        //first blit depth texture
        guard let depthBlitEncoder =
                commandBuffer.makeRenderCommandEncoder(descriptor: depthBlitPassDescriptor!)else{
            return
        }
       depthBlit(renderEncoder: depthBlitEncoder)
            
            
            //generateMipMaps(commandBuffer: commandBuffer, texture: HizTexture!)
            minPoolingDepth(computeEncoder: commandBuffer.makeComputeCommandEncoder()!)
            //screen space ray tracing pass
            guard let ssrtEncoder =
                commandBuffer.makeRenderCommandEncoder(descriptor: screenRTRenderPassDescriptor!)else{
                return
            }
           screenSpaceRayTracing(renderEncoder: ssrtEncoder)
        

        
        
            //light pass
        guard let compositionEncoder =
                commandBuffer.makeRenderCommandEncoder(descriptor: compositionRenderPassDescriptor!)else{
            return
        }
        renderCompositionPass(renderEncoder: compositionEncoder, skybox: scene.skybox)
        generateMipMaps(commandBuffer: commandBuffer, texture: diffuseTexture!)
        
            if(enableMSAA)
            {
                view.sampleCount = 4
            }
            
            guard let descriptor = view.currentRenderPassDescriptor else {
                return
            }
           
            guard let coneTracingEncoder =
                    commandBuffer.makeRenderCommandEncoder(descriptor: coneTracingPassDescriptor!)else{
                return
            }
        coneTracing(renderEncoder: coneTracingEncoder)
        
        //fxaa pass
        guard let fxaaEncoder =
                commandBuffer.makeRenderCommandEncoder(descriptor: fxaaRenderPassDescriptor!)else{
            return
        }
        fxaaPass(renderEncoder: fxaaEncoder)
        
        guard let endPostEncoder =
                commandBuffer.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!)else{
            return
        }
        endPostProcessing(renderEncoder: endPostEncoder)
            //update skybox
//            if let skb = scene.skybox{
//                skb.update(renderEncoder: compositionEncoder)
//            }
//            renderCompositionPass(renderEncoder: coneT, skybox: scene.skybox)
        
        
        guard let drawable = view.currentDrawable else {
          return
        }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            
    
        
        
        

        
      }
    }

private extension MTLRenderPassDescriptor{
    func setUpColorAttachment(position: Int, texture: MTLTexture) {
      let attachment: MTLRenderPassColorAttachmentDescriptor =
        colorAttachments[position]
      attachment.texture = texture
      attachment.loadAction = .clear
      attachment.storeAction = .store
        attachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1)
    }
    
    func setUpDepthAttachment(texture: MTLTexture){
        depthAttachment.texture = texture
        depthAttachment.loadAction = .clear
        depthAttachment.storeAction = .store
        depthAttachment.clearDepth  = 1
    }

}


