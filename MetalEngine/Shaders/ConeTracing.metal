//
//  ConeTracing.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/12/3.
//

#include <metal_stdlib>
using namespace metal;
#import "../Common.h"

struct VertexOut{
    float4 position [[position]];
    float2 texCoords;
};

float roughnessToSpecularPower(float roughness)
{
    return clamp(2.0f / (roughness * roughness) - 2.0f, 0.0f, 256.0f);
}

float roughnessToConeAngle(float roughness)
{
    float specpow = roughnessToSpecularPower(roughness);
    return acos(pow(0.244, 1.0f / (specpow + 1.0f)));
}
float specularPowerToConeAngle(float specularPower)
{
    const float xi = 0.244f;
    float exponent = 1.0f / (specularPower + 1.0f);
    return acos(pow(xi, exponent));
}

float isoscelesTriangleOpposite(float adjacentLength, float coneTheta)
{
    return 2.0f * tan(coneTheta) * adjacentLength;
}

float isosclelesTriangleInRadius(float a, float h)
{
    float a2 = a * a;
    float fh2 = 4.0f * h * h;
    return (a * (sqrt(a2 + fh2) - a)) / (4.0f * h);
}

float4 coneSampleWeightColor(float2 samplePos, float mipChannel, float gloss,
                             texture2d<float> lightBuffer)
{
    constexpr sampler s(mag_filter::linear,
                        min_filter::linear,
                        mip_filter::linear);
    float3 sampleColor = lightBuffer.sample(s, samplePos, level(mipChannel)).rgb;
    return float4(sampleColor * gloss, gloss);
}

float isoscelesTriangleNextAdjacent(float adjacentLength, float incircleRadius)
{
    return adjacentLength - (incircleRadius * 2.0f);
}

float3 fresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}
fragment float4 ConeTracingFrag(VertexOut in [[stage_in]],
                                constant ssrParam& param[[buffer(0)]],
                                texture2d<float> albedoTexture [[texture(0)]],
                                texture2d<float> normalTexture [[texture(1)]],
                                texture2d<float> positionTexture [[texture(2)]],
                                texture2d<float> materialPackTexture [[texture(3)]],
                                texture2d<float> depthTexture [[texture(4)]],
                                texture2d<float> rtTexture [[texture(5)]],
                                texture2d<float> colorTexture [[texture(6)]],
                                texture2d<float> directLight [[texture(7)]]
                                )
{
    constexpr sampler s(filter::nearest);
    float4 raySS = rtTexture.sample(s, in.texCoords);
    float3 L_dir = directLight.sample(s, in.texCoords).rgb;
    if(raySS.w <= 0.0f)
    {
        return float4(L_dir, 1.0f);
    }
    float depth = depthTexture.sample(s, in.texCoords).r;
    float3 positionSS = float3(in.texCoords, depth);
    float3 positionVS = positionTexture.sample(s, in.texCoords).rgb;
    float3 toPositionVS = normalize(positionVS);
    float3 normalVS = normalTexture.sample(s, in.texCoords).rgb;
    
    float4 MatPack = materialPackTexture.sample(s, in.texCoords);
    float metallic = MatPack.x;
    float roughness = MatPack.y;
    float ambientOcclusion = MatPack.z;
    float shadow = MatPack.a;
    
    float gloss = 1.0f - roughness;
    
    float coneTheta = roughnessToConeAngle(roughness) * 0.5f;
    float2 deltaP = raySS.xy - positionSS.xy;
    float adjacentLength = length(deltaP);
    float2 adjacentUnit = normalize(deltaP);
    
    float4 totalColor = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float remainingAlpha = 1.0f;
    float maxMipLevel = param.numMips - 1.0f;
    float glossMult = gloss;
    float3 baseColor = albedoTexture.sample(s, in.texCoords).rgb;
    for(int i = 0; i < 14; ++i)
    {
        float oppositeLength = isoscelesTriangleOpposite(adjacentLength, coneTheta);
        
        float incircleSize = isosclelesTriangleInRadius(oppositeLength, adjacentLength);
        
        float2 samplePos = positionSS.xy + adjacentUnit * (adjacentLength - incircleSize);
        
        float mipChannel = clamp(log2(incircleSize * max(param.depthBufferSize.x, param.depthBufferSize.y)), 0.0f, maxMipLevel);
        
        float4 newColor = coneSampleWeightColor(samplePos, mipChannel, glossMult, colorTexture);
        
        remainingAlpha -= newColor.a;
        
        if(remainingAlpha < 0.0f)
        {
            newColor.rgb *= (1.0f - abs(remainingAlpha));
            
        }
        totalColor += newColor;
        if(totalColor.a >= 1.0f)
        {
            break;
        }
        
        adjacentLength = isoscelesTriangleNextAdjacent(adjacentLength, incircleSize);
        glossMult *= gloss;
    }
    
    float3 toEye = -toPositionVS;
    float3 F0 = float3(0.04);
    F0 = mix(F0, baseColor, metallic);
    float3 specular = fresnelSchlick(abs(dot(normalVS, toEye)), F0) / M_PI_F;
    
    float2 boundary = abs(raySS.xy - float2(0.5f, 0.5f)) * 2.0f;
    const float fadeDiffRcp = 1.0f / (param.fadeEnd - param.fadeStart);
    float fadeOnBorder = 1.0f - saturate((boundary.x - param.fadeStart) * fadeDiffRcp);
    fadeOnBorder *= 1.0f - saturate((boundary.y - param.fadeStart) * fadeDiffRcp);
    fadeOnBorder = smoothstep(0.0, 1.0, fadeOnBorder);
    float3 rayHitPositionVs = positionTexture.sample(s, raySS.xy).rgb;
    float fadeOnDistance = 1.0f - saturate(distance(rayHitPositionVs, positionVS) / param.maxDistance);
    float fadeOnPerpendicular = saturate(mix(0.0f, 1.0f, saturate(raySS.w * 4.0f)));
    float fadeOnRoughness = saturate(mix(0.0f, 1.0f, gloss * 4.0f));
    float totalFade = fadeOnBorder * fadeOnDistance * fadeOnPerpendicular * fadeOnRoughness * (1.0f - saturate(remainingAlpha));
    
    //float nDotl = max(0.001, saturate(dot(normalVS,toEye)));;
    //nDotl = ((nDotl + 1) / (1 + 1)) * (1 - 0.3) + 0.3;
    
    totalColor = float4(mix(float3(0.0, 0.0, 0.0), totalColor.rgb  , totalFade), 1.0f);
    
    return float4( L_dir + totalColor.rgb * specular   , 1.0);
//    return float4(0.0, 0.0, 0.0, 1.0);
    
    
}
