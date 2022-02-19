//
//  endPost.metal
//  MetalEngine
//
//  Created by 马西开 on 2022/1/24.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut{
    float4 position [[position]];
    float2 texCoords;
};


fragment float4 endPostFrag(VertexOut in [[stage_in]],
                                texture2d<float> inputTexture [[texture(0)]]
                                )
{
    constexpr sampler s(filter::nearest);
    return inputTexture.sample(s, in.texCoords);
    
}

