//
//  HiZ.metal
//  MetalEngine
//
//  Created by 马西开 on 2022/1/26.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut{
    float4 position [[position]];
    float2 texCoords;
};


fragment float depthBlitFrag(VertexOut in [[stage_in]],
                             texture2d<float> inputTexture [[texture(0)]]
                             )
{
    constexpr sampler s(filter::linear);
    return inputTexture.sample(s, in.texCoords).r;
}

kernel void
minPooling(    texture2d<float, access::read> source [[texture(0)]],
               texture2d<float, access::write> dest [[texture(1)]],
               uint2 input_id [[thread_position_in_grid ]]){
    
    uint2 id = input_id * uint2(2, 2);

//    unsigned int h = source.get_height();
//    unsigned int w = source.get_width();
//    if(input_id.x == 0 && input_id.y == 0)
//        dest.write(1.0, input_id);
//    else
//        dest.write(0.0, input_id);
//    return;

    float min_val = source.read(id).r;
    //if(id.y + 1 < w)
        min_val = min(min_val, source.read(id + uint2(1,0)).r);
    //if(id.x + 1 < h)
        min_val = min(min_val, source.read(id + uint2(0,1)).r);
    //if(id.x + 1 < h && id.y + 1 < w)
        min_val = min(min_val, source.read(id + uint2(1,1)).r);
    
    dest.write(min_val,input_id);


}
