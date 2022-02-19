//
//  Common.h
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

#ifndef Common_h
#define Common_h

#import <simd/simd.h>

typedef enum{
    unused = 0,
    Sunlight = 1,
    Spotlight = 2,
    Pointlight = 3,
    Ambientlight = 4
}LightType;

typedef struct{
    vector_float3 position;
    vector_float3 color;
    vector_float3 specularColor;
    float intensity;
    vector_float3 attenuation;
    LightType type;
    float coneAngle;
    vector_float3 coneDirection;
    float coneAttenuation;
}Light_Uniform;

typedef struct{
    vector_float2 size;
    float height;
    uint maxTessellation;
} Terrain_Uniform;

typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 inv_viewMatrix;
    //use for shadow
    matrix_float4x4 shadowMatrix;
    matrix_float3x3 normalMatrix;
    matrix_float3x3 viewNormalMatrix;
    matrix_float3x3 inv_viewNormalMatrix;
    matrix_float3x3 mvNormalMatrix;
}Uniforms;

typedef enum{
    forwardRendering = 0,
    deferredRendering = 1
    
}RenderType;

typedef enum {
  BaseColorTexture = 0,
  NormalTexture = 1,
  RoughnessTexture = 2,
  MetallicTexture = 3,
  AOTexture = 4,
  ShadowMap = 5,
  heightTexture = 6,
  cliffTexture = 7,
  grassTexture = 8,
  snowTexture = 9,
  slopeTexture = 10
} Textures;

typedef struct {
    vector_float3 baseColor;
    vector_float3 specularColor;
    float roughness;
    float metallic;
    vector_float3 ambientOcculusion;
    float shininess;
}Material;

typedef enum {
  Position = 0,
  Normal = 1,
  UV = 2,
  Tangent = 3,
  Bitangent = 4,
  Color = 5,
  Joints = 6,
  Weights = 7
} Attributes;

typedef enum {
  BufferIndexVertices = 0,
  BufferIndexUniforms = 11,
  BufferIndexLights = 12,
  BufferIndexFragmentUniforms = 13,
  BufferIndexMaterials = 14,
  BufferIndexSkybox = 15,
  BufferIndexSkyboxDiffuse = 16,
  BufferIndexBRDFLut = 17,
  BufferIndexFog = 18,
  BufferIndexTerrain = 19,
  BufferIndexParticles = 20,
  BufferIndexHasSkybox = 21,
  BufferIndexSamples = 22
} BufferIndices;

typedef struct {
  uint lightCount;
  vector_float3 cameraPosition;
  uint tiling;
} FragmentUniforms;

typedef enum {
    NoShadow = 0,
    hardShadow = 1,
    PCF = 2
}ShadowType;

typedef struct{
    float zThickness;
    float nearPlaneZ;
    float farPlaneZ;
    float stride;
    float maxSteps;
    float maxDistance;
    float strideZCutoff;
    vector_float2 depthBufferSize;
    
    float numMips;
    float fadeStart;
    float fadeEnd;
    float sslr_padding0;
} ssrParam;
#endif /* Common_h */
