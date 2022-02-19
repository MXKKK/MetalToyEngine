//
//  AnimationClip.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/12.
//

import MetalKit

class AnimationClip{
    let name: String
    var jointAnimation: [String: Animation?] = [:]
    var duration: Float = 0
    var speed: Float = 1
    
    init(name: String) {
      self.name = name
    }
    
    func getPose(at: Float, jointPath: String) -> float4x4?{
        guard
            let jointAnimation = jointAnimation[jointPath] ?? nil
        else { return nil}
        
        let time = at * speed
        let rotation =
          jointAnimation.getRotation(at: time) ?? simd_quatf()
        let translation =
          jointAnimation.getTranslation(at: time) ?? float3(repeating: 0)
        let scale =
          jointAnimation.getScales(at: time) ?? float3(repeating: 1)
        let pose = float4x4(translation: translation) * float4x4(rotation) * float4x4(scaling: scale)
        return pose
    }
}
