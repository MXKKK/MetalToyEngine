//
//  RSM.metal
//  MetalEngine
//
//  Created by 马西开 on 2022/2/2.
//

#include <metal_stdlib>
using namespace metal;
constant bool hasColorTexture [[function_constant(0)]];
constant bool hasNormalTexture [[function_constant(1)]];
constant bool hasSkeleton [[function_constant(6)]];


#import "../Common.h"

struct VertexIn {
  float4 position [[attribute(Position)]];
  float3 normal [[attribute(Normal)]];
  float2 uv [[attribute(UV)]];
  float3 tangent [[attribute(Tangent)]];
  float3 bitangent [[attribute(Bitangent)]];
  ushort4 joints [[attribute(Joints)]];
  float4 weights [[attribute(Weights)]];
};

struct VertexOut {
  float4 position [[position]];
  float3 worldPosition;
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
  float2 uv;
};

struct RSMOut{
    float4 position [[color(0)]];
    float4 normal [[color(1)]];
    float4 flux [[color(2)]];
};

vertex VertexOut RSM_VS(const VertexIn vertexIn [[stage_in]],
                             constant float4x4 *jointMatrices [[buffer(22),
                                                                function_constant(hasSkeleton)]],
                             constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]])

{
  float4 position = vertexIn.position;
  float4 normal = float4(vertexIn.normal, 0);
  float4 tangent = float4(vertexIn.tangent, 0);
  float4 bitangent = float4(vertexIn.bitangent, 0);
  
  if (hasSkeleton) {
    float4 weights = vertexIn.weights;
    ushort4 joints = vertexIn.joints;
    position =
    weights.x * (jointMatrices[joints.x] * position) +
    weights.y * (jointMatrices[joints.y] * position) +
    weights.z * (jointMatrices[joints.z] * position) +
    weights.w * (jointMatrices[joints.w] * position);
    normal =
    weights.x * (jointMatrices[joints.x] * normal) +
    weights.y * (jointMatrices[joints.y] * normal) +
    weights.z * (jointMatrices[joints.z] * normal) +
    weights.w * (jointMatrices[joints.w] * normal);
    tangent =
    weights.x * (jointMatrices[joints.x] * tangent) +
    weights.y * (jointMatrices[joints.y] * tangent) +
    weights.z * (jointMatrices[joints.z] * tangent) +
    weights.w * (jointMatrices[joints.w] * tangent);
    bitangent =
    weights.x * (jointMatrices[joints.x] * bitangent) +
    weights.y * (jointMatrices[joints.y] * bitangent) +
    weights.z * (jointMatrices[joints.z] * bitangent) +
    weights.w * (jointMatrices[joints.w] * bitangent);
  }
  
  VertexOut out {
    .position = uniforms.projectionMatrix * uniforms.viewMatrix
    * uniforms.modelMatrix * position,
    .worldPosition = (uniforms.modelMatrix * position).xyz,
    .worldNormal = uniforms.normalMatrix * normal.xyz,
      .worldTangent = uniforms.normalMatrix * tangent.xyz,
      .worldBitangent = uniforms.normalMatrix * bitangent.xyz,
      .uv = vertexIn.uv
  };

  return out;
}

fragment RSMOut RSM_PS(VertexOut in[[stage_in]],
                       texture2d<float> baseColorTexture [[texture(0), function_constant(hasColorTexture)]],
                       texture2d<float> normalTexture [[texture(1), function_constant(hasNormalTexture)]])
{
    constexpr sampler s(filter::linear);
    float4 baseColoralpha;
    float3 baseColor;
    if (hasColorTexture) {
      baseColoralpha = baseColorTexture.sample(s, in.uv).rgba;
        baseColor = baseColoralpha.rgb;
    } else {
      baseColor = float3(1.0f, 1.0f, 1.0f);
        baseColoralpha = float4(baseColor, 1.0);
    }
    float3 normal;
    
    if (hasNormalTexture) {
//      float3 normalValue = normalTexture.sample(s, in.uv ).xyz * 2.0 - 1.0;
//      normal = in.worldNormal * normalValue.z
//      + in.worldTangent * normalValue.x
//      + in.worldBitangent * normalValue.y;


        float2 texelSize(normalTexture.get_width(), normalTexture.get_height());
        float scale = 0.002;
        float h1_u =normalTexture.sample(s, in.uv + float2(-texelSize.x, 0)).r;
        float h2_u = normalTexture.sample(s, in.uv + float2(texelSize.x, 0)).r;
        float deltaU = 2 * texelSize.x;

        float3 tangentU(deltaU, 0, (h2_u - h1_u) * scale) ;


        float h1_v =normalTexture.sample(s, in.uv + float2(0, -texelSize.y)).r;
        float h2_v = normalTexture.sample(s, in.uv + float2(0, texelSize.y)).r;
        float deltaV = 2 * texelSize.y;

        float3 tangentV(0, deltaV, (h2_v - h1_v) * scale) ;



      float3 normalValue = cross(tangentU, tangentV);
      normal = in.worldNormal * normalValue.z
      + in.worldTangent * normalValue.x
      + in.worldBitangent * normalValue.y;
    } else {
      normal = in.worldNormal;
    }
    normal = normalize(normal);
    
    RSMOut out;
    out.position = float4(in.worldPosition, 1.0f);
    out.normal = float4(normal, 1.0f);
    out.flux = float4(baseColor, 1.0f);
    return out;
}
