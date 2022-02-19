//
//  Terrains.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/11/22.
//

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"

float calc_distance(float3 pointA, float3 pointB, float3 camera_position, float4x4 modelMatrix){
    float3 positionA = (modelMatrix * float4(pointA, 1)).xyz;
    float3 positionB = (modelMatrix * float4(pointB, 1)).xyz;
    float3 midpoint = (positionA + positionB) * 0.5;
    
    float camera_distance = distance(camera_position, midpoint);
    return camera_distance;
}
kernel void
    tessellation_main(constant float* edge_factors [[buffer(0)]],
                      constant float* inside_factors [[buffer(1)]],
                      constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                      constant FragmentUniforms& fragUniforms [[buffer(BufferIndexFragmentUniforms)]],
                      device MTLQuadTessellationFactorsHalf*
                                                factors [[buffer(2)]],
                      constant float3* control_points [[buffer(3)]],
                      constant Terrain_Uniform &terrain [[buffer(BufferIndexTerrain)]],
                      uint pid [[thread_position_in_grid]]){
        uint index = pid * 4;
        
        float totalTessellation = 0;
        for(int i = 0; i < 4; i++){
            int pointAIndex = i;
            int pointBIndex = i + 1;
            if(pointAIndex == 3){
                pointBIndex = 0;
            }
            int edgeIndex = pointBIndex;
            float cameraDistance =
                   calc_distance(control_points[pointAIndex + index],
                                 control_points[pointBIndex + index],
                                 fragUniforms.cameraPosition.xyz,
                                 uniforms.modelMatrix);
            float tessellation =
                max(4.0, terrain.maxTessellation / cameraDistance);
            factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
            totalTessellation += tessellation;


        }
        
        factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
        factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
       

    }


kernel void
heightToNormal(texture2d<float, access::read> heightMap [[texture(0)]],
               texture2d<float, access::write> normalMap [[texture(1)]],
               uint2 id [[thread_position_in_grid ]]){
    int h = heightMap.get_height();
    int w = heightMap.get_width();
    float scale = 8.0;
    float h1_u = heightMap.read(id - uint2(1,0)).r;
    float h2_u = heightMap.read(id + uint2(1,0)).r;
    float deltaU = 1.0 / float(w);
    float deltaV = 1.0 / float(h);
    
    float3 tangentU( 2 * deltaU, 0.0, (h2_u - h1_u) * scale);
    
    
    float h1_v = heightMap.read(id - uint2(0,1)).r;
    float h2_v = heightMap.read(id + uint2(0,1)).r;
    
    float3 tangentV(0.0, 2 * deltaV, (h2_v - h1_v) * scale);
    float3 normal = normalize(cross(tangentU, tangentV));
    //normal.z *= -1;
    float4 color(normal * 0.5 + 0.5, 1.0);
    normalMap.write(color,id);
    
    
}


struct VertexOut {
  float4 position [[position]];
  float4 color;
    float3 normal;
  float height;
  float2 uv;
  float slope;
};

struct ControlPoint {
  float4 position [[attribute(0)]];
};


[[patch(quad, 4)]]
vertex VertexOut
vertex_terrains(patch_control_point<ControlPoint> control_points [[stage_in]],
               constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
               texture2d<float> heightMap [[texture(heightTexture)]],
               texture2d<float> slopeMap [[texture(slopeTexture)]],
                texture2d<float> normalMap [[texture(NormalTexture)]],
                constant Terrain_Uniform &terrain [[buffer(BufferIndexTerrain)]],
               float2 patch_coord [[position_in_patch]]
               )
{
    float u = patch_coord.x;
    float v = patch_coord.y;
    
    float2 top = mix(control_points[0].position.xz,
                     control_points[1].position.xz, u);
    float2 bottom = mix(control_points[3].position.xz,
                        control_points[2].position.xz, u);
    
      
    VertexOut out;
    float2 interpolated = mix(top, bottom, v);
    float4 position = float4(interpolated.x, 0.0,
                             interpolated.y, 1.0);
   
    
    float2 xy = (position.xz + terrain.size / 2.0) / terrain.size;
    
    constexpr sampler sample;
    float3 normal = normalMap.sample(sample,xy).xzy;
    normal = normalize(normal * 2.0 - 1.0);
    //normal.z *= -1;
    //normal.y *= -1;
    float4 color = heightMap.sample(sample, xy);
    //out.color = float4(color.r);
    out.uv = xy;
    
    
    float height = (color.r * 2 - 1) * terrain.height;
    out.height = height;
    position.y = height;
    color = slopeMap.sample(sample, xy);
    out.slope = color.r;
    
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    out.normal = normal;

    //out.color = float4(u, v, 0, 1);
    
    return out;

}

fragment float4
fragment_terrains(VertexOut in [[stage_in]],
                  constant Light_Uniform *lights [[buffer(BufferIndexLights)]],
                  texture2d<float> grassColor [[texture(grassTexture)]],
                  texture2d<float> snowColor [[texture(snowTexture)]],
                  texture2d<float> cliffColor [[texture(cliffTexture)]]
                 
)
{
    constexpr sampler sample(filter::linear, address::repeat);
    float tiling = 16.0;
    float4 color;
    Light_Uniform light = lights[0];
    float3 lightDirection = normalize(light.position);
    float nDotl = max(0.001, saturate(dot(in.normal, lightDirection)));
    if (in.height < -0.6) {
      color = grassColor.sample(sample, in.uv * tiling);
    } else if (in.height < -0.4) {
        float factor = (in.height + 0.6) / 0.2;
      color = mix(grassColor.sample(sample, in.uv * tiling), cliffColor.sample(sample, in.uv * tiling), factor);
    } else if (in.height < -0.2 || in.slope >= 0.1){
      color =  cliffColor.sample(sample, in.uv * tiling);
    }
    else{
        color = snowColor.sample(sample, in.uv * tiling);
    }
    
   
    return float4(color.rgb * light.color * nDotl, 1.0);
    //return float4((in.normal + 1.0 ) / 2.0 ,1.0);
}

fragment float4
fragment_terrains_IBL(VertexOut in [[stage_in]],
                
                  constant Light_Uniform *lights [[buffer(BufferIndexLights)]],
                  texture2d<float> grassColor [[texture(grassTexture)]],
                  texture2d<float> snowColor [[texture(snowTexture)]],
                  texture2d<float> cliffColor [[texture(cliffTexture)]],
                  texturecube<float> skyboxDiffuse [[texture(BufferIndexSkyboxDiffuse)]]
                 
)
{
    constexpr sampler sample(filter::linear, address::repeat);
    float tiling = 16.0;
    float4 color;
    float4 diffuse = skyboxDiffuse.sample(sample, in.normal);
    
   
    if (in.height < -0.6) {
      color = grassColor.sample(sample, in.uv * tiling);
    } else if (in.height < -0.4) {
        float factor = (in.height + 0.6) / 0.2;
      color = mix(grassColor.sample(sample, in.uv * tiling), cliffColor.sample(sample, in.uv * tiling), factor);
    } else if (in.height < -0.2 || in.slope >= 0.1){
      color =  cliffColor.sample(sample, in.uv * tiling);
    }
    else{
        color = snowColor.sample(sample, in.uv * tiling);
    }
    
   
    return diffuse * float4(color.rgb , 1.0);
    //return float4((in.normal + 1.0 ) / 2.0 ,1.0);
}


[[patch(quad, 4)]]
vertex float4
vertex_terrains_shadow(patch_control_point<ControlPoint> control_points [[stage_in]],
               constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
               texture2d<float> heightMap [[texture(heightTexture)]],
                constant Terrain_Uniform &terrain [[buffer(BufferIndexTerrain)]],
               float2 patch_coord [[position_in_patch]]
               )
{
    float u = patch_coord.x;
    float v = patch_coord.y;
    
    float2 top = mix(control_points[0].position.xz,
                     control_points[1].position.xz, u);
    float2 bottom = mix(control_points[3].position.xz,
                        control_points[2].position.xz, u);
    
      
    VertexOut out;
    float2 interpolated = mix(top, bottom, v);
    float4 position = float4(interpolated.x, 0.0,
                             interpolated.y, 1.0);
    
    float2 xy = (position.xz + terrain.size / 2.0) / terrain.size;
    
    constexpr sampler sample;
    float4 color = heightMap.sample(sample, xy);
    //out.color = float4(color.r);
    out.uv = xy;
    
    
    float height = (color.r * 2 - 1) * terrain.height;
    out.height = height;
    position.y = height;
    
    
    return uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;



}
