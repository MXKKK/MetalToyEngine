//
//  Particles.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/29.
//

import Foundation
import CoreGraphics
import simd

extension Renderer{
    static func snow(position: float3, xRange: Float, zRange: Float, name:String = "SnowEmitter") -> Emitter{
        let emitter = Emitter()
        
        emitter.particleCount = 100
        emitter.birthRate = 1
        emitter.birthDelay = 20
        
        
        var descriptor = ParticleDescriptor()
        descriptor.position = position
        descriptor.positionXRange = -xRange...xRange
        descriptor.positionYRange = -zRange...zRange
        descriptor.direction =  normalize(float3(0.3, -1, 0))
        descriptor.directionXRange = -0.2 ... 0.2
        descriptor.directionZRange = -0.1 ... 0.1
        descriptor.speedRange =  0.005...0.01
          descriptor.pointSizeRange = 20...30
          descriptor.startScale = 0
          descriptor.startScaleRange = 0.2...1.0
        
        descriptor.life = 500
        descriptor.color = [1,1,1,1]
        emitter.particleDescriptor = descriptor
        emitter.name = name
        return emitter
    }
}
