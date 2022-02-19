//
//  Mesh.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/12.
//

import MetalKit

struct Mesh {
  let mtkMesh: MTKMesh
  let submeshes: [Submesh]
  let transform: TransformComponent?
  let skeleton: Skeleton?

  init(mdlMesh: MDLMesh, mtkMesh: MTKMesh,
       startTime: TimeInterval,
       endTime: TimeInterval,
       shadowTypes: Int,
       renderType: Int,
       enableMSAA: Bool,
       enableRSM: Bool = false,
       vertexFunctionName: String,
       fragmentFunctionName: String) {
    // load skeleton
    let skeleton =
      Skeleton(animationBindComponent:
        (mdlMesh.componentConforming(to: MDLComponent.self)
          as? MDLAnimationBindComponent))
    self.skeleton = skeleton

    // load submeshes
    self.mtkMesh = mtkMesh
    submeshes = zip(mdlMesh.submeshes!, mtkMesh.submeshes).map { mesh in
      Submesh(mdlSubmesh: mesh.0 as! MDLSubmesh,
              mtkSubmesh: mesh.1,
              hasSkeleton: skeleton != nil,
              shadowTypes: shadowTypes,
              renderType: renderType,
              enableMSAA: enableMSAA,
              vertexFunctionName: vertexFunctionName,
              fragmentFunctionName: fragmentFunctionName,
              enableRSM: enableRSM)
      
    }
    
    if let mdlMeshTransform = mdlMesh.transform {
      transform = TransformComponent(transform: mdlMeshTransform,
                                     object: mdlMesh,
                                     startTime: startTime,
                                     endTime: endTime)
    } else {
      transform = nil
    }
  }
}
