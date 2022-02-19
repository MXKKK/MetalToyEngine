//
//  Submesh.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

import MetalKit

class Submesh {
  var mtkSubmesh: MTKSubmesh
  
  struct Textures {
    let baseColor: MTLTexture?
    let normal: MTLTexture?
    let roughness: MTLTexture?
    let metallic: MTLTexture?
    let ao: MTLTexture?
  }
  
  let textures: Textures
  let material: Material
  let pipelineState: MTLRenderPipelineState
    let shadowPipelineState: MTLRenderPipelineState
    
  
    init(mdlSubmesh: MDLSubmesh, mtkSubmesh: MTKSubmesh, hasSkeleton: Bool, shadowTypes: Int, renderType: Int,
         enableMSAA: Bool,vertexFunctionName: String,
         fragmentFunctionName: String,
         enableRSM: Bool = false) {
    var enableMSAAv = enableMSAA
    if(renderType == deferredRendering.rawValue)
    {
        enableMSAAv = false
    }
    self.mtkSubmesh = mtkSubmesh
    textures = Textures(material: mdlSubmesh.material)
    material = Material(material: mdlSubmesh.material)
    if(renderType == forwardRendering.rawValue)
    {
        pipelineState =
          Submesh.makePipelineState(textures: textures,
                                    hasSkeleton: hasSkeleton,
                                    shadowTypes: shadowTypes,
                                    enableMSAA: enableMSAAv,
                                    vertexFunctionName: vertexFunctionName,
                                    fragmentFunctionName: fragmentFunctionName)
    }
    else
    {
        pipelineState =
            Submesh.makeGbufferPipelineState(textures: textures, hasSkeleton: hasSkeleton, enableMSAA: enableMSAAv, shadowTypes: shadowTypes)
    }
        
    if(enableRSM)
    {
        shadowPipelineState = Submesh.makeRSMShadowPipelineState(hasSkeleton: hasSkeleton, textures: textures)
    }
    else
    {
        shadowPipelineState = Submesh.makeShadowPipelineState()
    }
        
    
  }
}

// Pipeline state
private extension Submesh {
    static func makeFunctionConstants(textures: Textures, shadowTypes: Int)
    -> MTLFunctionConstantValues {
      let functionConstants = MTLFunctionConstantValues()
      var property = textures.baseColor != nil
      functionConstants.setConstantValue(&property, type: .bool, index: 0)
      property = textures.normal != nil
      functionConstants.setConstantValue(&property, type: .bool, index: 1)
      property = textures.roughness != nil
      functionConstants.setConstantValue(&property, type: .bool, index: 2)
      property = textures.metallic != nil
      functionConstants.setConstantValue(&property, type: .bool, index: 3)
      property = textures.ao != nil
      functionConstants.setConstantValue(&property, type: .bool, index: 4)
      var sType = shadowTypes
      functionConstants.setConstantValue(&sType, type: .int, index: 5)
      return functionConstants
  }
  
  static func makeVertexFunctionConstants(hasSkeleton: Bool) -> MTLFunctionConstantValues {
    let functionConstants = MTLFunctionConstantValues()
    var addSkeleton = hasSkeleton
    functionConstants.setConstantValue(&addSkeleton, type: .bool, index: 6)
    return functionConstants
  }
  
  static func makePipelineState(textures: Textures,
                                hasSkeleton: Bool,
                                shadowTypes: Int,
                                enableMSAA: Bool,
                                vertexFunctionName: String,
                                fragmentFunctionName: String)
    -> MTLRenderPipelineState {
    let functionConstants = makeFunctionConstants(textures: textures, shadowTypes: shadowTypes)
    
    let library = Renderer.library
      let vertexFunction: MTLFunction?
      let fragmentFunction: MTLFunction?
    do {
      let constantValues =
        makeVertexFunctionConstants(hasSkeleton: hasSkeleton)
      vertexFunction =
        try library?.makeFunction(name: vertexFunctionName,
                                  constantValues: constantValues)
      fragmentFunction = try library?.makeFunction(name: fragmentFunctionName,
                                                   constantValues: functionConstants)
    } catch {
      fatalError("No Metal function exists")
    }
    
    var pipelineState: MTLRenderPipelineState
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    
    let vertexDescriptor = Model.vertexDescriptor
    pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
    pipelineDescriptor.colorAttachments[0].pixelFormat = Renderer.colorPixelFormat
    pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
    if(enableMSAA)
    {
        pipelineDescriptor.sampleCount = 4
    }
    do {
      pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    } catch let error {
      fatalError(error.localizedDescription)
    }
    return pipelineState
  }
    
    static func makeGbufferPipelineState(textures: Textures,
                                         hasSkeleton: Bool,
                                         enableMSAA: Bool,
                                         shadowTypes: Int) -> MTLRenderPipelineState{
        let functionConstants = makeFunctionConstants(textures: textures, shadowTypes: shadowTypes)
        let library = Renderer.library
        let vertexFunction: MTLFunction?
        let fragmentFunction: MTLFunction?
      do {
        let constantValues =
          makeVertexFunctionConstants(hasSkeleton: hasSkeleton)
//        vertexFunction =
//          try library?.makeFunction(name: "vertex_main",
//                                    constantValues: constantValues)
//        fragmentFunction = try library?.makeFunction(name: "gBufferFragment",
//                                                     constantValues: functionConstants)
//        
        vertexFunction =
          try library?.makeFunction(name: "vertex_gbuffer_ssr",
                                    constantValues: constantValues)
        fragmentFunction = try library?.makeFunction(name: "fragment_gbuffer_ssr",
                                                     constantValues: functionConstants)
      } catch {
        fatalError("No Metal function exists")
      }
      
      var pipelineState: MTLRenderPipelineState
      let pipelineDescriptor = MTLRenderPipelineDescriptor()
      pipelineDescriptor.vertexFunction = vertexFunction
      pipelineDescriptor.fragmentFunction = fragmentFunction
        if(enableMSAA)
        {
            pipelineDescriptor.sampleCount = 4
        }
      
      let vertexDescriptor = Model.vertexDescriptor
      pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[1].pixelFormat = .rgba16Float
        pipelineDescriptor.colorAttachments[2].pixelFormat = .rgba16Float
        pipelineDescriptor.colorAttachments[3].pixelFormat = .rgba16Float
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.label = "GBuffer state"
      do {
        pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
      return pipelineState
    }
    
    static func makeShadowPipelineState() -> MTLRenderPipelineState{
        let library = Renderer.library
        let vertexFunction: MTLFunction?
        vertexFunction = library?.makeFunction(name: "vertex_depth")
       
        var pipelineState: MTLRenderPipelineState
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = nil
        pipelineDescriptor.colorAttachments[0].pixelFormat = .invalid
        
        let vertexDescriptor = Model.vertexDescriptor
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        do {
          pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
        return pipelineState
    }
    
    static func makeRSMShadowPipelineState(hasSkeleton: Bool, textures: Textures) -> MTLRenderPipelineState{
        let library = Renderer.library
        let vertexFunction: MTLFunction?
        let fragmentFunction: MTLFunction?
        let functionConstants = makeFunctionConstants(textures: textures, shadowTypes: Int(NoShadow.rawValue))
        
        
        do {
          let constantValues =
            makeVertexFunctionConstants(hasSkeleton: hasSkeleton)
          vertexFunction =
            try library?.makeFunction(name: "RSM_VS",
                                      constantValues: constantValues)
          fragmentFunction = try library?.makeFunction(name: "RSM_PS",constantValues: functionConstants)
        } catch {
          fatalError("No Metal function exists")
        }
        
        var pipelineState: MTLRenderPipelineState
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float //Position
        pipelineDescriptor.colorAttachments[1].pixelFormat = .rgba16Float //Normal
        pipelineDescriptor.colorAttachments[2].pixelFormat = .rgba16Float //Flux
        
        let vertexDescriptor = Model.vertexDescriptor
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        do {
          pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
          fatalError(error.localizedDescription)
        }
        return pipelineState
        
    }
}


extension Submesh: Texturable {}

private extension Submesh.Textures {
  init(material: MDLMaterial?) {
    func property(with semantic: MDLMaterialSemantic) -> MTLTexture? {
      guard let property = material?.property(with: semantic),
        property.type == .string,
        let filename = property.stringValue,
        let texture = try? Submesh.loadTexture(imageName: filename)
        else {
          if let property = material?.property(with: semantic),
            property.type == .texture,
            let mdlTexture = property.textureSamplerValue?.texture {
            return try? Submesh.loadTexture(texture: mdlTexture)
          }
          return nil
      }
      return texture
    }
    baseColor = property(with: MDLMaterialSemantic.baseColor)
    normal = property(with: .tangentSpaceNormal)
    roughness = property(with: .roughness)
    metallic = property(with: .metallic)
    ao = property(with: .ambientOcclusion)
    
  }
}

private extension Material {
  init(material: MDLMaterial?) {
    self.init()
    if let baseColor = material?.property(with: .baseColor),
      baseColor.type == .float3 {
      self.baseColor = baseColor.float3Value
    }
    if let specular = material?.property(with: .specular),
      specular.type == .float3 {
      self.specularColor = specular.float3Value
    }
    if let shininess = material?.property(with: .specularExponent),
      shininess.type == .float {
      self.shininess = shininess.floatValue
    }
    if let roughness = material?.property(with: .roughness),
      roughness.type == .float3 {
      self.roughness = roughness.floatValue
    }
  }
}

