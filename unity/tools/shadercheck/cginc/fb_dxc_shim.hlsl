// harness only: DX9-style samplers for DXC (Unity compiles CG programs with fxc, which has them)
struct fb_sampler2D_shim { Texture2D t; SamplerState s; };
struct fb_sampler3D_shim { Texture3D t; SamplerState s; };
struct fb_samplerCUBE_shim { TextureCube t; SamplerState s; };
#define sampler2D fb_sampler2D_shim
#define sampler3D fb_sampler3D_shim
#define samplerCUBE fb_samplerCUBE_shim
float4 tex2D(fb_sampler2D_shim x, float2 uv) { return x.t.Sample(x.s, uv); }
float4 tex2D(fb_sampler2D_shim x, float2 uv, float2 dx, float2 dy) { return x.t.SampleGrad(x.s, uv, dx, dy); }
float4 tex2Dlod(fb_sampler2D_shim x, float4 uv) { return x.t.SampleLevel(x.s, uv.xy, uv.w); }
float4 tex2Dbias(fb_sampler2D_shim x, float4 uv) { return x.t.SampleBias(x.s, uv.xy, uv.w); }
float4 tex2Dgrad(fb_sampler2D_shim x, float2 uv, float2 dx, float2 dy) { return x.t.SampleGrad(x.s, uv, dx, dy); }
float4 tex2Dproj(fb_sampler2D_shim x, float4 uv) { return x.t.Sample(x.s, uv.xy / uv.w); }
float4 tex2Dproj(fb_sampler2D_shim x, float3 uv) { return x.t.Sample(x.s, uv.xy / uv.z); }
float4 tex3D(fb_sampler3D_shim x, float3 uv) { return x.t.Sample(x.s, uv); }
float4 texCUBE(fb_samplerCUBE_shim x, float3 uv) { return x.t.Sample(x.s, uv); }
float4 texCUBElod(fb_samplerCUBE_shim x, float4 uv) { return x.t.SampleLevel(x.s, uv.xyz, uv.w); }
float4 texCUBEbias(fb_samplerCUBE_shim x, float4 uv) { return x.t.SampleBias(x.s, uv.xyz, uv.w); }
