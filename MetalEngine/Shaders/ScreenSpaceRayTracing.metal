//
//  ScreenSpaceRayTracing.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/12/1.
//

#include <metal_stdlib>
using namespace metal;
#import "../Common.h"

bool intersectsDepthBuffer(float z, float minZ, float maxZ, constant ssrParam& param)
{
    float depthScale = min(1.0f, z * param.strideZCutoff);
    z += param.zThickness;
    return (z < param.farPlaneZ) && (maxZ >= z) && (minZ - param.zThickness <= z);
    
    //return (z < param.farPlaneZ) &&(maxZ >= z) && (minZ  - param.zThickness<= z);
    
}

float linearDepthTexelFetch(float2 hitPixel, texture2d<float> depthBuffer, constant ssrParam& param, float2 texelSize, int mip)
{

    constexpr sampler s(filter::nearest,
                      mip_filter::nearest,
                        mag_filter::nearest,
                        min_filter::nearest,
                        address::clamp_to_zero);
    //float2 tex(hitPixel.x * texelSize.x, hitPixel.y * texelSize.y);
    //float factor = pow(2.0f, mip);
    //texelSize *= factor;
    
    float depth = depthBuffer.sample(s, hitPixel , level(mip)).r;
    //float depth = depthBuffer.read(hitPixel).r;
    //linearizeDepth
    float z = depth * 2.0 - 1.0; //Back to NDC
    return (2.0 * param.nearPlaneZ * param.farPlaneZ) / (param.farPlaneZ + param.nearPlaneZ - z * (param.farPlaneZ - param.nearPlaneZ));
    
}
bool traceScreenSpaceRay(
                         float3 csOrig,
                         float3 csDir,
                         float jitter,
                         thread float2& hitPixel,
                         thread float3& hitPoint,
                         constant ssrParam& param,
                         float4x4 proj,
                         texture2d<float> depthBuffer,
                         float2 texelSize
                         )
{
    float2 depthBufferSize(depthBuffer.get_width(), depthBuffer.get_height());
    float rayLength = ((csOrig.z + csDir.z * param.maxDistance) < param.farPlaneZ) ? (param.farPlaneZ - csOrig.z) / csDir.z : param.maxDistance;
    float3 csEndPoint = csOrig + csDir * rayLength;
    assert(rayLength >= 0);
    float4 H0 = proj * float4(csOrig, 1.0f);
    float4 H1 = proj * float4(csEndPoint, 1.0f);
    float k0 = 1.0f / H0.w;
    float k1 = 1.0f / H1.w;
    int max_mip = depthBuffer.get_num_mip_levels();
    H0 /= H0.w;
    H0.xy = (H0.xy * 0.5 + 0.5) * depthBufferSize;
   
    H1 /= H1.w;
    H1.xy = (H1.xy * 0.5 + 0.5) * depthBufferSize;
//    H1.xy *= param.depthBufferSize;
    
    
    float3 Q0 = csOrig * k0;
    float3 Q1 = csEndPoint * k1;
    
//    float2 P0 = H0.xy * k0;
//    float2 P1 = H1.xy * k1;
    float2 P0 = H0.xy;
    float2 P1 = H1.xy;
    
    P1 += (distance_squared(P0, P1) < 0.0001f) ? float2(0.01f, 0.01f) : 0.0f;
    float2 delta = P1 - P0;
    
    bool permute = false;
    if(abs(delta.x) < abs(delta.y))
    {
        permute = true;
        delta = delta.yx;
        P0 = P0.yx;
        P1 = P1.yx;
    }
    
    float stepDir = sign(delta.x);
    float invdx = stepDir / delta.x;
    
    float3 dQ = (Q1 - Q0) * invdx;
    float dk = (k1 - k0) * invdx;
    float2 dP = float2(stepDir, delta.y * invdx);
    
    //float strideScale = 1.0f - min(1.0f, csOrig.z * param.strideZCutoff);
    float stride = 1.0f;
    
    dP *= stride;
    dQ *= stride;
    dk *= stride;
    
    P0 += dP;
    Q0 += dQ;
    k0 += dk;
    
    float4 PQK = float4(P0, Q0.z, k0);
    float4 dPQK = float4(dP, dQ.z, dk);
    float3 Q = Q0;
    
    float end = P1.x * stepDir;
    float stepCount = 0.0f;
    float prevZMaxEstimate = csOrig.z;
    float rayZMin = prevZMaxEstimate;
    float rayZMax = prevZMaxEstimate;
    float sceneZMax = rayZMax + 100.0f;
    int mip = 0;
    stride = 1.0f;
    
    //while(mip >= 0)
    //{
//        for(;((PQK.x * stepDir) <= end) && (stepCount < param.maxSteps) && !intersectsDepthBuffer(sceneZMax, rayZMin, rayZMax, param) &&
//            (sceneZMax != 0.0f);
//            ++stepCount)
    for(;((PQK.x * stepDir) <= end) && (stepCount < param.maxSteps) && mip >= 0 &&
                (sceneZMax != 0.0f);
                ++stepCount)
        {
            
            float4 new_PQK = PQK + dPQK * stride;
            
            rayZMin = prevZMaxEstimate;
            rayZMax = (dPQK.z * 0.5f * stride + new_PQK.z) / (dPQK.w * 0.5f * stride + new_PQK.w);
            if(rayZMin > rayZMax)
            {
                float _ = rayZMin;
                rayZMin = rayZMax;
                rayZMax = _;
            }
            float2 new_hitPixel = permute ? new_PQK.yx : new_PQK.xy;
            //float2 offset(1.0f, -1.0f);
            new_hitPixel.y = depthBufferSize.y - new_hitPixel.y;
            float2 hit_uv = new_hitPixel * texelSize;
            bool flag = (hit_uv.x > 1.0f || hit_uv.x < 0.0f || hit_uv.y > 1.0f || hit_uv.y < 0.0f);
            sceneZMax = linearDepthTexelFetch(new_hitPixel  * texelSize, depthBuffer, param, texelSize, mip);
            if(intersectsDepthBuffer(sceneZMax, rayZMin, rayZMax, param) || flag)
            {
                mip--;
                stride /= 2.0f;
                if(mip < 0)
                {
                    hitPixel = new_hitPixel;
                    return true;
                }
            }
                
            else
            {
                if(mip < 5)
                {
                    stride *=  2.0f ;
                    mip++ ;
                }
                
                
                
                prevZMaxEstimate = rayZMax;
                
                
                //rayZMax = (dPQK.z * 0.5f * stride + PQK.z) / (dPQK.w * 0.5f * stride + PQK.w);
                PQK = new_PQK;
                hitPixel = new_hitPixel;
                
            }

           
            
            
            
           
        
    
        }
        
        

    
    //Q.xy += dQ.xy * stepCount;
    //hitPoint = Q * (1.0f / PQK.w);
    return mip < 0;
    //return intersectsDepthBuffer(sceneZMax, rayZMin, rayZMax, param);
    
    
}

struct VertexOut{
    float4 position [[position]];
    float2 texCoords;
};

fragment float4 SSRT_fragment(VertexOut in [[stage_in]],
                              constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
                              constant Uniforms &uniforms[[buffer(BufferIndexUniforms)]],
                              texture2d<float> normalTexture [[texture(1)]],
                              texture2d<float> positionTexture [[texture(2)]],
                              texture2d<float> depthTexture [[texture(4)]],
                              constant ssrParam& param[[buffer(0)]])
{
    constexpr sampler s(filter::nearest);
    float2 texelSize = float2(1.0f / depthTexture.get_width(), 1.0f / depthTexture.get_height());
//    float3 albedo = albedoTexture.sample(s, in.texCoords).xyz;
    float3 normalVS = normalTexture.sample(s, in.texCoords).xyz;
    float3 position = positionTexture.sample(s, in.texCoords).xyz;
//    float4 MatPack = materialPackTexture.sample(s, in.texCoords);
//    float metallic = MatPack.x;
//    float roughness = MatPack.y;
//    float ambientOcclusion = MatPack.z;
//    float shadow = MatPack.a;
    float depth = depthTexture.sample(s, in.texCoords, level(0)).r;
    //float depth = depthTexture.sample(s, in.texCoords).x;
    //linearizeDepth
    float liner_depth = depth * 2.0 - 1.0; //Back to NDC
    liner_depth =  (2.0 * param.nearPlaneZ * param.farPlaneZ) / (param.farPlaneZ + param.nearPlaneZ - liner_depth * (param.farPlaneZ - param.nearPlaneZ));
    
    float3 rayOriginVS = position * liner_depth;
    float3 toPositionVS = normalize(position);
    float3 rayDirectionVS = normalize(reflect(toPositionVS, normalVS));
    
    float rDotV = dot(rayDirectionVS, toPositionVS);
    
    float2 hitPixel = float2(0.0f, 0.0f);
    float3 hitPoint = float3(0.0f, 0.0f, 0.0f);
    
    float jitter = param.stride > 1.0f ? float(int(in.texCoords.x + in.texCoords.y) & 1) * 0.5f : 0.0f;
    
//    bool intersection = traceScreenSpaceRay(rayOriginVS, rayDirectionVS, jitter, hitPixel, hitPoint, param, float4x4(1.0), depthTexture);
    
    bool intersection = traceScreenSpaceRay(position, rayDirectionVS, jitter, hitPixel, hitPoint, param, uniforms.projectionMatrix, depthTexture, texelSize);
//    return float4(hitPoint, 1.0);
    depth = depthTexture.read(uint2(hitPixel)).r;
    float texelWidth = 1.0 / depthTexture.get_width();
    float texelHeight = 1.0 / depthTexture.get_height();
    hitPixel *= float2(texelWidth, texelHeight);
    if(hitPixel.x > 1.0f || hitPixel.x < 0.0f || hitPixel.y > 1.0f || hitPixel.y < 0.0f)
    {
        intersection = false;
    }
    
    return float4(hitPixel, depth, rDotV) * (intersection? 1.0f : 0.0f);
   
    
}
