//
//  Renderable.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

import Foundation
import MetalKit


protocol Renderable {
    var name: String{ get }
    func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms,
                fragmentUniforms fragment: FragmentUniforms)
    func render_shadow(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms)
    
//    func render_gbuffer(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms,
//                        fragmentUniforms fragment: FragmentUniforms)
}
