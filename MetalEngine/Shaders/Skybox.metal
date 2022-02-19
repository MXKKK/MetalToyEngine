//
//  Skybox.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/11/18.
//

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"

struct VertexIn{
    float4 position [[ attribute(0) ]];
};

struct VertexOut{
    float4 position [[ position ]];
    float3 xyw;
    float3 textureCoordinates;
};

struct ComposeOut{
    float4 directLight [[color(0)]];
    float4 diffuse [[color(1)]];
    
};
vertex VertexOut vertexSkybox(const VertexIn in [[stage_in]],
                              constant float4x4 &vp [[buffer(1)]]){
    VertexOut out;
    out.position = (vp * in.position).xyww;
    out.xyw = (vp * in.position).xyw;
    out.textureCoordinates = in.position.xyz;
    return out;
}

half4 fog() {
//  float distance = position.z / position.w;
//  float density = 0.2;
//  float fog = 1.0 - clamp(exp(-density * distance), 0.0, 1.0);
  half4 fogColor = half4(1.0);
//  color = mix(color, fogColor, fog);
  return fogColor;
}


fragment half4
        fragmentSkybox(VertexOut in [[stage_in]],
                       constant bool &fogEnabled [[buffer(BufferIndexFog)]],
                       texturecube<half> cubeTexture
                           [[texture(BufferIndexSkybox)]]) {
  constexpr sampler default_sampler(filter::linear);
  half4 color = cubeTexture.sample(default_sampler,
                                   in.textureCoordinates);
            
  if(fogEnabled == true)
  {
      color = fog();
  }
  return color;
}

fragment ComposeOut
        fragmentSkybox_deffered(VertexOut in [[stage_in]],
                        constant bool &fogEnabled [[buffer(BufferIndexFog)]],
                       texturecube<half> cubeTexture
                           [[texture(BufferIndexSkybox)]],
                       texture2d<float> depthTexture [[texture(4)]]) {
    
  float2 xy = in.xyw.xy / in.xyw.z ;
    xy = xy * 0.5 + 0.5;
    xy.y = 1 - xy.y;
    constexpr sampler default_sampler(filter::nearest);
    if(depthTexture.sample(default_sampler, xy).r < 1.0)
    {
        discard_fragment();
    }
                
    half4 color = cubeTexture.sample(default_sampler,
                                   in.textureCoordinates);
            
    if(fogEnabled == true)
    {
        color = fog();
    }
            ComposeOut out;
            float4 ret(color.r, color.g, color.b, 1.0f);
            out.diffuse = ret;
            out.directLight = ret;
    return out;
}


