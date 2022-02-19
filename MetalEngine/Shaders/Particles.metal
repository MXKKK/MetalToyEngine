//
//  Particles.metal
//  MetalEngine
//
//  Created by 马西开 on 2021/11/29.
//

#include <metal_stdlib>
using namespace metal;
#import "../Common.h"

struct Particle{
    float3 startPosition;
    float3 position;
    float3 direction;
    float speed;
    float4 color;
    float age;
    float life;
    float size;
    float scale;
    float startScale;
    float endScale;

};

struct VertexOut{
    float4 position [[position]];
    float point_size [[point_size]];
    float4 color;
};

kernel void compute_particles(device Particle *particles [[buffer(0)]],
                              uint id [[thread_position_in_grid]]){
    float3 velocity = particles[id].speed * particles[id].direction;
    
    particles[id].position += velocity;
    particles[id].age += 1.0;
    float age = particles[id].age / particles[id].life;
    particles[id].scale = mix(particles[id].startScale, particles[id].endScale, age);
    
    if(particles[id].age > particles[id].life){
        particles[id].position = particles[id].startPosition;
        particles[id].age = 0;
        particles[id].scale = particles[id].startScale;
    }
    
}

vertex VertexOut vertex_particle(
                              const device Particle *particles [[buffer(BufferIndexParticles)]],
                              constant float3 &emitterPosition [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
                              constant FragmentUniforms &fragUniforms [[buffer(BufferIndexFragmentUniforms)]],
                              uint instance [[instance_id]]
                              ) {
    VertexOut out;
    float4 position = float4(particles[instance].position + emitterPosition, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    float3 eyePos = (uniforms.viewMatrix * uniforms.modelMatrix * position).xyz;
    
    float dis = distance(fragUniforms.cameraPosition, eyePos);
    out.point_size = particles[instance].size * particles[instance].scale * (1 - dis / 20.0);
    out.color = particles[instance].color;
    return out;
    
}

fragment float4 fragment_particle(
                                  VertexOut in [[stage_in]],
                                  float2 point [[point_coord]]
                                  ){
    float2 texCoord = point * 2.0 - 1.0;
    float r = length(texCoord);
    if(r > 1.0){
        discard_fragment();
    }
    float alpha = smoothstep(1.0, 0.0, r);
    float4 color = in.color;
    color.a = alpha;
    return color;
}
                                  
                                  
