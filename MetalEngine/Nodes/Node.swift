//
//  Node.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

import Foundation
import MetalKit

class Node{
    var name: String = "untitled"
    var position: float3 = [0, 0, 0]
    var rotation: float3 = [0, 0, 0]{
        didSet{
            let rotationMatrix = float4x4(rotation: rotation)
            quaternion = simd_quatf(rotationMatrix)
        }
    }
    var quaternion = simd_quatf()
    var scale: float3 = [1, 1, 1]
    
    var modelMatrix: float4x4{
        let translateMatrix = float4x4(translation: position)
        let rotateMatrix = float4x4(quaternion)
        let scaleMatrix = float4x4(scaling: scale)
        return translateMatrix * rotateMatrix * scaleMatrix
    }
    
    var boundingBox = MDLAxisAlignedBoundingBox()
    var size: float3{
        return boundingBox.maxBounds - boundingBox.minBounds
    }
    
    var parent: Node?
    var children: [Node] = []
    
    func update(deltaTime: Float){
        
    }
    
    final func add(childNode: Node){
        children.append(childNode)
        childNode.parent = self
    }
    
    
    final func remove(childNode: Node){
        // mount all the childs of the childNode to be deleted under the current node
        for child in childNode.children{
            child.parent = self
            children.append(child)
        }
        
        //delete the childNode
        childNode.children = []
        guard let index = (children.firstIndex {
          $0 === childNode
        }) else { return }
        children.remove(at: index)
        childNode.parent = nil
    }
    
    final func numChildren() -> Int
    {
        return children.count
    }
    
    final func getChildren(index: Int) -> Node{
        return children[index]
    }
    
    final func getChildren(Name: String) -> Node?{
        guard let index = (children.firstIndex {
            $0.name == Name
        })else {return nil}
        return getChildren(index: index)
        
    }
    
    var worldTransform: float4x4 {
        if let parent = parent{
            return parent.worldTransform * self.modelMatrix
        }
        return modelMatrix
    }
    
    var forwardVector: float3 {
        return normalize([sin(rotation.y), 0, cos(rotation.y)])
    }
    
    var rightVector: float3 {
      return [forwardVector.z, forwardVector.y, -forwardVector.x]
    }
}
