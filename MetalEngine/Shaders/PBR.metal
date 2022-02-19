/**
 * Copyright (c) 2019 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"

constant bool hasColorTexture [[function_constant(0)]];
constant bool hasNormalTexture [[function_constant(1)]];
constant bool hasRoughnessTexture [[function_constant(2)]];
constant bool hasMetallicTexture [[function_constant(3)]];
constant bool hasAOTexture [[function_constant(4)]];
constant int  shadowTypes [[function_constant(5)]];

constant float pi = 3.1415926535897932384626433832795;

struct VertexOut {
  float4 position [[ position ]];
  float3 worldPosition;
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
  float2 uv;
    float4 shadowPosition;
};

typedef struct Lighting {
  float3 lightDirection;
  float3 viewDirection;
  float3 baseColor;
  float3 normal;
  float metallic;
  float roughness;
  float ambientOcclusion;
  float3 lightColor;
} Lighting;

float3 render(Lighting lighting);

float4 fog(float4 position, float4 color) {
  // 1
  float distance = position.z / position.w;
  // 2
  float density = 0.2;
  float fog = 1.0 - clamp(exp(-density * distance), 0.0, 1.0);
  // 3
  float4 fogColor = float4(1.0);
  color = mix(color, fogColor, fog);
  return color;
}



fragment float4 fragment_mainPBR(VertexOut in [[stage_in]],
          constant Light_Uniform *lights [[buffer(BufferIndexLights)]],
          constant Material &material [[buffer(BufferIndexMaterials)]],
          constant bool &fogEnabled [[buffer(BufferIndexFog)]],
          sampler textureSampler [[sampler(0)]],
          constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
          texture2d<float> baseColorTexture [[texture(0), function_constant(hasColorTexture)]],
          texture2d<float> normalTexture [[texture(1), function_constant(hasNormalTexture)]],
          texture2d<float> roughnessTexture [[texture(2), function_constant(hasRoughnessTexture)]],
          texture2d<float> metallicTexture [[texture(3), function_constant(hasMetallicTexture)]],
          texture2d<float> aoTexture [[texture(4), function_constant(hasAOTexture)]],
          depth2d<float> shadowTexture [[texture(5), function_constant(shadowTypes)]]){
    // extract color
  float3 baseColor;
  if (hasColorTexture) {
    baseColor = baseColorTexture.sample(textureSampler,
                                        in.uv * fragmentUniforms.tiling).rgb;
  } else {
    baseColor = material.baseColor;
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
    roughness = roughnessTexture.sample(textureSampler, in.uv).r;
  } else {
    roughness = material.roughness;
  }
  // extract ambient occlusion
  float ambientOcclusion;
  if (hasAOTexture) {
    ambientOcclusion = aoTexture.sample(textureSampler, in.uv).r;
  } else {
    ambientOcclusion = 1.0;
  }

  // normal map
  float3 normal;
  if (hasNormalTexture) {
    float3 normalValue = normalTexture.sample(textureSampler, in.uv * fragmentUniforms.tiling).xyz * 2.0 - 1.0;
    normal = in.worldNormal * normalValue.z
    + in.worldTangent * normalValue.x
    + in.worldBitangent * normalValue.y;
      
  } else {
    normal = in.worldNormal;
  }
  normal = normalize(normal);

  float3 viewDirection = normalize(fragmentUniforms.cameraPosition - in.worldPosition);

  Light_Uniform light = lights[0];
  float3 lightDirection = normalize(light.position);

  // all the necessary components are in place
  Lighting lighting;
  lighting.lightDirection = lightDirection;
  lighting.viewDirection = viewDirection;
  lighting.baseColor = baseColor;
  lighting.normal = normal;
  lighting.metallic = metallic;
  lighting.roughness = roughness;
  lighting.ambientOcclusion = ambientOcclusion;
  lighting.lightColor = light.specularColor;

  float3 specularOutput = render(lighting);
  // compute Lambertian diffuse
  float nDotl = max(0.001, saturate(dot(lighting.normal, lighting.lightDirection)));
  // rescale from -1 : 1 to 0.4 - 1 to lighten shadows
//  nDotl = ((nDotl + 1) / (1 + 1)) * (1 - 0.3) + 0.3;
  float3 diffuseColor = light.color * baseColor * nDotl * ambientOcclusion;
  diffuseColor *= 1.0 - metallic;
    float3 color = specularOutput + diffuseColor;
    if(shadowTypes == hardShadow)
    {
        float2 xy = in.shadowPosition.xy ;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;
        constexpr sampler s(coord::normalized, filter::linear,
                            address::clamp_to_border,
                            border_color::opaque_white,
                            compare_func:: less);
        float shadow_sample = shadowTexture.sample(s, xy);
        float current_sample =
             in.shadowPosition.z / in.shadowPosition.w;
        if(current_sample > 1.0)
            current_sample = 0.0;
        if (current_sample > shadow_sample) {
          color *= 0.0;
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
        float lightFactor = 1.0 - (total * in.shadowPosition.w);
        color = color * lightFactor;

    }

    //other light sources(without shadows)
    for(uint i = 1; i < fragmentUniforms.lightCount; i++){
        Light_Uniform light = lights[i];
        float attenuation = 1.0;
        float3 lightDirection;
        if(light.type == Sunlight){
            lightDirection = normalize(light.position);
        }
        else if(light.type == Pointlight){
            lightDirection = normalize(light.position - in.worldPosition);
            float d = distance(light.position, in.worldPosition);
            attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);

        }
        else if(light.type == Spotlight){
            float d = distance(light.position, in.worldPosition);
            lightDirection = normalize(light.position - in.worldPosition);
            float3 coneDirection = normalize(-light.coneDirection);
            float spotResult = (dot(lightDirection, coneDirection));
            if (spotResult > cos(light.coneAngle)) {
              attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                attenuation *= pow(spotResult, light.coneAttenuation);
            }
        }
        lighting.lightDirection = lightDirection;
        lighting.lightColor = light.specularColor;
        diffuseColor = light.color * baseColor * nDotl * ambientOcclusion;
        diffuseColor *= 1.0 - metallic;
        specularOutput = render(lighting);
        color += (specularOutput + diffuseColor) * attenuation;


    }
    float4 finalColor = float4(color, 1.0);
    if(fogEnabled == true)
    {
        finalColor = fog(in.position, finalColor);
    }
  return finalColor;
}

/*
PBR.metal rendering equation from Apple's LODwithFunctionSpecialization sample code is under Copyright © 2017 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/


float3 render(Lighting lighting) {
  // Rendering equation courtesy of Apple et al.
  float nDotl = max(0.001, saturate(dot(lighting.normal, lighting.lightDirection)));
  float3 halfVector = normalize(lighting.lightDirection + lighting.viewDirection);
  float nDoth = max(0.001, saturate(dot(lighting.normal, halfVector)));
  float nDotv = max(0.001, saturate(dot(lighting.normal, lighting.viewDirection)));
  float hDotl = max(0.001, saturate(dot(lighting.lightDirection, halfVector)));

  // specular roughness
  float specularRoughness = lighting.roughness * (1.0 - lighting.metallic) + lighting.metallic;

  // Distribution
  float Ds;
  if (specularRoughness >= 1.0) {
    Ds = 1.0 / pi;
  }
  else {
    float roughnessSqr = specularRoughness * specularRoughness;
    float d = (nDoth * roughnessSqr - nDoth) * nDoth + 1;
    Ds = roughnessSqr / (pi * d * d);
  }

  // Fresnel
  float3 Cspec0 = float3(1.0);
  float fresnel = pow(clamp(1.0 - hDotl, 0.0, 1.0), 5.0);
  float3 Fs = float3(mix(float3(Cspec0), float3(1), fresnel));


  // Geometry
  float alphaG = (specularRoughness * 0.5 + 0.5) * (specularRoughness * 0.5 + 0.5);
  float a = alphaG * alphaG;
  float b1 = nDotl * nDotl;
  float b2 = nDotv * nDotv;
  float G1 = (float)(1.0 / (b1 + sqrt(a + b1 - a*b1)));
  float G2 = (float)(1.0 / (b2 + sqrt(a + b2 - a*b2)));
  float Gs = G1 * G2;

  float3 specularOutput = (Ds * Gs * Fs * lighting.lightColor) * (1.0 + lighting.metallic * lighting.baseColor) + lighting.metallic * lighting.lightColor * lighting.baseColor;
  specularOutput = specularOutput * lighting.ambientOcclusion;

  return specularOutput;
}



fragment float4 fragment_mainPBR_heightBump(VertexOut in [[stage_in]],
          constant Light_Uniform *lights [[buffer(BufferIndexLights)]],
          constant Material &material [[buffer(BufferIndexMaterials)]],
          constant bool &fogEnabled [[buffer(BufferIndexFog)]],
          sampler textureSampler [[sampler(0)]],
          constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
          texture2d<float> baseColorTexture [[texture(0), function_constant(hasColorTexture)]],
          texture2d<float> normalTexture [[texture(1), function_constant(hasNormalTexture)]],
          texture2d<float> roughnessTexture [[texture(2), function_constant(hasRoughnessTexture)]],
          texture2d<float> metallicTexture [[texture(3), function_constant(hasMetallicTexture)]],
          texture2d<float> aoTexture [[texture(4), function_constant(hasAOTexture)]],
          depth2d<float> shadowTexture [[texture(5), function_constant(shadowTypes)]]){
    // extract color
  float3 baseColor;
    float2 texelSize(1.0 / normalTexture.get_width(), 1.0 / normalTexture.get_height());
  if (hasColorTexture) {
    baseColor = baseColorTexture.sample(textureSampler,
                                        in.uv * fragmentUniforms.tiling).rgb;
  } else {
    baseColor = material.baseColor;
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
    roughness = roughnessTexture.sample(textureSampler, in.uv).r;
  } else {
    roughness = material.roughness;
  }
  // extract ambient occlusion
  float ambientOcclusion;
  if (hasAOTexture) {
    ambientOcclusion = aoTexture.sample(textureSampler, in.uv).r;
  } else {
    ambientOcclusion = 1.0;
  }

  // normal map
  float3 normal;
  if (hasNormalTexture) {
      float scale = 0.002;
      float h1_u =normalTexture.sample(textureSampler, in.uv + float2(-texelSize.x, 0)).r;
      float h2_u = normalTexture.sample(textureSampler, in.uv + float2(texelSize.x, 0)).r;
      float deltaU = 2 * texelSize.x;
      
      float3 tangentU(deltaU, 0, (h2_u - h1_u) * scale) ;
      
      
      float h1_v =normalTexture.sample(textureSampler, in.uv + float2(0, -texelSize.y)).r;
      float h2_v = normalTexture.sample(textureSampler, in.uv + float2(0, texelSize.y)).r;
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

  float3 viewDirection = normalize(fragmentUniforms.cameraPosition - in.worldPosition);

  Light_Uniform light = lights[0];
  float3 lightDirection = normalize(light.position);

  // all the necessary components are in place
  Lighting lighting;
  lighting.lightDirection = lightDirection;
  lighting.viewDirection = viewDirection;
  lighting.baseColor = baseColor;
  lighting.normal = normal;
  lighting.metallic = metallic;
  lighting.roughness = roughness;
  lighting.ambientOcclusion = ambientOcclusion;
  lighting.lightColor = light.specularColor;

  float3 specularOutput = render(lighting);
  // compute Lambertian diffuse
  float nDotl = max(0.001, saturate(dot(lighting.normal, lighting.lightDirection)));
  // rescale from -1 : 1 to 0.4 - 1 to lighten shadows
//  nDotl = ((nDotl + 1) / (1 + 1)) * (1 - 0.3) + 0.3;
  float3 diffuseColor = light.color * baseColor * nDotl * ambientOcclusion;
  diffuseColor *= 1.0 - metallic;
    float3 color = specularOutput + diffuseColor;
    if(shadowTypes == hardShadow)
    {
        float2 xy = in.shadowPosition.xy ;
        xy = xy * 0.5 + 0.5;
        xy.y = 1 - xy.y;
        constexpr sampler s(coord::normalized, filter::linear,
                            address::clamp_to_border,
                            border_color::opaque_white,
                            compare_func:: less);
        float shadow_sample = shadowTexture.sample(s, xy);
        float current_sample =
             in.shadowPosition.z / in.shadowPosition.w;
        if(current_sample > 1.0)
            current_sample = 0.0;
        if (current_sample > shadow_sample) {
          color *= 0.0;
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
        float lightFactor = 1.0 - (total * in.shadowPosition.w);
        color = color * lightFactor;

    }

    //other light sources(without shadows)
    for(uint i = 1; i < fragmentUniforms.lightCount; i++){
        Light_Uniform light = lights[i];
        float attenuation = 1.0;
        float3 lightDirection;
        if(light.type == Sunlight){
            lightDirection = normalize(light.position);
        }
        else if(light.type == Pointlight){
            lightDirection = normalize(light.position - in.worldPosition);
            float d = distance(light.position, in.worldPosition);
            attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);

        }
        else if(light.type == Spotlight){
            float d = distance(light.position, in.worldPosition);
            lightDirection = normalize(light.position - in.worldPosition);
            float3 coneDirection = normalize(-light.coneDirection);
            float spotResult = (dot(lightDirection, coneDirection));
            if (spotResult > cos(light.coneAngle)) {
              attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                attenuation *= pow(spotResult, light.coneAttenuation);
            }
        }
        lighting.lightDirection = lightDirection;
        lighting.lightColor = light.specularColor;
        diffuseColor = light.color * baseColor * nDotl * ambientOcclusion;
        diffuseColor *= 1.0 - metallic;
        specularOutput = render(lighting);
        color += (specularOutput + diffuseColor) * attenuation;


    }
    float4 finalColor = float4(color, 1.0);
    if(fogEnabled == true)
    {
        finalColor = fog(in.position, finalColor);
    }
  return finalColor;
}



