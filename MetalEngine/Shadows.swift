//
//  Shadows.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/15.
//

import Foundation
import MetalKit

extension Renderer{
    
    func buildTexture(pixelFormat: MTLPixelFormat, size: CGSize, label: String) -> MTLTexture{
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: Int(size.width), height: Int(size.height), mipmapped: false)
        
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let texture =
                Renderer.device.makeTexture(descriptor: descriptor) else{
            fatalError()
        }
        texture.label = "\(label) texuture"
        return texture
    }
    
    func buildShadowTexture(size: CGSize){
        shadowTexture = buildTexture(pixelFormat: .depth32Float, size: size, label: "Shadow")
        shadowRenderPassDescriptor?.setUpDepthAttachment(texture: shadowTexture!)
    }
    
    func buildRSMTexture(size: CGSize){
        
    }
    
    
}

extension ssrRenderer{
    
    func buildTexture(pixelFormat: MTLPixelFormat, size: CGSize, label: String, mipmapped: Bool = false, enable_write: Bool = false) -> MTLTexture{
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: Int(size.width), height: Int(size.height), mipmapped: mipmapped)
        
        if(enable_write)
        {
            descriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
        }
        else
        {
            descriptor.usage = [.shaderRead, .renderTarget]
        }
        
        descriptor.storageMode = .private
        guard let texture =
                Renderer.device.makeTexture(descriptor: descriptor) else{
            fatalError()
        }
        texture.label = "\(label) texuture"
        return texture
    }
    
    func buildShadowTexture(size: CGSize){
        shadowTexture = buildTexture(pixelFormat: .depth32Float, size: size, label: "Shadow")
        shadowRenderPassDescriptor?.setUpDepthAttachment(texture: shadowTexture!)
    }
    
    
}

private extension MTLRenderPassDescriptor{
    func setUpDepthAttachment(texture: MTLTexture){
        depthAttachment.texture = texture
        depthAttachment.loadAction = .clear
        depthAttachment.storeAction = .store
        depthAttachment.clearDepth  = 1
    }
}

