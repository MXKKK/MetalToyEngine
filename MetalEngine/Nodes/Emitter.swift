//
//  Emitter.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/26.
//

import Foundation
import MetalKit

struct Particle{
    var startposition: float3
    var position: float3
    var direction: float3
    var speed: Float
    var color: float4
    var age: Float
    var life: Float
    var size: Float
    var scale: Float = 1.0
    var startScale: Float = 1.0
    var endScale: Float = 1.0
}

struct ParticleDescriptor{
    var position: float3 = [0, 0, 0]
    var positionXRange: ClosedRange<Float> = 0...0
    var positionYRange: ClosedRange<Float> = 0...0
    var positionZRange: ClosedRange<Float> = 0...0
    var direction: float3 = [0, 0, 0]
    var directionXRange: ClosedRange<Float> = 0...0
    var directionYRange: ClosedRange<Float> = 0...0
    var directionZRange: ClosedRange<Float> = 0...0
    
    var speed: Float = 0.0001
    var speedRange: ClosedRange<Float> = 0...0
    var pointSize: Float = 80
    var pointSizeRange: ClosedRange<Float> = 0...0
    var startScale: Float = 0
    var startScaleRange: ClosedRange<Float> = 1...1
    var endScale: Float = 0
    var endScaleRange: ClosedRange<Float>?
    var life: Float = 0
    var lifeRange: ClosedRange<Float> = 1...1
    var color: float4 = [0, 0, 0, 1]
    
    
}

class Emitter: Node{
    var currentParticles = 0
    var particleCount: Int = 0{
        didSet{
            let bufferSize = MemoryLayout<Particle>.stride * particleCount
            particleBuffer = Renderer.device.makeBuffer(length: bufferSize)!
        }
    }
    init(enableMSAA: Bool = true,
         vertexFunctionName: String = "vertex_particle",
         fragmentFunctionName: String = "fragment_particle")
    {
        computePipelineState = Emitter.buildComputePipelineState()
        renderPipelineState = Emitter.makePipelineState(enableMSAA: enableMSAA, vertexFunctionName: vertexFunctionName, fragmentFunctionName: fragmentFunctionName)
    }
    var birthRate = 0
    var birthDelay = 0{
        didSet{
            birthTimer = birthDelay
        }
    }
    private var birthTimer = 0
    
    var particleTexture: MTLTexture!
    var particleBuffer: MTLBuffer?
    var computePipelineState: MTLComputePipelineState
    var renderPipelineState: MTLRenderPipelineState
    
    var particleDescriptor: ParticleDescriptor?
    func emit(){
        if currentParticles >= particleCount{
            return
        }
        guard let particleBuffer = particleBuffer,
          let pd = particleDescriptor else {
          return
        }
        birthTimer += 1
        if birthTimer < birthDelay{
            return
        }
        birthTimer = 0
        var pointer = particleBuffer.contents().bindMemory(to: Particle.self,
                                                           capacity: particleCount)
        pointer = pointer.advanced(by: currentParticles)
        for _ in 0..<birthRate{
            let positionX = pd.position.x + .random(in: pd.positionXRange)
            let positionY = pd.position.y + .random(in: pd.positionYRange)
            let positionZ = pd.position.z + .random(in: pd.positionZRange)
            pointer.pointee.position = [positionX, positionY, positionZ]
            pointer.pointee.startposition = pointer.pointee.position
            pointer.pointee.size = pd.pointSize + .random(in:pd.pointSizeRange)
            pointer.pointee.direction = normalize(pd.direction + float3(.random(in: pd.directionXRange), .random(in: pd.directionYRange), .random(in: pd.directionZRange)))
            pointer.pointee.speed = pd.speed + .random(in: pd.speedRange)
            pointer.pointee.scale = pd.startScale + .random(in: pd.startScaleRange)
            pointer.pointee.startScale = pointer.pointee.scale
            if let range = pd.endScaleRange {
              pointer.pointee.endScale = pd.endScale + .random(in: range)
            } else {
              pointer.pointee.endScale = pointer.pointee.startScale
            }
            
            pointer.pointee.age = 0
            pointer.pointee.life = pd.life + .random(in: pd.lifeRange)
            pointer.pointee.color = pd.color
            pointer = pointer.advanced(by: 1)
          }
          currentParticles += birthRate
        }
    
    func updateParticles(computeEncoder: MTLComputeCommandEncoder,uniforms: Uniforms, fragmentUniforms fragment: FragmentUniforms)
    {
        computeEncoder.setComputePipelineState(computePipelineState)
        let width = computePipelineState.threadExecutionWidth
        let threadsPerGroup = MTLSizeMake(width, 1, 1)
        let threadsPerGrid = MTLSizeMake(particleCount, 1, 1)
        computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        
    }
    
    
    
    
}
extension Emitter{
    static func buildComputePipelineState() -> MTLComputePipelineState
    {
        guard let kernelFunction =
                Renderer.library?.makeFunction(name: "compute_particles")else{
            fatalError("Tessellation shader function not found")
        }
        
        return try!
            Renderer.device.makeComputePipelineState(function: kernelFunction)
    }
    
    static func makePipelineState(enableMSAA: Bool,
                                  vertexFunctionName: String,
                                  fragmentFunctionName: String)
      -> MTLRenderPipelineState {
      
      let library = Renderer.library
        let vertexFunction: MTLFunction?
        let fragmentFunction: MTLFunction?

       
        vertexFunction = library?.makeFunction(name: vertexFunctionName)
        fragmentFunction =  library?.makeFunction(name: fragmentFunctionName)
    
      var pipelineState: MTLRenderPipelineState
      let pipelineDescriptor = MTLRenderPipelineDescriptor()
      pipelineDescriptor.vertexFunction = vertexFunction
      pipelineDescriptor.fragmentFunction = fragmentFunction
      
     
      pipelineDescriptor.colorAttachments[0].pixelFormat = Renderer.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
//      if(enableMSAA)
//      {
//          pipelineDescriptor.sampleCount = 4
//      }
      do {
        pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
      return pipelineState
    }
}

extension Emitter: Texturable {}

extension Emitter: Renderable {
    func render_shadow(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms) {
        return
    }
    
    func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, fragmentUniforms fragment: FragmentUniforms) {
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: Int(BufferIndexParticles.rawValue))
        renderEncoder.setVertexBytes(&position, length: MemoryLayout<float3>.stride, index: 0)
        var uni = uniforms
        
        var frag = fragment
        uni.modelMatrix = worldTransform
        uni.normalMatrix = uniforms.modelMatrix.upperLeft
        renderEncoder.setVertexBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
        renderEncoder.setVertexBytes(&frag, length: MemoryLayout<FragmentUniforms>.stride, index: Int(BufferIndexFragmentUniforms.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1, instanceCount: currentParticles)
        
    }
}


