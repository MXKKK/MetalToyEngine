//
//  Composition.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/11/18.
//

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"
constant float pi = 3.1415926535897932384626433832795;
constant bool enableRSM [[function_constant(0)]];

#define r_max 0.4
#define n_sample 200
struct VertexOut{
    float4 position [[position]];
    float2 texCoords;
};

struct ComposeOut{
    float4 directLight [[color(0)]];
    float4 diffuse [[color(1)]];
    
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
float4 IBL(float metallic, float roughness, float ao, float3 viewDirection, float3 normal,
           float3 albedo, texturecube<float> skybox, texturecube<float> skyboxDiffuse, texture2d<float> brdfLut);
vertex VertexOut compositionVert(constant float2 *quadVertices [[buffer(0)]],
                                 constant float2 *quadTexCoords [[buffer(1)]],
                                 uint id [[vertex_id]]){
    VertexOut out;
    out.position = float4(quadVertices[id], 0.0, 1.0);
    out.texCoords = quadTexCoords[id];
    return out;
}

float4 fog(float position, float4 color) {
  float distance = position;
  float density = 0.2;
  float fog = 1.0 - clamp(exp(-density * distance), 0.0, 1.0);
  float4 fogColor = float4(1.0);
  color = mix(color, fogColor, fog);
  return color;
}


fragment ComposeOut compositionFrag(VertexOut in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
                                constant Light_Uniform *lights [[buffer(BufferIndexLights)]],
                                constant bool &fogEnabled [[buffer(BufferIndexFog)]],
                                    constant bool &hasSkyBox [[buffer(BufferIndexHasSkybox)]],
                                texture2d<float> albedoTexture [[texture(0)]],
                                texture2d<float> normalTexture [[texture(1)]],
                                texture2d<float> positionTexture [[texture(2)]],
                                texture2d<float> materialPackTexture [[texture(3)]],
                                texture2d<float> lightTexture [[texture(5)]],
                                texture2d<float> rsmPosition [[texture(6), function_constant(enableRSM)]],
                                texture2d<float> rsmNormal [[texture(7), function_constant(enableRSM)]],
                                texture2d<float> rsmFlux [[texture(8), function_constant(enableRSM)]],
                                    texturecube<float> skybox [[texture(BufferIndexSkybox)]],
                                    texturecube<float> skyboxDiffuse [[texture(BufferIndexSkyboxDiffuse)]],
                                    texture2d<float> brdfLut [[texture(BufferIndexBRDFLut)]],
                                    constant float *samples [[buffer(BufferIndexSamples)]]
                                )
{
    
    constexpr sampler s(filter::nearest);
    float3 albedo = albedoTexture.sample(s, in.texCoords).xyz;
    float3 normal = normalTexture.sample(s, in.texCoords).xyz;
    float3 position = positionTexture.sample(s, in.texCoords).xyz;
    float4 MatPack = materialPackTexture.sample(s, in.texCoords);
    float metallic = MatPack.x;
    float roughness = MatPack.y;
    float ambientOcclusion = MatPack.z;
    float shadow = MatPack.a;
    ComposeOut out;
    
    float3 viewDirection = normalize( -position);
    
    float3 color(0.0, 0.0, 0.0);
    float3 dc(0.0 ,0.0, 0.0);
    
    for(uint i = 0; i < fragmentUniforms.lightCount; i++){
        Light_Uniform light = lights[i];
        float attenuation = 1.0;
        float3 lightDirection;
        float3 lightPos;
        if(light.type == Sunlight){
            lightPos = uniforms.viewNormalMatrix * light.position;
            lightDirection = normalize(lightPos);
        }
        else if(light.type == Pointlight){
            lightPos = (uniforms.viewMatrix * float4(light.position, 1.0)).xyz;
            lightDirection = normalize(lightPos - position);
            float d = distance(lightPos, position);
            attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
            
        }
        else if(light.type == Spotlight){
            lightPos = (uniforms.viewMatrix * float4(light.position, 1.0)).xyz;
            float d = distance(lightPos, position);
            lightDirection = normalize(lightPos - position);
            float3 coneDirection = normalize(uniforms.viewNormalMatrix * (-light.coneDirection));
            float spotResult = (dot(lightDirection, coneDirection));
            if (spotResult > cos(light.coneAngle)) {
              attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                attenuation *= pow(spotResult, light.coneAttenuation);
            }
        }
    
        Lighting lighting;
        lighting.lightDirection = lightDirection;
        lighting.viewDirection = viewDirection;
        lighting.baseColor = albedo;
        lighting.normal = normal;
        lighting.metallic = metallic;
        lighting.roughness = roughness;
        lighting.ambientOcclusion = ambientOcclusion;
        lighting.lightColor = light.specularColor;
        
        
        float nDotl = max(0.001, saturate(dot(lighting.normal, lighting.lightDirection)));
        nDotl = ((nDotl + 1) / (1 + 1)) * (1 - 0.3) + 0.3;
        float3 diffuseColor = light.color * albedo * nDotl * ambientOcclusion;
        diffuseColor *= 1.0 - metallic;
        float3 specularOutput = render(lighting);
        color += (specularOutput + diffuseColor) * attenuation;
        dc = diffuseColor * attenuation;
        
        
    
        
    }
    float3 ambinent(0.1, 0.1, 0.1);
    ambinent *= albedo;
    color *= shadow;
    if(hasSkyBox)
    {
        color += IBL(metallic, roughness, ambientOcclusion, viewDirection, normal, albedo, skybox, skyboxDiffuse, brdfLut).rgb;
    }
    float4 ret(color  , 1.0);
    
    if(fogEnabled == true)
    {
        float fac = normalTexture.sample(s, in.texCoords).w;
        fac = fac * 2.0 - 1.0;
        ret = fog(fac, ret);
    }
//    float2 texelSize(lightTexture.get_width(), lightTexture.get_height());
//    float4 lightPack = lightTexture.sample(s, in.texCoords);
//    if(lightPack.w <= 0.0f)
//        return float4(0.0, 0.0, 0.0, 1.0);
//    float2 tex = lightPack.xy;
//    float d = lightPack.z ;
//    return float4(albedoTexture.sample(s, tex).xyz, 1.0);
      
//    return  ret;
    out.diffuse = ret;
    if(enableRSM)
    {
        float normalizer = 0.0f;
        float3 indir(0.0f, 0.0f, 0.0f); //E
        float3 n = uniforms.inv_viewNormalMatrix * normal;
        n = normalize(n);
        float3 x = (uniforms.inv_viewMatrix * float4(position, 1.0f)).rgb;
        //float2 RSM_Size(1.0f / rsmFlux.get_width(), 1.0f / rsmFlux.get_height());
        float4 clipPos = uniforms.shadowMatrix * float4(x, 1.0f);
        clipPos.xy /= clipPos.w;
        
        constexpr sampler rsm_s(filter::nearest, address::clamp_to_border,
                                border_color::opaque_black);
        float2 rsm_uv = (clipPos.xy + 1.0f) / 2.0f;
        rsm_uv.y = 1.0f - rsm_uv.y;
        //float3 ttt;
        for(int i = 0; i < n_sample; ++i)
        {
            float2 offset = float2( samples[3 * i] , samples[3 * i + 1] );
            float2 sample_uv = rsm_uv + offset;
            
            float3 np = rsmNormal.sample(rsm_s, sample_uv).rgb;
            np = normalize(np);
            float3 Phi = rsmFlux.sample(rsm_s, sample_uv).rgb;
            //ttt = Phi;
            float3 xp = rsmPosition.sample(rsm_s, sample_uv).rgb; //xp
            float3 xxp = x - xp;
            float d2 = dot( xxp, xxp );
            xxp = normalize(xxp);
            
            //xxp = normalize(xxp);
            float s1_sqr = samples[3 * i + 2];
            //indir += s1_sqr * Phi;
            indir += max(0.0f, dot(np, xxp)) * max(0.0f, dot(n, -xxp)) * s1_sqr / d2 * Phi;
            normalizer += s1_sqr;
            
            
            
        }
        
        indir = indir * n_sample * 4.0f / normalizer;
        
        ret.rgb += indir * albedo;
        //ret.rgb = ttt;
    }
    out.directLight = saturate(ret);
    
    return out;
    
    
    
}

float4 IBL(float metallic, float roughness, float ao, float3 viewDirection, float3 normal,
           float3 albedo, texturecube<float> skybox, texturecube<float> skyboxDiffuse, texture2d<float> brdfLut)
{
    constexpr sampler s(min_filter::linear, mag_filter::linear);
    float4 diffuse = skyboxDiffuse.sample(s, normal);
    diffuse = mix(pow(diffuse, 0.5), diffuse, metallic);

    float3 textureCoordinates = reflect(viewDirection, normal);

    float3 prefilteredColor = skybox.sample(s, textureCoordinates,
                                            level(roughness * 10)).rgb;

    float nDotV = saturate(dot(normal, normalize(-viewDirection)));
    float2 envBRDF = brdfLut.sample(s, float2(roughness, nDotV)).rg;
    
    float3 f0 = mix(0.04, albedo, metallic);
    float3 specularIBL = f0 * envBRDF.r + envBRDF.g;
    
    float3 specular = prefilteredColor * specularIBL;
    float4 color = diffuse * float4(albedo, 1) + float4(specular, 1);
    color *= ao;
      

    return color;
}
fragment float4 fragment_IBL_deff(VertexOut in [[stage_in]],
//                             sampler textureSampler [[sampler(0)]],
                             constant Material &material [[buffer(BufferIndexMaterials)]],
                             constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
                             texture2d<float> albedoTexture [[texture(0)]],
                             texture2d<float> normalTexture [[texture(1)]],
                             texture2d<float> positionTexture [[texture(2)]],
                             texture2d<float> materialPackTexture [[texture(3)]],
                             texturecube<float> skybox [[texture(BufferIndexSkybox)]],
                             texturecube<float> skyboxDiffuse [[texture(BufferIndexSkyboxDiffuse)]],
                             texture2d<float> brdfLut [[texture(BufferIndexBRDFLut)]]
                             ){
    
    constexpr sampler s(min_filter::linear, mag_filter::linear);
    float3 albedo = albedoTexture.sample(s, in.texCoords).xyz;
    float3 normal = normalTexture.sample(s, in.texCoords).xyz;
    float3 position = positionTexture.sample(s, in.texCoords).xyz;
    float4 MatPack = materialPackTexture.sample(s, in.texCoords);
    float metallic = MatPack.x;
    float roughness = MatPack.y;
    float ambientOcclusion = MatPack.z;
    float shadow = MatPack.a;
    
    float3 viewDirection = normalize(fragmentUniforms.cameraPosition - position);

  

  float4 diffuse = skyboxDiffuse.sample(s, normal);
  diffuse = mix(pow(diffuse, 0.5), diffuse, metallic);

  float3 textureCoordinates = reflect(viewDirection, normal);

  float3 prefilteredColor = skybox.sample(s, textureCoordinates,
                                          level(roughness * 10)).rgb;

  float nDotV = saturate(dot(normal, normalize(-viewDirection)));
  float2 envBRDF = brdfLut.sample(s, float2(roughness, nDotV)).rg;
  
  float3 f0 = mix(0.04, albedo, metallic);
  float3 specularIBL = f0 * envBRDF.r + envBRDF.g;
  
  float3 specular = prefilteredColor * specularIBL;
  float4 color = diffuse * float4(albedo, 1) + float4(specular, 1);
  color *= ambientOcclusion;
    
    color *= shadow;

  return color;

}







