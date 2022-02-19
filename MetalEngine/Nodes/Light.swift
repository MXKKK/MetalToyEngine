//
//  Light.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

//vector_float3 position;
//vector_float3 color;
//vector_float3 specularColor;
//float intensity;
//vector_float3 attenuation;
//LightType type;
//float coneAngle;
//vector_float3 coneDirection;
//float coneAttenuation;
import Foundation
import MetalKit
class Light : Node{
    var light = buildDefaultLight()
//    var direction: float3 = [0, 0, 0]
//    var diffuse_color: float3 = [0, 0, 0]
//    var specular_color: float3 = [0, 0, 0]
//    var intensity: Float = 1.0
//    var attenuation: float3 = [1, 3, 4]
//    var type: LightType = unused
//    var coneAngle : Float = Float(40).degreesToRadians
//    var coneDirection: float3 = [-2, 0, -1.5]
//    var coneAtenuation: Float = 12
    var isVisible: Bool = false
    let lightPipelineState: MTLRenderPipelineState
    
    init(name: String){
        lightPipelineState = Light.buildLightPipelineState()
        super.init()
        self.name = name
        
    }
    override func update(deltaTime: Float){
        position = light.position
    }
    
}

private extension Light{
    static func buildLightPipelineState() -> MTLRenderPipelineState {
      let library = Renderer.device.makeDefaultLibrary()
      let vertexFunction = library?.makeFunction(name: "vertex_light")
      let fragmentFunction = library?.makeFunction(name: "fragment_light")
      let pipelineDescriptor = MTLRenderPipelineDescriptor()
      pipelineDescriptor.vertexFunction = vertexFunction
      pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.sampleCount = 4
      pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
      let lightPipelineState: MTLRenderPipelineState
      do {
        lightPipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
      return lightPipelineState
    }
    
    static func buildDefaultLight() -> Light_Uniform {
      var light = Light_Uniform()
      light.position = [0, 0, 0]
      light.color = [1, 1, 1]
      light.specularColor = [1, 1, 1]
      light.intensity = 0.6
      light.attenuation = float3(1, 0, 0)
      light.type = Sunlight
      return light
    }
}

extension Light: Renderable{
    func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, fragmentUniforms fragment: FragmentUniforms) {
        if !isVisible{
            return
        }
        switch light.type {
        case Pointlight:
            drawPointLight(renderEncoder: renderEncoder, position: position, color: light.color, uniforms: uniforms)
        case Sunlight:
            drawDirectionalLight(renderEncoder: renderEncoder, direction: position, color: [1, 0, 0], count: 5, uniforms: uniforms)
        case Spotlight:
            drawPointLight(renderEncoder: renderEncoder, position: light.position,
                           color: light.color, uniforms: uniforms)
       
            drawSpotLight(renderEncoder: renderEncoder, position: light.position, direction: light.coneDirection, color: light.color, uniforms: uniforms)
        default:
            return

        }
    }
    
    func render_shadow(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms) {
        return
    }

    func drawPointLight(renderEncoder: MTLRenderCommandEncoder, position: float3, color: float3,
                        uniforms vertex: Uniforms) {
      var vertices = [position]
      let buffer = Renderer.device.makeBuffer(bytes: &vertices,
                                              length: MemoryLayout<float3>.stride * vertices.count,
                                              options: [])
        
      var uniforms = vertex
      uniforms.modelMatrix = float4x4.identity()
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride, index: 1)
      var lightColor = color
      renderEncoder.setFragmentBytes(&lightColor, length: MemoryLayout<float3>.stride, index: 1)
      renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
      renderEncoder.setRenderPipelineState(lightPipelineState)
      renderEncoder.drawPrimitives(type: .point, vertexStart: 0,
                                   vertexCount: vertices.count)
      
    }
    
    func drawDirectionalLight (renderEncoder: MTLRenderCommandEncoder,
                               direction: float3,
                               color: float3, count: Int,
                               uniforms vertex: Uniforms) {
        var uniforms = vertex
      var vertices: [float3] = []
      for i in -count..<count {
        let value = Float(i) * 0.4
        vertices.append(float3(value, 0, value))
        vertices.append(float3(direction.x+value, direction.y, direction.z+value))
      }

      let buffer = Renderer.device.makeBuffer(bytes: &vertices,
                                              length: MemoryLayout<float3>.stride * vertices.count,
                                              options: [])
      uniforms.modelMatrix = float4x4.identity()
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride, index: 1)
      var lightColor = color
      renderEncoder.setFragmentBytes(&lightColor, length: MemoryLayout<float3>.stride, index: 1)
      renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
      renderEncoder.setRenderPipelineState(lightPipelineState)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0,
                                   vertexCount: vertices.count)
      
    }
    
    
    func drawSpotLight(renderEncoder: MTLRenderCommandEncoder, position: float3, direction: float3, color: float3, uniforms vertex: Uniforms) {
      var uniforms = vertex
      var vertices: [float3] = []
      vertices.append(position)
      vertices.append(float3(position.x + direction.x, position.y + direction.y, position.z + direction.z))
      let buffer = Renderer.device.makeBuffer(bytes: &vertices,
                                              length: MemoryLayout<float3>.stride * vertices.count,
                                              options: [])
      uniforms.modelMatrix = float4x4.identity()
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride, index: 1)
      var lightColor = color
      renderEncoder.setFragmentBytes(&lightColor, length: MemoryLayout<float3>.stride, index: 1)
      renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
      renderEncoder.setRenderPipelineState(lightPipelineState)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0,
                                   vertexCount: vertices.count)
    }
    
    

}
