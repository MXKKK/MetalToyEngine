//
//  Deffered.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/11/17.
//

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"

constant bool hasColorTexture [[function_constant(0)]];
constant bool hasNormalTexture [[function_constant(1)]];
constant bool hasRoughnessTexture [[function_constant(2)]];
constant bool hasMetallicTexture [[function_constant(3)]];
constant bool hasAOTexture [[function_constant(4)]];
constant int  shadowTypes [[function_constant(5)]];

struct VertexOut {
  float4 position [[ position ]];
  float3 worldPosition;
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
  float2 uv;
    float4 shadowPosition;
};


struct GbufferOut{
    float4 albedo [[color(0)]];
    float4 normal [[color(1)]];
    float4 position [[color(2)]];
    float4 materialPack [[color(3)]];
};

fragment GbufferOut gBufferFragment(VertexOut in[[stage_in]],
                                    constant Material &material [[buffer(BufferIndexMaterials)]],
                                    sampler textureSampler [[sampler(0)]],
                                    constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
                                    texture2d<float> baseColorTexture [[texture(0), function_constant(hasColorTexture)]],
                                    texture2d<float> normalTexture [[texture(1), function_constant(hasNormalTexture)]],
                                    texture2d<float> roughnessTexture [[texture(2), function_constant(hasRoughnessTexture)]],
                                    texture2d<float> metallicTexture [[texture(3), function_constant(hasMetallicTexture)]],
                                    texture2d<float> aoTexture [[texture(4), function_constant(hasAOTexture)]],
                                    depth2d<float> shadowTexture [[texture(5), function_constant(shadowTypes)]])
{
    // extract color
  float4 baseColoralpha;
    float3 baseColor;
  if (hasColorTexture) {
    baseColoralpha = baseColorTexture.sample(textureSampler,
                                        in.uv * fragmentUniforms.tiling).rgba;
      baseColor = baseColoralpha.rgb;
  } else {
    baseColor = material.baseColor;
      baseColoralpha = float4(baseColor, 1.0);
  }
    //alpha test
    if(baseColoralpha.a < 0.5)
    {
        discard_fragment();
    }
  // extract metallic
  float metallic;
  if (hasMetallicTexture) {
    metallic = metallicTexture.sample(textureSampler, in.uv).r;
  } else {
    metallic = material.metallic;
  }
  // extract roughness
  float roughness;
  if (hasRoughnessTexture) {
    roughness = roughnessTexture.sample(textureSampler, in.uv).g;
  } else {
    roughness = material.roughness;
  }
  // extract ambient occlusion
  float ambientOcclusion;
  if (hasAOTexture) {
    ambientOcclusion = aoTexture.sample(textureSampler, in.uv).b;
  } else {
    ambientOcclusion = 1.0;
  }
  
  // normal map
  float3 normal;
  if (hasNormalTexture) {
    float3 normalValue = normalTexture.sample(textureSampler, in.uv * fragmentUniforms.tiling).xyz * 2.0 - 1.0;
      
      //if use a height map instead of normal map
//      float2 texelSize(normalTexture.get_width(), normalTexture.get_height());
//      float scale = 0.002;
//      float h1_u =normalTexture.sample(textureSampler, in.uv + float2(-texelSize.x, 0)).r;
//      float h2_u = normalTexture.sample(textureSampler, in.uv + float2(texelSize.x, 0)).r;
//      float deltaU = 2 * texelSize.x;
//
//      float3 tangentU(deltaU, 0, (h2_u - h1_u) * scale) ;
//
//
//      float h1_v =normalTexture.sample(textureSampler, in.uv + float2(0, -texelSize.y)).r;
//      float h2_v = normalTexture.sample(textureSampler, in.uv + float2(0, texelSize.y)).r;
//      float deltaV = 2 * texelSize.y;
//
//      float3 tangentV(0, deltaV, (h2_v - h1_v) * scale) ;
      
     
      
//    float3 normalValue = cross(tangentU, tangentV);
    normal = in.worldNormal * normalValue.z
    + in.worldTangent * normalValue.x
    + in.worldBitangent * normalValue.y;
  } else {
    normal = in.worldNormal;
  }
  normal = normalize(normal);
    
    GbufferOut out;
    out.normal = float4(normal, ((in.position.z / in.position.w) + 1.0) / 2.0);
    out.position = float4(in.worldPosition, 1.0);
    
    
    float shadow = 1.0;
    if(shadowTypes == hardShadow)
    {
        float2 xy = in.shadowPosition.xy;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;
        constexpr sampler s(coord::normalized, filter::linear,
                            address::clamp_to_edge,
                            compare_func:: less);
        float shadow_sample = shadowTexture.sample(s, xy);
        float current_sample =
               in.shadowPosition.z / in.shadowPosition.w;
        if (current_sample > shadow_sample ) {
            shadow = 0.0;
          }
    }
    
    else if(shadowTypes == PCF)
    {
        float bias = 0.005;
        float2 xy = in.shadowPosition.xy ;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;
        constexpr sampler s(coord::normalized, filter::nearest,
                            address::clamp_to_border,
                            border_color::opaque_white,
                            compare_func:: less);
        const int neighborWidth = 6;
        const float neighbors = (neighborWidth * 2.0 + 1.0) *
                                (neighborWidth * 2.0 + 1.0);
        
        
        float2 mapSize(4096, 4096);
        float2 texelSize = 1.0 / mapSize;
        float total = 0.0;
        for (int x = -neighborWidth; x <= neighborWidth; x++) {
          for (int y = -neighborWidth; y <= neighborWidth; y++) {
            float shadow_sample = shadowTexture.sample(
                                   s, xy + float2(x, y) * texelSize);
            float current_sample =
                 in.shadowPosition.z / in.shadowPosition.w;
             if(current_sample > 1.0)
                 total += 0.0;
            else if (current_sample - bias> shadow_sample ) {
              total += 1.0;
            }
          }
        }
        // 4
        total /= neighbors;
        shadow = 1.0 - (total * in.shadowPosition.w);
        
    }
    
    out.albedo = float4(baseColor, 1.0);
    out.materialPack = float4(metallic, roughness, ambientOcclusion, shadow);
    
    return out;
}

