//
//  FXAA.metal
//  MetalEngine
//
//  Created by 马西开 on 2022/1/24.
//

//参考 https://github.com/Raphael2048/AntiAliasing/blob/main/Assets/Shaders/FXAA/FXAASelf.shader
#include <metal_stdlib>
using namespace metal;
#import "../Common.h"

#define _ContrastThreshold 0.0625f
#define _RelativeThreshold 0.125f

#define _SearchSteps 15
#define _Guess 8


struct VertexOut{
    float4 position [[position]];
    float2 texCoords;
};

float FxaaLuma(float3 rgb) {
return rgb.y * (0.587/0.299) + rgb.x; }

fragment float4 FXAAFrag(VertexOut in [[stage_in]],
                                texture2d<float> inputTexture [[texture(0)]]
                                )
{
    constexpr sampler s(filter::linear);
    float2 texelSize(1.0f / inputTexture.get_width(), 1.0f / inputTexture.get_height());
    float2 uv = in.texCoords;
    float3 origin = inputTexture.sample(s, uv).rgb;
    float M = FxaaLuma(origin);
    float E = FxaaLuma(inputTexture.sample(s, uv + float2( texelSize.x, 0)).rgb);
    float N = FxaaLuma(inputTexture.sample(s, uv + float2( 0, texelSize.y)).rgb);
    float W = FxaaLuma(inputTexture.sample(s, uv + float2(-texelSize.x, 0)).rgb);
    float S = FxaaLuma(inputTexture.sample(s, uv + float2( 0, -texelSize.y)).rgb);
    float NW = FxaaLuma(inputTexture.sample(s, uv + float2( -texelSize.x, texelSize.y)).rgb);
    float NE = FxaaLuma(inputTexture.sample(s, uv + float2( texelSize.x, texelSize.y)).rgb);
    float SW = FxaaLuma(inputTexture.sample(s, uv + float2( -texelSize.x, -texelSize.y)).rgb);
    float SE = FxaaLuma(inputTexture.sample(s, uv + float2( texelSize.x, -texelSize.y)).rgb);
    
    //计算对比度
    float MaxLuma = max(max(max(N, E), max(W, S)), M);
    float MinLuma = min(min(min(N, E), min(W, S)), M);
    float Contrast = MaxLuma - MinLuma;
    
    //对比度很小则提前终止
    if(Contrast < max(_ContrastThreshold, MaxLuma * _RelativeThreshold))
    {
        return float4(origin, 1.0f);
    }
    
    //计算锯齿方向，水平or垂直
    float Vertical   = abs(N + S - 2 * M) * 2 + abs(NE + SE - 2 * E) + abs(NW + SW - 2 * W);
    float Horizontal = abs(E + W - 2 * M) * 2 + abs(NE + NW - 2 * N) + abs(SE + SW - 2 * S);
    bool IsHorizontal = Vertical > Horizontal;
    //混合的方向
    float2 PixelStep = IsHorizontal ? float2(0, texelSize.y) : float2(texelSize.x, 0);
    //混合方向的正负
    float Positive = abs((IsHorizontal ? N : E) - M);
    float Negative = abs((IsHorizontal ? S : W) - M);
    //锯齿两侧亮度变化的梯度
    float Gradient, OppositeLuminance;
    if(Positive > Negative){
        Gradient = Positive;
        OppositeLuminance = IsHorizontal ? N : E;
    }
    else
    {
        PixelStep = -PixelStep;
        Gradient = Negative;
        OppositeLuminance = IsHorizontal ? S : W;
    }
    
    //基于亮度的混合系数计算
    float Filter = 2 * (N + E + S + W) + NE + NW + SE + SW;
    Filter = Filter / 12;
    Filter = abs(Filter - M);
    Filter = saturate(Filter / Contrast);
    
    //基于亮度的混合系数值
    float PixelBlend = smoothstep(0, 1, Filter);
    PixelBlend = PixelBlend * PixelBlend;
    
    //基于边界的混合系数计算
    float2 UVEdge = UV;
    UVEdge += PixelStep * 0.5f;
    float2 EdgeStep = IsHorizontal ? float2(texelSize.x, 0) : float2(0, texelSize.y);
    
    //沿锯齿边界两侧进行搜索直到找到边界
    float EdgeLuminance = (M + OppositeLuminance)*0.5f;
    float GradientThreshold = Gradient * 0.25f;
    float PLuminanceDelta, NLuminanceDelta, PDistance, NDistance;
    int i;
    
    for(i = 1; i <= _SearchSteps; ++i){
        PLuminanceDelta = FxaaLuma(inputTexture.sample(s, UVEdge + i * EdgeStep).rgb) - EdgeLuminance;
        if(abs(PLuminanceDelta) > GradientThreshold){
            PDistance = i * (IsHorizontal ? EdgeStep.x : EdgeStep.y);
            break;
        }
    }
    if( i == _SearchSteps + 1)
    {
        PDistance = (IsHorizontal ? EdgeStep.x : EdgeStep.y) * _Guess;
    }
    
    for(i = 1; i <= _SearchSteps; ++i){
        NLuminanceDelta = FxaaLuma(inputTexture.sample(s, UVEdge - i * EdgeStep).rgb) - EdgeLuminance;
        
        if(abs(NLuminanceDelta) > GradientThreshold){
            NDistance = i * (IsHorizontal ? EdgeStep.x : EdgeStep.y);
            break;
        }
    }
    if( i == _SearchSteps + 1)
    {
        NDistance = (IsHorizontal ? EdgeStep.x : EdgeStep.y) * _Guess;
    }
    
    //计算基于边界的混合系数，如果边界方向错误，直接设为0，如果方向正确，按照相对的距离来估算混合系数
    float EdgeBlend;
    if(PDistance < NDistance){
        if(sign(PLuminanceDelta) == sign(M - EdgeLuminance)){
            EdgeBlend = 0;
        }else
        {
            EdgeBlend = 0.5f - PDistance / (PDistance + NDistance);
        }
    }else{
        if(sign(NLuminanceDelta) == sign(M - EdgeLuminance)){
            EdgeBlend = 0;
        }else
        {
            EdgeBlend = 0.5f - NDistance / (PDistance + NDistance);
        }
    }
    
    //从基于亮度与基于边界的混合系数中取大的
    float FinalBlend = max(PixelBlend, EdgeBlend);
    float4 Result = inputTexture.sample(s, uv + PixelStep * FinalBlend);
    return Result;
    
}
