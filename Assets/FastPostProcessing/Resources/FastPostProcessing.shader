Shader "Demonixis/FastPostProcessing"
{
	Properties
	{
		_MainTex("Base (RGB)", 2D) = "white" {}
	}

	CGINCLUDE
	#include "UnityCG.cginc"
	#pragma multi_compile __ SHARPEN
    #pragma multi_compile __ BLOOM 
	#pragma multi_compile __ TONEMAPPER_ACES
	#pragma multi_compile __ TONEMAPPER_PHOTOGRAPHIC
	#pragma multi_compile __ TONEMAPPER_HABLE
	#pragma multi_compile __ TONEMAPPER_DAWSON
    #pragma multi_compile __ TONEMAPPER_REINHART
	#pragma multi_compile __ DITHERING
	#pragma multi_compile __ USERLUT_TEXTURE
    #pragma multi_compile __ GAMMA_CORRECTION
	uniform sampler2D _MainTex;
	uniform half4 _MainTex_TexelSize;
	uniform	half4 _MainTex_ST;
	uniform float _SharpenSize;
	uniform float _SharpenIntensity;
	uniform float _BloomSize;
	uniform float _BloomAmount;
	uniform float _BloomPower;
	uniform float _Exposure;
	sampler2D _UserLutTex;
	uniform half4 _UserLutParams;

	struct v2f_data
	{
		float4 pos : SV_POSITION;
		half2  uv  : TEXCOORD0;
#if UNITY_UV_STARTS_AT_TOP
		half2  uv2 : TEXCOORD1;
#endif
	};

	v2f_data vertFunction(appdata_img v)
	{
		v2f_data o;

		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv = UnityStereoScreenSpaceUVAdjust(v.texcoord, _MainTex_ST);

#if UNITY_UV_STARTS_AT_TOP
		o.uv2 = o.uv;
		if (_MainTex_TexelSize.y < 0.0)
			o.uv.y = 1.0 - o.uv.y;
#endif
		return o;
	}

#if TONEMAPPER_ACES
	half3 tonemapACES(half3 color)
	{
		color *= _Exposure;
		
		const half3 a = 2.51f;
		const half3 b = 0.03f;
		const half3 c = 2.43f;
		const half3 d = 0.59f;
		const half3 e = 0.14f;
		return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
	}
#endif

#if TONEMAPPER_PHOTOGRAPHIC
	half3 tonemapPhotographic(half3 color)
	{
		color *= _Exposure;
		return 1.0 - exp2(-color);
	}
#endif

#if TONEMAPPER_HABLE
	half3 tonemapHable(half3 color)
	{
		const half a = 0.15;
		const half b = 0.50;
		const half c = 0.10;
		const half d = 0.20;
		const half e = 0.02;
		const half f = 0.30;
		const half w = 11.2;

		color *= _Exposure * 2.0;
		half3 curr = ((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - e / f;
		color = w;
		half3 whiteScale = 1.0 / (((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - e / f);
		return curr * whiteScale;
	}

#endif

#if TONEMAPPER_DAWSON
	half3 tonemapHejlDawson(half3 color)
	{
		const half a = 6.2;
		const half b = 0.5;
		const half c = 1.7;
		const half d = 0.06;

		color *= _Exposure;
		color = max((0.0).xxx, color - (0.004).xxx);
		color = (color * (a * color + b)) / (color * (a * color + c) + d);
		return color * color;
	}
#endif

#if TONEMAPPER_REINHART
	half3 tonemapReinhard(half3 color)
	{
		half lum = Luminance(color);
		half lumTm = lum * _Exposure;
		half scale = lumTm / (1.0 + lumTm);
		return color * scale / lum;
	}
#endif

#if USERLUT_TEXTURE
	half3 applyLUT(sampler2D tex, half3 uvw, half3 scaleOffset)
	{
		uvw.z *= scaleOffset.z;
		half shift = floor(uvw.z);
		uvw.xy = uvw.xy * scaleOffset.z * scaleOffset.xy + scaleOffset.xy * 0.5;
		uvw.x += shift * scaleOffset.y;
		uvw.xyz = lerp(tex2D(tex, uvw.xy).rgb, tex2D(tex, uvw.xy + half2(scaleOffset.y, 0)).rgb, uvw.z - shift);
		return uvw;
	}
#endif

	half4 fragFunction(v2f_data i) : SV_Target
	{
		half2 uv = i.uv;
#if UNITY_UV_STARTS_AT_TOP
		uv = i.uv2;
#endif
		
		half3 col = tex2D(_MainTex, uv).rgb;

#if SHARPEN
		col = tex2D(_MainTex, uv).rgb;
		col -= tex2D(_MainTex, uv + _SharpenSize).rgb * 7.0 * _SharpenIntensity;
		col += tex2D(_MainTex, uv - _SharpenSize).rgb * 7.0 * _SharpenIntensity;
#endif

#if BLOOM
		float size = 1 / _BloomSize;
		float4 sum = 0;
		float3 bloom;

		for (int i = -3; i < 3; i++)
		{
			sum += tex2D(_MainTex, uv + float2(-1, i) * size) * _BloomAmount;
			sum += tex2D(_MainTex, uv + float2(0, i) * size) * _BloomAmount;
			sum += tex2D(_MainTex, uv + float2(1, i) * size) * _BloomAmount;
		}

		if (col.r < 0.3 && col.g < 0.3 && col.b < 0.3)
		{
			bloom = sum.rgb * sum.rgb * 0.012 + col;
		}
		else
		{
			if (col.r < 0.5 && col.g < 0.5 && col.b < 0.5)
			{
				bloom = sum.xyz * sum.xyz * 0.009 + col;
			}
			else
			{
				bloom = sum.xyz * sum.xyz * 0.0075 + col;
			}
		}

		col = lerp(col, bloom, _BloomPower);
#endif

#if TONEMAPPER_ACES
		col = tonemapACES(col);
#elif TONEMAPPER_PHOTOGRAPHIC
		col = tonemapPhotographic(col);
#elif TONEMAPPER_HABLE
		col = tonemapHable(col);
#elif TONEMAPPER_DAWSON
		col = tonemapHejlDawson(col);
#elif TONEMAPPER_REINHART
		col = tonemapReinhard(col);
#endif

#if GAMMA_CORRECTION
		col = pow(col, 0.454545);
#endif

#if DITHERING
		// Interleaved Gradient Noise from http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare (slide 122)
		half3 magic = float3(0.06711056, 0.00583715, 52.9829189);
		half gradient = frac(magic.z * frac(dot(uv / _MainTex_TexelSize, magic.xy))) / 255.0;
		col.rgb -= gradient.xxx;
#endif

#if USERLUT_TEXTURE
		half3 lc = applyLUT(_UserLutTex, saturate(col.rgb), _UserLutParams.xyz);
		col = lerp(col, lc, _UserLutParams.w);
#endif

		return half4(col, 1.0);
	}

	ENDCG
	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
		{
CGPROGRAM
#pragma vertex vertFunction
#pragma fragment fragFunction
ENDCG
		}
	}
}