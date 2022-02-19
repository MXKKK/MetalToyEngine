//
//  Terrains.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/21.
//

import Foundation
import MetalKit
import simd

class Terrains: Node{
    let patches = (horizontal: 5, vertical: 5)
    var patchCount: Int{
        return patches.horizontal * patches.vertical
    }
    
    var edgeFactors: [Float] = [4]
    var insideFactors: [Float] = [4]
    
    let vertices: [float3] = [
      [-1,  0,  1],
      [ 1,  0, -1],
      [-1,  0, -1],
      [-1,  0,  1],
      [ 1,  0, -1],
      [ 1,  0,  1]
    ]
    
    let heightMap: MTLTexture
    let cliffColor: MTLTexture
    let snowColor: MTLTexture
    let grassColor: MTLTexture
    let terrainSlope: MTLTexture
    let normalMap: MTLTexture

    let vertexBuffer: MTLBuffer?
    
    var tessellationPipelineState: MTLComputePipelineState
    var renderPipelineState: MTLRenderPipelineState
    static let maxTessellation = 64
    var terrain : Terrain_Uniform
    
    lazy var tessellationFactorsBuffer: MTLBuffer? = {
        let count = patchCount * (4 + 2)
        let size = count * MemoryLayout<Float>.size / 2
        return Renderer.device.makeBuffer(length: size, options: .storageModePrivate)
    }()
    
    var controlPointsBuffer: MTLBuffer?
    
    init(name: String, size: float2, height: Float)
    {
        self.vertexBuffer = Renderer.device.makeBuffer(bytes: vertices,
                                                       length: MemoryLayout<float3>.stride * vertices.count,
                                                       options: [])
        self.renderPipelineState = Terrains.buildRenderPipelineState()
        self.tessellationPipelineState = Terrains.buildComputePipelineState()
        self.terrain = Terrain_Uniform(size: size, height: height, maxTessellation: UInt32(Terrains.maxTessellation))
        do{
            heightMap = try Terrains.loadTexture(imageName: "mountain")!
            cliffColor = try Terrains.loadTexture(imageName: "cliff-color")!
            grassColor = try Terrains.loadTexture(imageName: "grass-color")!
            snowColor = try Terrains.loadTexture(imageName:  "snow-color")!
        }catch{
            fatalError(error.localizedDescription)
        }
        terrainSlope = Renderer.heightToSlope(source: heightMap)
        normalMap = Renderer.heightToNormal(source: heightMap)
        
        
        
        super.init()
        let controlPoints = createControlPoints(patches: patches,
                                  size: (width: terrain.size.x,
                                         height: terrain.size.y))

        controlPointsBuffer = Renderer.device.makeBuffer(bytes: controlPoints,
                                                         length: MemoryLayout<float3>.stride * controlPoints.count)
    }
    
    func tessellation(computeEncoder: MTLComputeCommandEncoder,uniforms: Uniforms, fragmentUniforms fragment: FragmentUniforms)
    {
        
        computeEncoder.setComputePipelineState(tessellationPipelineState)
        var uniforms = uniforms
        var frag = fragment
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
        computeEncoder.setBytes(&frag, length: MemoryLayout<FragmentUniforms>.stride, index: Int(BufferIndexFragmentUniforms.rawValue))
        computeEncoder.setBytes(&terrain, length: MemoryLayout<Terrain_Uniform>.stride, index: Int(BufferIndexTerrain.rawValue))
        computeEncoder.setBytes(&edgeFactors, length: MemoryLayout<Float>.size * edgeFactors.count, index: 0)
        computeEncoder.setBytes(&insideFactors, length: MemoryLayout<Float>.size * insideFactors.count, index: 1)
        computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 3)
        let width = min(patchCount, tessellationPipelineState.threadExecutionWidth)
        computeEncoder.dispatchThreadgroups(MTLSizeMake(patchCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
        //computeEncoder.endEncoding()
    }
    
}

extension Terrains{
    func createControlPoints(patches: (horizontal: Int, vertical: Int),
                             size: (width: Float, height: Float)) -> [float3] {
      
      var points: [float3] = []
      // per patch width and height
      let width = 1 / Float(patches.horizontal)
      let height = 1 / Float(patches.vertical)
      
      for j in 0..<patches.vertical {
        let row = Float(j)
        for i in 0..<patches.horizontal {
          let column = Float(i)
          let left = width * column
          let bottom = height * row
          let right = width * column + width
          let top = height * row + height
          
          points.append([left, 0, top])
          points.append([right, 0, top])
          points.append([right, 0, bottom])
          points.append([left, 0, bottom])
        }
      }
      // size and convert to Metal coordinates
      // eg. 6 across would be -3 to + 3
      points = points.map {
        [$0.x * size.width - size.width / 2,
         0,
         $0.z * size.height - size.height / 2]
      }
      return points
    }
    
    static func buildRenderPipelineState() -> MTLRenderPipelineState {
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      descriptor.depthAttachmentPixelFormat = .depth32Float

      let vertexFunction = Renderer.library?.makeFunction(name: "vertex_terrains")
      let fragmentFunction = Renderer.library?.makeFunction(name: "fragment_terrains_IBL")
      descriptor.vertexFunction = vertexFunction
      descriptor.fragmentFunction = fragmentFunction
        descriptor.sampleCount = 4
      
      let vertexDescriptor = MTLVertexDescriptor()
      vertexDescriptor.attributes[0].format = .float3
      vertexDescriptor.attributes[0].offset = 0
      vertexDescriptor.attributes[0].bufferIndex = 0
      
      vertexDescriptor.layouts[0].stride = MemoryLayout<float3>.stride
      vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
      descriptor.vertexDescriptor = vertexDescriptor
      
      descriptor.tessellationFactorStepFunction = .perPatch
      descriptor.maxTessellationFactor = maxTessellation
      descriptor.tessellationPartitionMode = .pow2
      
        return try! Renderer.device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    static func buildShadowPipelineState() -> MTLRenderPipelineState {
        let library = Renderer.library
        let vertexFunction: MTLFunction?
        vertexFunction = library?.makeFunction(name: "vertex_terrains_shadow")
       
        var pipelineState: MTLRenderPipelineState
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = nil
        pipelineDescriptor.colorAttachments[0].pixelFormat = .invalid
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<float3>.stride
        vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        do {
          pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
        return pipelineState
    }
    
    static func buildComputePipelineState() -> MTLComputePipelineState{
        guard let kernelFunction =
                Renderer.library?.makeFunction(name: "tessellation_main")else{
            fatalError("Tessellation shader function not found")
        }
        
        return try!
            Renderer.device.makeComputePipelineState(function: kernelFunction)
        
    }
}

extension Terrains: Renderable{
    func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, fragmentUniforms fragment: FragmentUniforms) {
        
        
        renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
        var uniforms = uniforms
        
        
        var fragmentUniforms = fragment
        //fragmentUniforms.tiling = tiling
        renderEncoder.setFragmentBytes(&fragmentUniforms,
                                       length: MemoryLayout<FragmentUniforms>.stride,
                                       index: Int(BufferIndexFragmentUniforms.rawValue))
        uniforms.modelMatrix = worldTransform
        
        uniforms.normalMatrix = uniforms.modelMatrix.upperLeft
        renderEncoder.setVertexBytes(&uniforms,
                                     length: MemoryLayout<Uniforms>.stride,
                                     index: Int(BufferIndexUniforms.rawValue))
        renderEncoder.setVertexTexture(heightMap, index: Int(heightTexture.rawValue))
        renderEncoder.setVertexTexture(terrainSlope, index: Int(slopeTexture.rawValue))
        renderEncoder.setVertexTexture(normalMap, index: Int(NormalTexture.rawValue))
        
        renderEncoder.setFragmentTexture(cliffColor, index: Int(cliffTexture.rawValue))
        renderEncoder.setFragmentTexture(grassColor, index: Int(grassTexture.rawValue))
        renderEncoder.setFragmentTexture(snowColor, index: Int(snowTexture.rawValue))
        
        
        renderEncoder.setVertexBytes(&terrain, length: MemoryLayout<Terrain_Uniform>.stride, index: Int(BufferIndexTerrain.rawValue))
        
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        //renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                                  patchStart: 0, patchCount: patchCount,
                                  patchIndexBuffer: nil,
                                  patchIndexBufferOffset: 0,
                                  instanceCount: 1, baseInstance: 0)

        //renderEncoder.endEncoding()
        
    }
    
    func render_shadow(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms) {
        renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer, offset: 0, instanceStride: 0)
        renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: Int(BufferIndexVertices.rawValue))
        var uniforms = vertex
        uniforms.modelMatrix = worldTransform
        
        uniforms.normalMatrix = uniforms.modelMatrix.upperLeft
        renderEncoder.setVertexBytes(&uniforms,
                                     length: MemoryLayout<Uniforms>.stride,
                                     index: Int(BufferIndexUniforms.rawValue))
        renderEncoder.setVertexTexture(heightMap, index: Int(heightTexture.rawValue))
        renderEncoder.setVertexTexture(terrainSlope, index: Int(slopeTexture.rawValue))
        renderEncoder.setVertexTexture(normalMap, index: Int(NormalTexture.rawValue))
        
        renderEncoder.setFragmentTexture(cliffColor, index: Int(cliffTexture.rawValue))
        renderEncoder.setFragmentTexture(grassColor, index: Int(grassTexture.rawValue))
        renderEncoder.setFragmentTexture(snowColor, index: Int(snowTexture.rawValue))
        
        
        renderEncoder.setVertexBytes(&terrain, length: MemoryLayout<Terrain_Uniform>.stride, index: Int(BufferIndexTerrain.rawValue))
        renderEncoder.setRenderPipelineState(renderPipelineState)
        //renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                                  patchStart: 0, patchCount: patchCount,
                                  patchIndexBuffer: nil,
                                  patchIndexBufferOffset: 0,
                                  instanceCount: 1, baseInstance: 0)

    }
    
    
}

extension Terrains: Texturable {}
